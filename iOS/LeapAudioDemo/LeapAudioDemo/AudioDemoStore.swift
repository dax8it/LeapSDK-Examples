import AVFoundation
import Foundation
import LeapSDK
import Observation

enum ModelQuantization: String, CaseIterable, Identifiable {
  // Note: Q4_0 not supported by LeapSDK 0.9.0 for audio models
  case q8 = "Q8_0"
  
  var id: String { rawValue }
  
  var displayName: String {
    switch self {
    case .q8: return "Q8 (Quality, ~2GB)"
    }
  }
}

struct AudioDemoMessage: Identifiable, Equatable {
  let id = UUID()
  let role: ChatMessageRole
  let text: String
  let audioData: Data?

  var isUser: Bool { role == .user }

  static func == (lhs: AudioDemoMessage, rhs: AudioDemoMessage) -> Bool {
    lhs.id == rhs.id && lhs.role == rhs.role && lhs.text == rhs.text
  }
}

@Observable
@MainActor
final class AudioDemoStore {
  var inputText: String = ""
  var messages: [AudioDemoMessage] = []
  var status: String?
  var streamingText: String = ""
  var isModelLoading = false
  var isGenerating = false
  var isRecording = false
  var selectedQuantization: ModelQuantization = .q8
  var availableQuantizations: [ModelQuantization] = []

  private let playbackManager = AudioPlaybackManager()
  private let recorder = AudioRecorder()
  private var conversation: Conversation?
  private var modelRunner: ModelRunner?
  private var streamingTask: Task<Void, Never>?

  init() {
    playbackManager.prepareSession()
  }

  func setupModel() async {
    detectAvailableModels()
    
    // If selected model isn't available, switch to first available
    if !availableQuantizations.contains(selectedQuantization),
       let first = availableQuantizations.first {
      selectedQuantization = first
    }
    
    await loadModel()
  }
  
  func switchModel(to quantization: ModelQuantization) async {
    guard quantization != selectedQuantization || modelRunner == nil else { return }
    selectedQuantization = quantization
    
    // Unload current model
    modelRunner = nil
    conversation = nil
    messages.removeAll()
    
    await loadModel()
  }
  
  private func detectAvailableModels() {
    let bundle = Bundle.main
    availableQuantizations = ModelQuantization.allCases.filter { quant in
      bundle.url(forResource: "LFM2.5-Audio-1.5B-\(quant.rawValue)", withExtension: "gguf") != nil
    }
    print("Available quantizations: \(availableQuantizations.map { $0.rawValue })")
  }
  
  private func loadModel() async {
    guard modelRunner == nil else { return }
    isModelLoading = true
    let quant = selectedQuantization.rawValue
    status = "Loading \(selectedQuantization.displayName) model..."

    guard let modelURL = findModelURL(quantization: quant) else {
      status = "No \(quant) model found. Add model files first."
      isModelLoading = false
      return
    }

    do {
      let bundle = Bundle.main
      let mmProjPath = bundle.url(forResource: "mmproj-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
      let audioTokenizerPath = bundle.url(forResource: "tokenizer-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
      let vocoderPath = bundle.url(forResource: "vocoder-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
      
      print("Loading \(quant) model:")
      print("  mmProjPath: \(mmProjPath ?? "nil")")
      print("  audioTokenizerPath: \(audioTokenizerPath ?? "nil")")
      print("  vocoderPath: \(vocoderPath ?? "nil")")
      
      var options = LiquidInferenceEngineOptions(
        bundlePath: modelURL.path(),
        contextSize: 8192,
        nGpuLayers: 0,
        mmProjPath: mmProjPath,
        audioDecoderPath: vocoderPath,
        audioTokenizerPath: audioTokenizerPath
      )
      let runner = try Leap.load(options: options)
      modelRunner = runner
      conversation = Conversation(
        modelRunner: runner,
        history: [
          ChatMessage(role: .system, content: [.text("Respond with interleaved text and audio.")])
        ])
      messages.append(
        AudioDemoMessage(
          role: .assistant,
          text: "Model loaded: \(selectedQuantization.displayName)",
          audioData: nil
        )
      )
      status = "Ready (\(selectedQuantization.displayName))"
    } catch {
      status = "Failed to load model: \(error.localizedDescription)"
    }

    isModelLoading = false
  }

  func sendTextPrompt() {
    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    inputText = ""
    let message = ChatMessage(role: .user, content: [.text(trimmed)])
    appendUserMessage(text: trimmed, audioData: nil)
    streamResponse(for: message)
  }

  func toggleRecording() {
    if isRecording {
      recorder.stop()
      isRecording = false
      guard let capture = recorder.capture() else {
        status = "No audio captured."
        return
      }
      sendAudioPrompt(samples: capture.samples, sampleRate: capture.sampleRate)
    } else {
      do {
        try recorder.start()
        isRecording = true
        status = "Recording..."
      } catch {
        status = "Recording failed: \(error.localizedDescription)"
      }
    }
  }

  func cancelRecording() {
    recorder.cancel()
    isRecording = false
    status = "Recording cancelled."
  }

  func playAudio(_ data: Data) {
    playbackManager.play(wavData: data)
  }

  private func sendAudioPrompt(samples: [Float], sampleRate: Int) {
    guard !samples.isEmpty else {
      status = "Audio capture was empty."
      return
    }

    let content = ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate)
    let chatMessage = ChatMessage(role: .user, content: [content])

    var display = "Audio prompt (\(samples.count) samples @ \(sampleRate) Hz)"
    if samples.count < sampleRate / 4 {
      display = "Audio prompt (~\(samples.count) samples)"
    }

    let audioData: Data?
    if case .audio(let data) = content {
      audioData = data
    } else {
      audioData = nil
    }

    appendUserMessage(text: display, audioData: audioData)
    streamResponse(for: chatMessage)
  }

  private func appendUserMessage(text: String, audioData: Data?) {
    messages.append(AudioDemoMessage(role: .user, text: text, audioData: audioData))
  }

  private func streamResponse(for message: ChatMessage) {
    guard let modelRunner else {
      status = "Model not ready yet."
      return
    }

    // LFM2.5 audio engine requires fresh conversation for each turn
    // ("messages are not replayable, need to start a new dialog")
    let freshConversation = Conversation(
      modelRunner: modelRunner,
      history: [
        ChatMessage(role: .system, content: [.text("Respond with interleaved text and audio.")])
      ])
    conversation = freshConversation

    playbackManager.reset()
    streamingTask?.cancel()
    streamingText = ""
    status = "Awaiting response..."
    isGenerating = true

    let stream = freshConversation.generateResponse(message: message)

    streamingTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in stream {
          if Task.isCancelled { break }
          await MainActor.run {
            self.handle(event)
          }
        }
      } catch {
        await MainActor.run {
          self.handleGenerationError(error)
        }
      }
      await MainActor.run {
        self.streamingTask = nil
      }
    }
  }

  private func handle(_ event: MessageResponse) {
    switch event {
    case .chunk(let text):
      streamingText.append(text)
    case .reasoningChunk:
      status = "Thinking..."
    case .audioSample(let samples, let sampleRate):
      playbackManager.enqueue(samples: samples, sampleRate: sampleRate)
      status = "Streaming audio..."
    case .functionCall(let calls):
      status = "Received function call: \(calls.count)"
    case .complete(let completion):
      finish(with: completion)
    }
  }

  private func finish(with completion: MessageCompletion) {
    print("=== Response Complete ===")
    print("Finish reason: \(completion.finishReason)")
    print("Content count: \(completion.message.content.count)")
    for (index, content) in completion.message.content.enumerated() {
      switch content {
      case .text(let t): print("  [\(index)] text: \(t.prefix(100))...")
      case .audio(let d): print("  [\(index)] audio: \(d.count) bytes")
      default: print("  [\(index)] other content type")
      }
    }
    
    let text = completion.message.content.compactMap { content -> String? in
      if case .text(let value) = content {
        return value
      }
      return nil
    }.joined()

    let audioData = completion.message.content.firstAudioData
    print("Final text: '\(text.prefix(200))'")
    print("Audio data: \(audioData?.count ?? 0) bytes")
    messages.append(
      AudioDemoMessage(
        role: .assistant,
        text: text.isEmpty ? "(audio response)" : text,
        audioData: audioData
      )
    )
    streamingText = ""
    isGenerating = false
    status =
      audioData != nil
      ? "Response complete with audio."
      : finishReasonDescription(completion.finishReason)

    // Audio already played via streaming (enqueue in handle(.audioSample))
    // Don't play again here to avoid duplicate playback
  }

  private func handleGenerationError(_ error: Error) {
    isGenerating = false
    streamingText = ""
    status = "Generation failed: \(error.localizedDescription)"
  }

  private func finishReasonDescription(_ reason: GenerationFinishReason) -> String {
    switch reason {
    case .stop:
      return "Response complete."
    case .exceed_context:
      return "Context window exceeded."
    }
  }

  private func findModelURL(quantization: String) -> URL? {
    let bundle = Bundle.main
    let modelName = "LFM2.5-Audio-1.5B-\(quantization)"
    
    print("Bundle: \(bundle.bundlePath)")
    print("Looking for model: \(modelName)")
    
    if let url = bundle.url(forResource: modelName, withExtension: "gguf") {
      print("Found model at: \(url)")
      return url
    }
    if let url = bundle.url(forResource: modelName, withExtension: "gguf", subdirectory: "Resources") {
      print("Found model in Resources: \(url)")
      return url
    }
    
    print("No \(modelName) model found in bundle")
    return nil
  }
}

extension Array where Element == ChatMessageContent {
  fileprivate var firstAudioData: Data? {
    for content in self {
      if case .audio(let data) = content {
        return data
      }
    }
    return nil
  }
}

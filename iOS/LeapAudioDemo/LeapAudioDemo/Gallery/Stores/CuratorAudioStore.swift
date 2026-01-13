import AVFoundation
import Foundation
import LeapSDK
import Observation

struct CuratorMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatMessageRole
    let text: String
    let audioData: Data?
    
    var isUser: Bool { role == .user }
    
    static func == (lhs: CuratorMessage, rhs: CuratorMessage) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role && lhs.text == rhs.text
    }
}

@Observable
@MainActor
final class CuratorAudioStore {
    var inputText: String = ""
    var messages: [CuratorMessage] = []
    var status: String?
    var streamingText: String = ""
    var isModelLoading = false
    var isGenerating = false
    var isRecording = false
    var showDebugPrompt = false
    var lastPromptDebug: String = ""
    var onAudioPlaybackComplete: (() -> Void)?
    
    private var currentArtist: Artist?
    private var currentArtwork: Artwork?
    private var currentArtworks: [Artwork] = []
    
    private let playbackManager = AudioPlaybackManager()
    private let recorder = AudioRecorder()
    private var conversation: Conversation?
    private var modelRunner: ModelRunner?
    private var streamingTask: Task<Void, Never>?
    
    init() {
        playbackManager.prepareSession()
        playbackManager.onPlaybackComplete = { [weak self] in
            Task { @MainActor in
                self?.onAudioPlaybackComplete?()
            }
        }
    }
    
    func speakAboutCurrentArtwork() {
        clearHistoryForAutoplay()
        let prompt = "Tell me about this artwork in 2-3 sentences."
        sendTextPrompt(prompt)
    }
    
    func setContext(artist: Artist?, artwork: Artwork?) {
        currentArtist = artist
        currentArtwork = artwork
        currentArtworks = []
        print("[CuratorAudioStore] Context set: artist=\(artist?.name ?? "nil"), artwork=\(artwork?.title ?? "nil")")
    }
    
    func setContext(artist: Artist?, artworks: [Artwork]) {
        currentArtist = artist
        currentArtwork = nil
        currentArtworks = artworks
        print("[CuratorAudioStore] Context set: artist=\(artist?.name ?? "nil"), artworks=\(artworks.count)")
    }
    
    func clearHistory() {
        messages.removeAll()
        conversation = nil
        streamingText = ""
        lastPromptDebug = ""
        print("[CuratorAudioStore] History cleared")
    }
    
    private func clearHistoryForAutoplay() {
        if messages.count > 4 {
            messages.removeAll()
            conversation = nil
            print("[CuratorAudioStore] Autoplay history cleared to free memory")
        }
    }
    
    private func trimHistoryIfNeeded() {
        if messages.count > 6 {
            let keepCount = 2
            messages = Array(messages.suffix(keepCount))
            print("[CuratorAudioStore] Trimmed history to \(keepCount) messages")
        }
    }
    
    private func buildContextPacket() -> String {
        if let artwork = currentArtwork {
            return CuratorContextBuilder.buildContextPacket(artist: currentArtist, artwork: artwork)
        } else {
            return CuratorContextBuilder.buildGeneralContextPacket(artist: currentArtist, artworks: currentArtworks)
        }
    }
    
    func setupModel() async {
        await loadModel()
    }
    
    private func loadModel() async {
        guard modelRunner == nil else { return }
        isModelLoading = true
        let quant = "Q8_0"
        status = "Loading model..."
        
        guard let modelURL = findModelURL(quantization: quant) else {
            status = "No model found. Add model files first."
            isModelLoading = false
            return
        }
        
        do {
            let bundle = Bundle.main
            let mmProjPath = bundle.url(forResource: "mmproj-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
            let audioTokenizerPath = bundle.url(forResource: "tokenizer-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
            let vocoderPath = bundle.url(forResource: "vocoder-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
            
            print("[CuratorAudioStore] Loading model:")
            print("  modelURL: \(modelURL.path())")
            print("  mmProjPath: \(mmProjPath ?? "nil")")
            print("  audioTokenizerPath: \(audioTokenizerPath ?? "nil")")
            print("  vocoderPath: \(vocoderPath ?? "nil")")
            
            let options = LiquidInferenceEngineOptions(
                bundlePath: modelURL.path(),
                contextSize: 4096,
                nGpuLayers: 0,
                mmProjPath: mmProjPath,
                audioDecoderPath: vocoderPath,
                audioTokenizerPath: audioTokenizerPath
            )
            let runner = try Leap.load(options: options)
            modelRunner = runner
            print("[CuratorAudioStore] Model loaded successfully")
            messages.append(
                CuratorMessage(role: .assistant, text: "Curator ready. Ask me about the exhibition.", audioData: nil)
            )
            status = "Ready"
        } catch {
            print("[CuratorAudioStore] Failed to load model: \(error)")
            status = "Failed to load model: \(error.localizedDescription)"
        }
        
        isModelLoading = false
    }
    
    func sendTextPrompt() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        sendTextPrompt(trimmed)
    }
    
    func sendTextPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let contextPacket = buildContextPacket()
        let instructions = CuratorContextBuilder.curatorInstructions
        let fullText = "\(instructions)\n\n\(contextPacket)\n\nUser question: \(trimmed)"
        
        lastPromptDebug = "INSTRUCTIONS:\n\(instructions)\n\nCONTEXT:\n\(contextPacket)\n\nQUERY:\n\(trimmed)"
        print("[CuratorAudioStore] Text prompt with context (\(fullText.count) chars)")
        
        let message = ChatMessage(role: .user, content: [.text(fullText)])
        appendUserMessage(text: trimmed, audioData: nil)
        streamResponse(for: message)
    }
    
    func stopPlayback() {
        streamingTask?.cancel()
        streamingTask = nil
        playbackManager.reset()
        isGenerating = false
        status = "Ready"
        trimHistoryIfNeeded()
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
        
        let contextPacket = buildContextPacket()
        let instructions = CuratorContextBuilder.curatorInstructions
        let fullContext = "\(instructions)\n\n\(contextPacket)\n\nUser voice question follows:"
        
        let audioContent = ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate)
        let textContent = ChatMessageContent.text(fullContext)
        
        let chatMessage = ChatMessage(role: .user, content: [textContent, audioContent])
        
        lastPromptDebug = "INSTRUCTIONS:\n\(instructions)\n\nCONTEXT (voice):\n\(contextPacket)\n\n[AUDIO INPUT]"
        print("[CuratorAudioStore] Audio prompt with context (\(fullContext.count) chars text + audio)")
        
        var display = "Voice question"
        if samples.count < sampleRate / 4 {
            display = "Voice question (brief)"
        }
        
        let audioData: Data?
        if case .audio(let data) = audioContent {
            audioData = data
        } else {
            audioData = nil
        }
        
        appendUserMessage(text: display, audioData: audioData)
        streamResponse(for: chatMessage)
    }
    
    private func appendUserMessage(text: String, audioData: Data?) {
        messages.append(CuratorMessage(role: .user, text: text, audioData: nil))
    }
    
    private func streamResponse(for message: ChatMessage) {
        guard let modelRunner else {
            status = "Model not ready yet."
            return
        }
        
        let sysPrompt = CuratorContextBuilder.systemPrompt
        print("[CuratorAudioStore] Starting response generation")
        print("[CuratorAudioStore] System prompt: \(sysPrompt)")
        
        let freshConversation = Conversation(
            modelRunner: modelRunner,
            history: [ChatMessage(role: .system, content: [.text(sysPrompt)])]
        )
        conversation = freshConversation
        
        playbackManager.reset()
        streamingTask?.cancel()
        streamingText = ""
        status = "Thinking..."
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
                print("[CuratorAudioStore] Response generation completed")
            } catch {
                print("[CuratorAudioStore] Generation error: \(error)")
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
            status = "Speaking..."
        case .functionCall(let calls):
            status = "Function call: \(calls.count)"
        case .complete(let completion):
            finish(with: completion)
        }
    }
    
    private func finish(with completion: MessageCompletion) {
        let text = completion.message.content.compactMap { content -> String? in
            if case .text(let value) = content { return value }
            return nil
        }.joined()
        
        let audioData = completion.message.content.firstAudioData
        messages.append(
            CuratorMessage(
                role: .assistant,
                text: text.isEmpty ? "(audio response)" : text,
                audioData: nil
            )
        )
        streamingText = ""
        isGenerating = false
        status = audioData != nil ? "Response complete." : finishReasonDescription(completion.finishReason)
        trimHistoryIfNeeded()
    }
    
    private func handleGenerationError(_ error: Error) {
        isGenerating = false
        streamingText = ""
        status = "Error: \(error.localizedDescription)"
    }
    
    private func finishReasonDescription(_ reason: GenerationFinishReason) -> String {
        switch reason {
        case .stop: return "Ready"
        case .exceed_context: return "Context limit reached."
        }
    }
    
    private func findModelURL(quantization: String) -> URL? {
        let bundle = Bundle.main
        let modelName = "LFM2.5-Audio-1.5B-\(quantization)"
        
        if let url = bundle.url(forResource: modelName, withExtension: "gguf") {
            return url
        }
        if let url = bundle.url(forResource: modelName, withExtension: "gguf", subdirectory: "Resources") {
            return url
        }
        return nil
    }
}

private extension Array where Element == ChatMessageContent {
    var firstAudioData: Data? {
        for content in self {
            if case .audio(let data) = content { return data }
        }
        return nil
    }
}

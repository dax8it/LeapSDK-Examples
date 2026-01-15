import AVFoundation
import Foundation
import LeapSDK

/// Thread-safe audio buffer for collecting samples from audio tap
private final class AudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    var sampleRate: Double = 16_000
    
    func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
    }
    
    func flush() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: true)
        return result
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}

/// Manages real-time conversational audio with LFM2.5-Audio model
/// The model natively processes audio and determines speech flow - no external VAD needed
@MainActor
final class ConversationLoop {
    
    // MARK: - State
    
    enum State: String {
        case idle
        case listening      // Recording audio, waiting for model to process
        case processing     // Model is generating response
        case speaking       // Playing model's audio response
    }
    
    // MARK: - Properties
    
    private let engine = AVAudioEngine()
    private let playbackManager = AudioPlaybackManager()
    private let audioBuffer = AudioBuffer()  // Thread-safe audio storage
    
    private var modelRunner: ModelRunner?
    private var conversation: Conversation?
    private var conversationTask: Task<Void, Never>?
    
    // Conversation history with modality flags
    private var history: [ChatMessage] = []
    private var systemPrompt: String = ""
    
    // State
    private(set) var state: State = .idle
    private(set) var isActive = false
    private var shouldContinue = true
    
    // Timing for chunked streaming
    private var lastSendTime: Date?
    private let chunkInterval: TimeInterval = 2.0  // Send audio every 2 seconds
    
    // MARK: - Callbacks
    
    var onStateChange: ((State) -> Void)?
    var onStreamingText: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onError: ((Error) -> Void)?
    var onTurnComplete: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        setupPlaybackCallback()
    }
    
    private func setupPlaybackCallback() {
        playbackManager.onPlaybackComplete = { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                print("[ConversationLoop] 🔊 Playback complete, resuming listening")
                self.onTurnComplete?()
                
                // Resume listening after model finishes speaking
                if self.shouldContinue {
                    self.startListening()
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Start a conversation session with the given model and system prompt
    func start(modelRunner: ModelRunner, systemPrompt: String) throws {
        guard !isActive else {
            print("[ConversationLoop] Already active")
            return
        }
        
        print("[ConversationLoop] 🎙️ Starting conversation")
        
        self.modelRunner = modelRunner
        self.systemPrompt = systemPrompt
        self.history = [ChatMessage(role: .system, content: [.text(systemPrompt)])]
        self.shouldContinue = true
        self.isActive = true
        
        // Configure audio session for conversation
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        
        playbackManager.prepareSession()
        startListening()
    }
    
    /// Stop the conversation session
    func stop() {
        guard isActive else { return }
        
        print("[ConversationLoop] 🛑 Stopping conversation")
        
        shouldContinue = false
        isActive = false
        
        stopListening()
        conversationTask?.cancel()
        conversationTask = nil
        playbackManager.reset()
        
        audioBuffer.clear()
        
        history.removeAll()
        conversation = nil
        
        updateState(.idle)
    }
    
    /// Interrupt the current response (e.g., user wants to speak)
    func interrupt() {
        print("[ConversationLoop] ⚡ Interrupting")
        conversationTask?.cancel()
        playbackManager.reset()
        
        if isActive {
            startListening()
        }
    }
    
    // MARK: - Audio Recording
    
    private func startListening() {
        guard isActive, !engine.isRunning else { return }
        
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            audioBuffer.sampleRate = format.sampleRate
            
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }
            
            engine.prepare()
            try engine.start()
            
            lastSendTime = Date()
            updateState(.listening)
            print("[ConversationLoop] 🎤 Listening (sampleRate: \(audioBuffer.sampleRate))")
            
        } catch {
            print("[ConversationLoop] ❌ Failed to start listening: \(error)")
            onError?(error)
        }
    }
    
    private func stopListening() {
        guard engine.isRunning else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        print("[ConversationLoop] 🎤 Stopped listening")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: frameCount))
        
        // Calculate audio level for UI
        let rms = calculateRMS(samples)
        Task { @MainActor in
            self.onAudioLevel?(min(rms * 5, 1.0))
        }
        
        // Accumulate samples in thread-safe buffer
        audioBuffer.append(samples)
        
        // Check if it's time to send a chunk to the model
        // The model will internally determine if there's meaningful speech
        let now = Date()
        if let lastSend = lastSendTime, now.timeIntervalSince(lastSend) >= chunkInterval {
            Task { @MainActor in
                self.sendAudioToModel()
            }
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    // MARK: - Model Interaction
    
    private func sendAudioToModel() {
        let samplesToSend = audioBuffer.flush()
        let rate = Int(audioBuffer.sampleRate)
        
        guard !samplesToSend.isEmpty else { return }
        
        lastSendTime = Date()
        
        Task {
            await self.processUserAudio(samples: samplesToSend, sampleRate: rate)
        }
    }
    
    private func processUserAudio(samples: [Float], sampleRate: Int) async {
        guard let modelRunner, isActive else { return }
        
        // Minimum audio threshold (skip very short/quiet audio)
        let duration = Double(samples.count) / Double(sampleRate)
        guard duration > 0.1 else { return }
        
        print("[ConversationLoop] 📤 Sending \(samples.count) samples (\(String(format: "%.1f", duration))s) to model")
        
        stopListening()
        updateState(.processing)
        
        // Create audio message content
        let audioContent = ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate)
        let userMessage = ChatMessage(role: .user, content: [audioContent])
        
        // LFM2.5 audio engine requires fresh conversation for each turn
        // ("messages are not replayable, need to start a new dialog")
        // So we create a new conversation with only the system prompt
        let freshConversation = Conversation(
            modelRunner: modelRunner,
            history: [ChatMessage(role: .system, content: [.text(systemPrompt)])]
        )
        conversation = freshConversation
        
        playbackManager.reset()
        
        // Generate response
        let stream = freshConversation.generateResponse(message: userMessage)
        var responseText = ""
        var responseHasAudio = false
        
        conversationTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        switch event {
                        case .chunk(let text):
                            responseText.append(text)
                            self.onStreamingText?(text)
                            
                        case .reasoningChunk:
                            break
                            
                        case .audioSample(let samples, let sampleRate):
                            self.updateState(.speaking)
                            self.playbackManager.enqueue(samples: samples, sampleRate: sampleRate)
                            responseHasAudio = true
                            
                        case .functionCall:
                            break
                            
                        case .complete(let completion):
                            self.handleCompletion(completion, responseText: responseText, hasAudio: responseHasAudio)
                            
                        @unknown default:
                            break
                        }
                    }
                }
            } catch {
                print("[ConversationLoop] ❌ Generation error: \(error)")
                await MainActor.run {
                    self.onError?(error)
                    if self.isActive && self.shouldContinue {
                        self.startListening()
                    }
                }
            }
        }
    }
    
    private func handleCompletion(_ completion: MessageCompletion, responseText: String, hasAudio: Bool) {
        print("[ConversationLoop] ✅ Response complete (hasAudio: \(hasAudio), text: \(responseText.prefix(50))...)")
        
        // Note: LFM2.5 audio engine doesn't support history replay
        // Each turn is independent, so we don't maintain conversation history
        
        // If no audio was generated, resume listening immediately
        // Otherwise, playback callback will resume listening
        if !hasAudio && isActive && shouldContinue {
            startListening()
        }
    }
    
    private func updateState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
        print("[ConversationLoop] 📊 State: \(newState.rawValue)")
    }
}

import AVFoundation
import Foundation
import LeapSDK

enum CuratorMode: String {
    case idle
    case autoTour
    case pushToTalk
    case conversation  // Real-time conversational mode (model handles speech flow natively)
}

enum CuratorState: String {
    case idle
    case recording
    case listening      // Continuous listening in conversation mode
    case generating
    case playing
}

@MainActor
final class CuratorRuntime {
    static let shared = CuratorRuntime()
    
    private(set) var mode: CuratorMode = .idle
    private(set) var state: CuratorState = .idle
    private(set) var isGenerating = false
    
    private let playbackManager = AudioPlaybackManager()
    private let recorder = AudioRecorder()
    private let conversationLoop = ConversationLoop()
    private var modelRunner: ModelRunner?
    private var conversation: Conversation?
    private var streamingTask: Task<Void, Never>?
    private var generationComplete = false
    
    private let inferenceQueue = DispatchQueue(label: "ai.leap.curator.inference", qos: .userInitiated)
    private var activeGenerationID: UUID?
    
    var onStreamingText: ((String) -> Void)?
    var onAudioSample: (([Float], Int) -> Void)?
    var onGenerationComplete: ((MessageCompletion) -> Void)?
    var onGenerationError: ((Error) -> Void)?
    var onPlaybackComplete: (() -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onConversationStateChange: ((ConversationLoop.State) -> Void)?
    
    private init() {
        print("[CuratorRuntime] 🚀 Initializing singleton")
        setupPlaybackCallback()
        setupConversationLoopCallbacks()
    }
    
    private func setupPlaybackCallback() {
        playbackManager.onPlaybackComplete = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                print("[CuratorRuntime] 🔊 Playback complete callback (generationComplete=\(self.generationComplete))")
                if self.generationComplete {
                    self.state = .idle
                    self.onPlaybackComplete?()
                }
            }
        }
    }
    
    private func setupConversationLoopCallbacks() {
        conversationLoop.onStateChange = { [weak self] loopState in
            Task { @MainActor in
                guard let self else { return }
                self.onConversationStateChange?(loopState)
                
                // Map conversation loop state to curator state
                switch loopState {
                case .idle:
                    self.state = .idle
                case .listening:
                    self.state = .listening
                case .processing:
                    self.state = .generating
                    self.isGenerating = true
                case .speaking:
                    self.state = .playing
                    self.isGenerating = false
                }
            }
        }
        
        conversationLoop.onStreamingText = { [weak self] text in
            Task { @MainActor in
                self?.onStreamingText?(text)
            }
        }
        
        conversationLoop.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.onAudioLevel?(level)
            }
        }
        
        conversationLoop.onError = { [weak self] error in
            Task { @MainActor in
                self?.onGenerationError?(error)
            }
        }
        
        conversationLoop.onTurnComplete = { [weak self] in
            Task { @MainActor in
                self?.onStatusChange?("Listening...")
            }
        }
    }
    
    var isModelLoaded: Bool {
        modelRunner != nil
    }
    
    func loadModel() async throws {
        guard modelRunner == nil else {
            print("[CuratorRuntime] Model already loaded")
            return
        }
        
        print("[CuratorRuntime] 📦 Loading model...")
        onStatusChange?("Loading model...")
        
        let quant = "Q8_0"
        guard let modelURL = findModelURL(quantization: quant) else {
            throw NSError(domain: "CuratorRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model found"])
        }
        
        let bundle = Bundle.main
        let mmProjPath = bundle.url(forResource: "mmproj-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
        let audioTokenizerPath = bundle.url(forResource: "tokenizer-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
        let vocoderPath = bundle.url(forResource: "vocoder-LFM2.5-Audio-1.5B-\(quant)", withExtension: "gguf")?.path()
        
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
        print("[CuratorRuntime] ✅ Model loaded successfully")
        onStatusChange?("Ready")
    }
    
    func hardReset() async {
        print("[CuratorRuntime] 🔄 === HARD RESET START ===")
        print("[CuratorRuntime] Current mode=\(mode.rawValue), state=\(state.rawValue)")
        
        let previousMode = mode
        
        // Stop conversation loop if active
        if conversationLoop.isActive {
            conversationLoop.stop()
        }
        
        await cancelGeneration()
        
        stopPlayback()
        
        stopRecording()
        
        resetConversation()
        
        await reconfigureAudioSession(for: .idle)
        
        mode = .idle
        state = .idle
        generationComplete = false
        
        print("[CuratorRuntime] 🔄 === HARD RESET COMPLETE === (was mode=\(previousMode.rawValue))")
    }
    
    private func cancelGeneration() async {
        guard let task = streamingTask else {
            print("[CuratorRuntime] No active generation to cancel")
            return
        }
        
        let genID = activeGenerationID
        print("[CuratorRuntime] ❌ Cancelling generation (id=\(genID?.uuidString.prefix(8) ?? "nil"))")
        
        task.cancel()
        
        var attempts = 0
        while !task.isCancelled && attempts < 10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        
        streamingTask = nil
        activeGenerationID = nil
        isGenerating = false
        generationComplete = false
        
        print("[CuratorRuntime] ❌ Generation cancelled after \(attempts) waits")
    }
    
    private func stopPlayback() {
        print("[CuratorRuntime] 🔇 Stopping playback")
        playbackManager.reset()
        state = state == .playing ? .idle : state
    }
    
    private func stopRecording() {
        if recorder.isRecording {
            print("[CuratorRuntime] 🎤 Stopping recording")
            recorder.cancel()
        }
        state = state == .recording ? .idle : state
    }
    
    private func resetConversation() {
        print("[CuratorRuntime] 🧹 Resetting conversation state")
        conversation = nil
    }
    
    private func reconfigureAudioSession(for newMode: CuratorMode) async {
        print("[CuratorRuntime] 🎧 Reconfiguring audio session for mode=\(newMode.rawValue)")
        
        do {
            let session = AVAudioSession.sharedInstance()
            
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            
            switch newMode {
            case .autoTour:
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            case .pushToTalk:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            case .conversation:
                // voiceChat mode optimized for real-time conversation
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            case .idle:
                try session.setCategory(.playback, mode: .default, options: [])
            }
            
            try session.setActive(true, options: [])
            print("[CuratorRuntime] 🎧 Audio session configured for \(newMode.rawValue)")
        } catch {
            print("[CuratorRuntime] ⚠️ Audio session error: \(error)")
        }
    }
    
    func startAutoTour() async {
        print("[CuratorRuntime] 🎬 Starting Auto Tour mode")
        await hardReset()
        await reconfigureAudioSession(for: .autoTour)
        mode = .autoTour
        playbackManager.prepareSession()
    }
    
    func startPushToTalk() async {
        print("[CuratorRuntime] 🎤 Starting Push-to-Talk mode")
        await hardReset()
        await reconfigureAudioSession(for: .pushToTalk)
        mode = .pushToTalk
        playbackManager.prepareSession()
    }
    
    /// Start real-time conversational mode
    /// Model handles speech flow natively - no external VAD needed
    func startConversation(systemPrompt: String) async throws {
        guard let modelRunner else {
            throw NSError(domain: "CuratorRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        print("[CuratorRuntime] 💬 Starting Conversation mode")
        await hardReset()
        mode = .conversation
        state = .listening
        
        try conversationLoop.start(modelRunner: modelRunner, systemPrompt: systemPrompt)
        onStatusChange?("Listening...")
    }
    
    /// Stop conversational mode
    func stopConversation() {
        guard mode == .conversation else { return }
        
        print("[CuratorRuntime] 💬 Stopping Conversation mode")
        conversationLoop.stop()
        mode = .idle
        state = .idle
        onStatusChange?("Ready")
    }
    
    /// Interrupt the current conversation turn (e.g., user wants to speak over model)
    func interruptConversation() {
        guard mode == .conversation else { return }
        conversationLoop.interrupt()
    }
    
    /// Check if conversation mode is active
    var isConversationActive: Bool {
        mode == .conversation && conversationLoop.isActive
    }
    
    func generate(message: ChatMessage, systemPrompt: String) async {
        guard let modelRunner else {
            print("[CuratorRuntime] ⚠️ Model not loaded")
            onStatusChange?("Model not ready")
            return
        }
        
        if isGenerating {
            print("[CuratorRuntime] ⚠️ Already generating, cancelling previous...")
            await cancelGeneration()
        }
        
        let genID = UUID()
        activeGenerationID = genID
        isGenerating = true
        generationComplete = false
        state = .generating
        
        print("[CuratorRuntime] 🧠 === GENERATION START === (id=\(genID.uuidString.prefix(8)))")
        onStatusChange?("Thinking...")
        
        playbackManager.reset()
        
        let freshConversation = Conversation(
            modelRunner: modelRunner,
            history: [ChatMessage(role: .system, content: [.text(systemPrompt)])]
        )
        conversation = freshConversation
        
        let stream = freshConversation.generateResponse(message: message)
        
        streamingTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                for try await event in stream {
                    if Task.isCancelled {
                        print("[CuratorRuntime] 🧠 Generation task cancelled mid-stream (id=\(genID.uuidString.prefix(8)))")
                        break
                    }
                    
                    guard self.activeGenerationID == genID else {
                        print("[CuratorRuntime] 🧠 Generation ID mismatch, stopping (expected=\(genID.uuidString.prefix(8)))")
                        break
                    }
                    
                    await MainActor.run {
                        self.handleEvent(event)
                    }
                }
                
                await MainActor.run {
                    if self.activeGenerationID == genID {
                        print("[CuratorRuntime] 🧠 === GENERATION END === (id=\(genID.uuidString.prefix(8)))")
                    }
                }
            } catch {
                print("[CuratorRuntime] 🧠 Generation error (id=\(genID.uuidString.prefix(8))): \(error)")
                await MainActor.run {
                    self.isGenerating = false
                    self.state = .idle
                    self.onGenerationError?(error)
                }
            }
            
            await MainActor.run {
                if self.activeGenerationID == genID {
                    self.streamingTask = nil
                }
            }
        }
    }
    
    private func handleEvent(_ event: MessageResponse) {
        switch event {
        case .chunk(let text):
            onStreamingText?(text)
        case .reasoningChunk:
            onStatusChange?("Thinking...")
        case .audioSample(let samples, let sampleRate):
            state = .playing
            playbackManager.enqueue(samples: samples, sampleRate: sampleRate)
            onAudioSample?(samples, sampleRate)
            onStatusChange?("Speaking...")
        case .functionCall(let calls):
            onStatusChange?("Function call: \(calls.count)")
        case .complete(let completion):
            finishGeneration(with: completion)
        @unknown default:
            break
        }
    }
    
    private func finishGeneration(with completion: MessageCompletion) {
        print("[CuratorRuntime] 🧠 Generation finished, waiting for audio playback")
        isGenerating = false
        generationComplete = true
        onGenerationComplete?(completion)
    }
    
    func startRecording() throws {
        print("[CuratorRuntime] 🎤 === RECORDING START ===")
        state = .recording
        try recorder.start()
    }
    
    func stopRecordingAndCapture() -> (samples: [Float], sampleRate: Int)? {
        print("[CuratorRuntime] 🎤 === RECORDING STOP ===")
        recorder.stop()
        state = .idle
        return recorder.capture()
    }
    
    func cancelRecording() {
        print("[CuratorRuntime] 🎤 Recording cancelled")
        recorder.cancel()
        state = .idle
    }
    
    func debugStatus() -> String {
        """
        [CuratorRuntime Status]
        Mode: \(mode.rawValue)
        State: \(state.rawValue)
        isGenerating: \(isGenerating)
        generationComplete: \(generationComplete)
        activeGenerationID: \(activeGenerationID?.uuidString.prefix(8) ?? "nil")
        streamingTask: \(streamingTask != nil ? "active" : "nil")
        modelLoaded: \(modelRunner != nil)
        """
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

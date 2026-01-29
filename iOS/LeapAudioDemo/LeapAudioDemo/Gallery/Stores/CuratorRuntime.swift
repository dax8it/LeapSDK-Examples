import AVFoundation
import Foundation
import LeapSDK

/// Coordinates generation to prevent decoder re-entrancy and ensure single-flight operation
actor GenerationCoordinator {
    private(set) var currentGenerationTask: Task<Void, Never>?
    private(set) var isAcceptingAudioFrames = true
    private(set) var generationID: UUID?
    private(set) var isGenerationActive = false  // Strict single-flight flag
    private var generationStartTime: Date?
    
    /// Generation timeout in seconds
    private let generationTimeoutSeconds: Double = 30.0
    
    /// Check if generation is currently active (blocks new generations and resets)
    var isActive: Bool { isGenerationActive }
    
    /// Check if audio frames are being accepted (for diagnostics)
    var audioFramesEnabled: Bool { isAcceptingAudioFrames }
    
    /// Start a new generation, blocking if one is already running
    /// Returns nil if generation is already active (caller should not proceed)
    func tryBeginGeneration() async -> UUID? {
        // STRICT SINGLE-FLIGHT: Block if generation is already active
        if isGenerationActive {
            print("[GenerationCoordinator] ⚠️ Generation already active, blocking new request")
            return nil
        }
        
        // Block new audio frames during transition
        isAcceptingAudioFrames = false
        isGenerationActive = true
        generationStartTime = Date()
        
        // Cancel any lingering task (shouldn't happen, but safety)
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        // Create new generation ID
        let newID = UUID()
        generationID = newID
        
        print("[GenerationCoordinator] 🆕 Starting generation \(newID.uuidString.prefix(8))")
        return newID
    }
    
    /// Set the generation task after it's created
    func setTask(_ task: Task<Void, Never>) {
        currentGenerationTask = task
    }
    
    /// Enable audio frame acceptance (call after playback buffer is ready)
    func enableAudioFrames() {
        isAcceptingAudioFrames = true
        print("[GenerationCoordinator] ✅ Audio frames enabled")
    }
    
    /// Disable audio frame acceptance (for clean soft-stop)
    func disableAudioFrames() {
        isAcceptingAudioFrames = false
        print("[GenerationCoordinator] 🛑 Audio frames disabled")
    }
    
    /// Check if audio frame should be accepted
    func shouldAcceptAudioFrame(forGenerationID id: UUID) -> Bool {
        guard isAcceptingAudioFrames else {
            return false
        }
        guard generationID == id else {
            return false
        }
        return true
    }
    
    /// Check if generation has exceeded timeout
    func hasExceededTimeout() -> Bool {
        guard let startTime = generationStartTime else { return false }
        return Date().timeIntervalSince(startTime) > generationTimeoutSeconds
    }
    
    /// End generation and prepare for next
    func endGeneration(id: UUID) {
        guard generationID == id else { return }
        print("[GenerationCoordinator] 🏁 Ending generation \(id.uuidString.prefix(8))")
        currentGenerationTask = nil
        isGenerationActive = false
        generationStartTime = nil
    }
    
    /// Force end generation (for timeout or error cases)
    func forceEndGeneration() {
        let genID = generationID?.uuidString.prefix(8) ?? "nil"
        print("[GenerationCoordinator] ⚠️ Force ending generation \(genID)")
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        generationID = nil
        isGenerationActive = false
        isAcceptingAudioFrames = false
        generationStartTime = nil
    }
    
    /// Two-phase reset: safely tear down with no in-flight frames
    /// Returns false if reset should be blocked (generation active)
    func prepareForReset() async -> Bool {
        // BLOCK RESET DURING ACTIVE GENERATION
        if isGenerationActive {
            print("[GenerationCoordinator] ⚠️ Cannot reset during active generation - wait for completion")
            return false
        }
        
        print("[GenerationCoordinator] 🔄 Preparing for reset (phase 1: block frames)")
        isAcceptingAudioFrames = false
        
        // Cancel and await the generation task
        if let task = currentGenerationTask {
            task.cancel()
            // Give it time to cancel
            for _ in 0..<20 {
                if task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 25_000_000) // 25ms
            }
        }
        currentGenerationTask = nil
        generationID = nil
        print("[GenerationCoordinator] 🔄 Reset prepared (phase 1 complete)")
        return true
    }
    
    /// Complete reset after buffers are cleared
    func completeReset() {
        print("[GenerationCoordinator] 🔄 Reset complete (phase 2: ready for new generation)")
        isAcceptingAudioFrames = true
        isGenerationActive = false
        generationStartTime = nil
    }
}

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
    private let generationCoordinator = GenerationCoordinator()  // Single-flight generation coordinator
    private var modelRunner: ModelRunner?
    private var conversation: Conversation?
    private var streamingTask: Task<Void, Never>?
    private var generationComplete = false
    
    private let inferenceQueue = DispatchQueue(label: "ai.leap.curator.inference", qos: .userInitiated)
    private var activeGenerationID: UUID?
    
    // BACKPRESSURE CONFIG: Output length limits to prevent runaway audio / ggml crashes
    private let maxOutputTokens: Int = 200  // Limit response length
    private let maxPendingAudioMs: Double = 2000  // Soft stop if total buffered audio exceeds 2s
    private let maxEmittedAudioMs: Double = 6000  // Hard cap: max 6s of audio per response
    private var emittedAudioMs: Double = 0  // Track audio emitted in current response
    
    // GPU CONFIG: Toggle for A/B testing stability (crash may be in decoder GPU path)
    static var audioDecoderUseGpu: Bool = true  // GPU-accelerated decoder for smoother audio
    
    var onStreamingText: ((String) -> Void)?
    var onAudioSample: (([Float], Int) -> Void)?
    var onGenerationComplete: ((MessageCompletion) -> Void)?
    var onGenerationStopped: (() -> Void)?  // Called when generation is soft-stopped (e.g., buffer limit)
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
            cpuThreads: 4,              // Explicit thread count for steady throughput
            contextSize: 2048,          // Reduced for lower latency
            nGpuLayers: 0,
            mmProjPath: mmProjPath,
            audioDecoderPath: vocoderPath,
            audioDecoderUseGpu: CuratorRuntime.audioDecoderUseGpu,  // Configurable: toggle for A/B stability testing
            audioTokenizerPath: audioTokenizerPath
        )
        print("[CuratorRuntime] 🎛️ audioDecoderUseGpu = \(CuratorRuntime.audioDecoderUseGpu)")
        
        let runner = try Leap.load(options: options)
        modelRunner = runner
        print("[CuratorRuntime] ✅ Model loaded successfully")
        onStatusChange?("Ready")
    }
    
    func hardReset(force: Bool = false) async {
        print("[CuratorRuntime] 🔄 === HARD RESET START === (force=\(force))")
        print("[CuratorRuntime] Current mode=\(mode.rawValue), state=\(state.rawValue)")
        
        let previousMode = mode
        
        // PHASE 1: Block audio frames and cancel generation safely
        // If force=true, we force-end any active generation first
        if force {
            await generationCoordinator.forceEndGeneration()
        }
        
        let canReset = await generationCoordinator.prepareForReset()
        if !canReset {
            print("[CuratorRuntime] ⚠️ Reset blocked - generation still active. Use force=true to override.")
            return
        }
        
        // Stop conversation loop if active
        if conversationLoop.isActive {
            conversationLoop.stop()
        }
        
        await cancelGeneration()
        
        // PHASE 2: Now safe to clear buffers (no frames in flight)
        stopPlayback()
        
        stopRecording()
        
        resetConversation()
        
        await reconfigureAudioSession(for: .idle)
        
        mode = .idle
        state = .idle
        generationComplete = false
        
        // PHASE 3: Re-enable for next generation
        await generationCoordinator.completeReset()
        
        print("[CuratorRuntime] 🔄 === HARD RESET COMPLETE === (was mode=\(previousMode.rawValue))")
    }
    
    private func cancelGeneration() async {
        guard let task = streamingTask else {
            print("[CuratorRuntime] No active generation to cancel")
            return
        }
        
        let genID = activeGenerationID
        print("[CuratorRuntime] ❌ Cancelling generation (id=\(genID?.uuidString.prefix(8) ?? "nil"))")
        
        AudioDebug.log("[CuratorRuntime] 🛑 generation cancel")
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
        AudioDebug.log("[CuratorRuntime] 🔇 stopPlayback")
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
    /// Uses energy/silence-based endpointing for turn detection (not ASR VAD)
    func startConversation(systemPrompt: String, contextPrefix: String = "") async throws {
        guard let modelRunner else {
            throw NSError(domain: "CuratorRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        print("[CuratorRuntime] 💬 Starting Conversation mode")
        await hardReset()
        mode = .conversation
        state = .listening
        
        try conversationLoop.start(modelRunner: modelRunner, systemPrompt: systemPrompt, contextPrefix: contextPrefix)
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
        
        // STRICT SINGLE-FLIGHT: Try to begin generation, block if already active
        guard let genID = await generationCoordinator.tryBeginGeneration() else {
            print("[CuratorRuntime] ⚠️ Generation blocked - another generation is active")
            onStatusChange?("Busy...")
            return
        }
        
        activeGenerationID = genID
        isGenerating = true
        generationComplete = false
        emittedAudioMs = 0  // Reset audio tracking for new response
        state = .generating
        AudioDebug.log("[CuratorRuntime] 🧠 generation start id=\(genID.uuidString.prefix(8)) mode=\(mode.rawValue)")
        
        // CRASH-TIME BREADCRUMBS: Log state before generation
        let pendingMs = playbackManager.pendingDurationMs
        let isPlaybackIdle = playbackManager.isIdle
        let audioFramesEnabled = await generationCoordinator.audioFramesEnabled
        print("[CuratorRuntime] 🧠 === GENERATION START === (id=\(genID.uuidString.prefix(8)))")
        print("[CuratorRuntime] 📊 Pre-gen state: pendingAudio=\(Int(pendingMs))ms, playbackIdle=\(isPlaybackIdle), audioFramesEnabled=\(audioFramesEnabled)")
        onStatusChange?("Thinking...")
        
        playbackManager.reset()
        
        // Enable audio frames now that playback is ready
        await generationCoordinator.enableAudioFrames()
        
        let freshConversation = Conversation(
            modelRunner: modelRunner,
            history: [ChatMessage(role: .system, content: [.text(systemPrompt)])]
        )
        conversation = freshConversation
        
        let stream = freshConversation.generateResponse(message: message)
        
        let task = Task { [weak self] in
            guard let self else { return }
            
            var tokenCount = 0
            var shouldStop = false
            
            do {
                for try await event in stream {
                    if Task.isCancelled || shouldStop {
                        print("[CuratorRuntime] 🧠 Generation stopped (id=\(genID.uuidString.prefix(8)), tokens=\(tokenCount), emittedAudio=\(Int(await MainActor.run { self.emittedAudioMs }))ms)")
                        // CLEAN SOFT-STOP: disable audio frames, end coordinator, let playback drain
                        await self.generationCoordinator.disableAudioFrames()
                        await self.generationCoordinator.endGeneration(id: genID)
                        await MainActor.run {
                            self.isGenerating = false
                            self.generationComplete = true
                            self.playbackManager.markGenerationComplete()  // Let playback drain normally
                            self.onGenerationStopped?()  // Notify listeners that generation was soft-stopped
                        }
                        return
                    }
                    
                    // Check 30s timeout kill-switch
                    let timedOut = await self.generationCoordinator.hasExceededTimeout()
                    if timedOut {
                        print("[CuratorRuntime] ⏰ Generation timeout (30s), forcing stop")
                        await self.generationCoordinator.forceEndGeneration()
                        await MainActor.run {
                            self.isGenerating = false
                            self.state = .idle
                            self.onStatusChange?("Timeout")
                        }
                        return
                    }
                    
                    // Check with coordinator if we should accept this frame
                    let shouldAccept = await self.generationCoordinator.shouldAcceptAudioFrame(forGenerationID: genID)
                    guard shouldAccept else {
                        print("[CuratorRuntime] 🧠 Frame rejected by coordinator")
                        break
                    }
                    
                    guard self.activeGenerationID == genID else {
                        print("[CuratorRuntime] 🧠 Generation ID mismatch, stopping (expected=\(genID.uuidString.prefix(8)))")
                        break
                    }
                    
                    // Track tokens for output length limit
                    if case .chunk = event {
                        tokenCount += 1
                    }
                    
                    await MainActor.run {
                        self.handleEvent(event, genID: genID, tokenCount: &tokenCount, shouldStop: &shouldStop)
                    }
                    
                    // Check output length limits
                    if tokenCount >= self.maxOutputTokens {
                        print("[CuratorRuntime] ⚠️ Max output tokens reached (\(tokenCount)), stopping generation")
                        shouldStop = true
                    }
                }
                
                await MainActor.run {
                    if self.activeGenerationID == genID {
                        print("[CuratorRuntime] 🧠 === GENERATION END === (id=\(genID.uuidString.prefix(8)), tokens=\(tokenCount))")
                    }
                }
                
                // Notify coordinator that generation ended
                await self.generationCoordinator.endGeneration(id: genID)
                
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
        
        streamingTask = task
        await generationCoordinator.setTask(task)
    }
    
    private func handleEvent(_ event: MessageResponse, genID: UUID, tokenCount: inout Int, shouldStop: inout Bool) {
        switch event {
        case .chunk(let text):
            onStreamingText?(text)
        case .reasoningChunk:
            onStatusChange?("Thinking...")
        case .audioSample(let samples, let sampleRate):
            // Calculate audio duration for this sample
            let sampleDurationMs = Double(samples.count) / Double(sampleRate) * 1000.0
            emittedAudioMs += sampleDurationMs
            
            // HARD CAP: max 6s of audio per response
            if emittedAudioMs >= maxEmittedAudioMs {
                print("[CuratorRuntime] ⚠️ HARD CAP: emittedAudio=\(Int(emittedAudioMs))ms >= \(Int(maxEmittedAudioMs))ms, stopping generation")
                shouldStop = true
                return
            }
            
            // SOFT CAP: total buffered audio (pending + scheduled)
            let totalBufferedMs = playbackManager.pendingDurationMs
            if totalBufferedMs >= maxPendingAudioMs {
                print("[CuratorRuntime] ⚠️ Buffer limit: totalBuffered=\(Int(totalBufferedMs))ms >= \(Int(maxPendingAudioMs))ms, soft stopping")
                shouldStop = true
                return
            }
            
            state = .playing
            playbackManager.enqueue(samples: samples, sampleRate: sampleRate)
            onAudioSample?(samples, sampleRate)
            onStatusChange?("Speaking...")
        case .functionCall(let calls):
            onStatusChange?("Function call: \(calls.count)")
        case .complete(let completion):
            finishGeneration(with: completion, genID: genID)
        @unknown default:
            break
        }
    }
    
    private func finishGeneration(with completion: MessageCompletion, genID: UUID) {
        print("[CuratorRuntime] 🧠 Generation finished (id=\(genID.uuidString.prefix(8))), waiting for audio playback")
        AudioDebug.log("[CuratorRuntime] ✅ generation finish")
        isGenerating = false
        generationComplete = true
        
        // Signal to playback manager that generation is done - it can fire completion when buffers empty
        playbackManager.markGenerationComplete()
        
        onGenerationComplete?(completion)
    }
    
    func startRecording() throws {
        print("[CuratorRuntime] 🎤 === RECORDING START ===")
        AudioDebug.log("[CuratorRuntime] 🎤 recording start")
        state = .recording
        try recorder.start()
    }
    
    func stopRecordingAndCapture() -> (samples: [Float], sampleRate: Int)? {
        print("[CuratorRuntime] 🎤 === RECORDING STOP ===")
        AudioDebug.log("[CuratorRuntime] 🎤 recording stop")
        recorder.stop()
        state = .idle
        return recorder.capture()
    }
    
    func cancelRecording() {
        print("[CuratorRuntime] 🎤 Recording cancelled")
        AudioDebug.log("[CuratorRuntime] 🎤 recording cancel")
        recorder.cancel()
        state = .idle
    }
    
    /// Set mute state - forwards to playback manager
    func setMuted(_ muted: Bool) {
        playbackManager.setMuted(muted)
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

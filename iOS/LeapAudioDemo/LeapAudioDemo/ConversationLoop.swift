import AVFoundation
import Accelerate
import Foundation
import LeapSDK

/// Resamples audio to the model's expected format (16kHz mono Float32)
enum AudioResampler {
    
    /// Target sample rate expected by LFM2.5-Audio model
    static let modelSampleRate: Int = 16000
    
    /// Resample audio from source rate to 16kHz mono
    static func resampleTo16kHz(samples: [Float], sourceSampleRate: Int) -> [Float]? {
        guard sourceSampleRate != modelSampleRate else { return samples }
        guard !samples.isEmpty else { return [] }
        
        let ratio = Double(modelSampleRate) / Double(sourceSampleRate)
        let outputLength = Int(Double(samples.count) * ratio)
        guard outputLength > 0 else { return [] }
        
        var output = [Float](repeating: 0, count: outputLength)
        let step = Float(samples.count - 1) / Float(outputLength - 1)
        
        for i in 0..<outputLength {
            let srcIndex = Float(i) * step
            let srcIndexInt = Int(srcIndex)
            let fraction = srcIndex - Float(srcIndexInt)
            
            if srcIndexInt >= samples.count - 1 {
                output[i] = samples[samples.count - 1]
            } else {
                output[i] = samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction
            }
        }
        
        // Remove DC offset
        var mean: Float = 0
        vDSP_meanv(output, 1, &mean, vDSP_Length(output.count))
        var negativeMean = -mean
        var dcRemoved = [Float](repeating: 0, count: output.count)
        vDSP_vsadd(output, 1, &negativeMean, &dcRemoved, 1, vDSP_Length(output.count))
        
        let inputDuration = Double(samples.count) / Double(sourceSampleRate)
        let outputDuration = Double(dcRemoved.count) / Double(modelSampleRate)
        print("[AudioResampler] \(samples.count)@\(sourceSampleRate)Hz → \(dcRemoved.count)@\(modelSampleRate)Hz (\(String(format: "%.2f", inputDuration))s)")
        
        return dcRemoved
    }
}

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
    private var contextPrefix: String = ""  // Context to prepend to user audio
    
    // State
    private(set) var state: State = .idle
    private(set) var isActive = false
    private var shouldContinue = true
    private var generationComplete = false  // Track if model finished generating
    
    // Single-flight generation protection
    private var isGenerationInProgress = false
    private var generationStartTime: Date?
    private let generationTimeoutSeconds: Double = 30.0  // Kill-switch timeout
    
    // Speech-gated commit: tuning knobs
    private let startThresholdDb: Float = -40     // dB level to start speech detection
    private let endThresholdDb: Float = -45       // dB level for silence (hysteresis)
    private let minSpeechMs: Double = 300         // Minimum speech duration before sending
    private let endSilenceMs: Double = 900        // Silence duration to end utterance
    private let maxUtteranceMs: Double = 12000    // Maximum utterance length
    private let preRollMs: Double = 250           // Pre-roll buffer to capture first syllables
    private let frameMs: Double = 20              // Analyze in 20ms frames
    
    // Speech detection state
    private var hasSpeech = false
    private var speechMs: Double = 0
    private var silenceMs: Double = 0
    private var utteranceStart: Date?
    private var preRollBuffer: [Float] = []       // Last 250ms to capture first syllables
    private var sendBuffer: [Float] = []          // Buffer to send to model
    private var analysisBuffer: [Float] = []      // Buffer for frame analysis
    
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
                
                // Only resume listening if generation is complete
                // Otherwise, more audio chunks may still be coming
                guard self.generationComplete else { return }
                
                print("[ConversationLoop] 🔊 Playback complete, resuming listening")
                self.onTurnComplete?()
                
                // Resume listening after model finishes speaking
                if self.shouldContinue {
                    self.generationComplete = false  // Reset for next turn
                    self.startListening()
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Start a conversation session with the given model and system prompt
    func start(modelRunner: ModelRunner, systemPrompt: String, contextPrefix: String = "") throws {
        guard !isActive else {
            print("[ConversationLoop] Already active")
            return
        }
        
        print("[ConversationLoop] 🎙️ Starting conversation")
        
        self.modelRunner = modelRunner
        self.systemPrompt = systemPrompt
        self.contextPrefix = contextPrefix
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
        generationComplete = false
        isGenerationInProgress = false
        generationStartTime = nil
        
        stopListening()
        conversationTask?.cancel()
        conversationTask = nil
        playbackManager.reset()
        
        audioBuffer.clear()
        resetUtteranceState()
        preRollBuffer.removeAll()
        
        history.removeAll()
        conversation = nil
        
        updateState(.idle)
    }
    
    /// Interrupt the current response (e.g., user wants to speak)
    func interrupt() {
        print("[ConversationLoop] ⚡ Interrupting")
        
        // Clear generation state
        isGenerationInProgress = false
        generationStartTime = nil
        
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
            
            // Reset speech detection state for new listening session
            resetUtteranceState()
            preRollBuffer.removeAll()
            
            updateState(.listening)
            print("[ConversationLoop] 🎤 Listening (sampleRate: \(audioBuffer.sampleRate), speech threshold: \(startThresholdDb)dB)")
            
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
        
        // Add samples to analysis buffer for speech detection
        analysisBuffer.append(contentsOf: samples)
        
        // Maintain pre-roll buffer (last ~250ms at source sample rate)
        let sourceSampleRate = audioBuffer.sampleRate
        let preRollSamples = Int(sourceSampleRate * preRollMs / 1000.0)
        preRollBuffer.append(contentsOf: samples)
        if preRollBuffer.count > preRollSamples {
            preRollBuffer.removeFirst(preRollBuffer.count - preRollSamples)
        }
        
        // Analyze in frames (20ms at source sample rate)
        let frameSize = Int(sourceSampleRate * frameMs / 1000.0)
        
        while analysisBuffer.count >= frameSize {
            let frame = Array(analysisBuffer.prefix(frameSize))
            analysisBuffer.removeFirst(frameSize)
            
            let db = rmsToDb(frame)
            
            if !hasSpeech {
                // Not in speech yet - check if speech started
                if db > startThresholdDb {
                    hasSpeech = true
                    utteranceStart = Date()
                    speechMs = frameMs
                    silenceMs = 0
                    
                    // Start send buffer with pre-roll + current frame
                    sendBuffer = preRollBuffer + frame
                    print("[ConversationLoop] 🎙️ Speech started (dB: \(String(format: "%.1f", db)))")
                }
                // No speech yet - don't accumulate anything
            } else {
                // Already in utterance - accumulate
                sendBuffer.append(contentsOf: frame)
                
                if db > endThresholdDb {
                    speechMs += frameMs
                    silenceMs = 0
                } else {
                    silenceMs += frameMs
                }
                
                let utteranceMs = Date().timeIntervalSince(utteranceStart ?? Date()) * 1000.0
                
                // Check if utterance should end
                let silenceEnded = silenceMs >= endSilenceMs && speechMs >= minSpeechMs
                let maxReached = utteranceMs >= maxUtteranceMs
                
                if silenceEnded || maxReached {
                    let reason = maxReached ? "max duration" : "silence detected"
                    print("[ConversationLoop] 🎙️ Speech ended (\(reason), speech: \(Int(speechMs))ms, silence: \(Int(silenceMs))ms)")
                    commitUtterance()
                    return
                }
            }
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    private func rmsToDb(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -100 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let mean = max(sum / Float(samples.count), 1e-12)
        return 10 * log10(mean)
    }
    
    private func commitUtterance() {
        guard !sendBuffer.isEmpty, speechMs >= minSpeechMs else {
            print("[ConversationLoop] ⚠️ Utterance too short (\(Int(speechMs))ms), discarding")
            resetUtteranceState()
            return
        }
        
        let samplesToSend = sendBuffer
        let rate = Int(audioBuffer.sampleRate)
        
        // Reset state before sending
        resetUtteranceState()
        
        Task { @MainActor in
            await self.processUserAudio(samples: samplesToSend, sampleRate: rate)
        }
    }
    
    private func resetUtteranceState() {
        hasSpeech = false
        speechMs = 0
        silenceMs = 0
        utteranceStart = nil
        sendBuffer.removeAll(keepingCapacity: true)
        analysisBuffer.removeAll(keepingCapacity: true)
    }
    
    private func processUserAudio(samples: [Float], sampleRate: Int) async {
        guard let modelRunner, isActive else { return }
        
        // SINGLE-FLIGHT: Block if generation already in progress
        if isGenerationInProgress {
            print("[ConversationLoop] ⚠️ Generation already in progress, dropping audio")
            return
        }
        
        // Minimum audio threshold (skip very short/quiet audio)
        let duration = Double(samples.count) / Double(sampleRate)
        guard duration > 0.1 else { return }
        
        // Resample to 16kHz (model's expected rate) if needed
        let resampledSamples: [Float]
        let targetSampleRate: Int
        
        if sampleRate != AudioResampler.modelSampleRate {
            guard let resampled = AudioResampler.resampleTo16kHz(samples: samples, sourceSampleRate: sampleRate) else {
                print("[ConversationLoop] ❌ Failed to resample audio")
                return
            }
            resampledSamples = resampled
            targetSampleRate = AudioResampler.modelSampleRate
        } else {
            resampledSamples = samples
            targetSampleRate = sampleRate
        }
        
        let resampledDuration = Double(resampledSamples.count) / Double(targetSampleRate)
        print("[ConversationLoop] 📤 Sending \(resampledSamples.count) samples (\(String(format: "%.1f", resampledDuration))s) @ \(targetSampleRate)Hz to model")
        
        // Mark generation as starting
        isGenerationInProgress = true
        generationStartTime = Date()
        
        stopListening()
        updateState(.processing)
        generationComplete = false  // Reset for new generation
        
        // Create audio message content with context prefix
        let audioContent = ChatMessageContent.fromFloatSamples(resampledSamples, sampleRate: targetSampleRate)
        var messageContent: [ChatMessageContent] = []
        if !contextPrefix.isEmpty {
            messageContent.append(.text(contextPrefix))
        }
        messageContent.append(audioContent)
        let userMessage = ChatMessage(role: .user, content: messageContent)
        
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
                    
                    // Check 30s timeout kill-switch
                    if let startTime = await MainActor.run(body: { self.generationStartTime }),
                       Date().timeIntervalSince(startTime) > self.generationTimeoutSeconds {
                        print("[ConversationLoop] ⏰ Generation timeout (30s), forcing stop")
                        await MainActor.run {
                            self.isGenerationInProgress = false
                            self.generationStartTime = nil
                            if self.isActive && self.shouldContinue {
                                self.startListening()
                            }
                        }
                        return
                    }
                    
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
                    self.isGenerationInProgress = false
                    self.generationStartTime = nil
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
        
        // Clear single-flight lock
        isGenerationInProgress = false
        generationStartTime = nil
        
        // Mark generation as complete so playback callback knows it can resume listening
        generationComplete = true
        
        // Signal to playback manager that generation is done - it can fire completion when buffers empty
        playbackManager.markGenerationComplete()
        
        // If no audio was generated, resume listening immediately
        // Otherwise, playback callback will resume listening when audio finishes
        if !hasAudio && isActive && shouldContinue {
            generationComplete = false  // Reset for next turn
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

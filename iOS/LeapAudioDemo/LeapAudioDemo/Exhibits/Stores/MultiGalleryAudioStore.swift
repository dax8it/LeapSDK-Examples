import AVFoundation
import Foundation
import LeapSDK
import Observation

enum MultiGalleryContext {
    case home
    case galleriesOverview
    case exhibit(ExhibitMeta)
    case artwork(ExhibitMeta, Artwork)
}

@Observable
@MainActor
final class MultiGalleryAudioStore {
    var inputText: String = ""
    var messages: [CuratorMessage] = []
    var status: String?
    var streamingText: String = ""
    var isModelLoading = false
    var isGenerating = false
    var isRecording = false
    var isConversationActive = false
    var audioLevel: Float = 0
    var showDebugPrompt = false
    var lastPromptDebug: String = ""
    var onAudioPlaybackComplete: (() -> Void)?
    
    // MUTE STATE: Global mute toggle for audio output
    var isMuted: Bool = false {
        didSet {
            runtime.setMuted(isMuted)
            print("[MultiGalleryAudioStore] 🔇 Mute: \(isMuted)")
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
    }
    
    private var currentContext: MultiGalleryContext = .home
    private var libraryStore: ExhibitLibraryStore?
    
    private let runtime = CuratorRuntime.shared
    
    // Debug properties
    var debugContextType: String {
        switch currentContext {
        case .home: return "Home"
        case .galleriesOverview: return "Galleries Overview"
        case .exhibit(let e): return "Exhibit: \(e.id)"
        case .artwork(let e, let a): return "Artwork: \(a.id) in \(e.id)"
        }
    }
    var debugContextPacketPreview: String {
        String(buildContextPacket().prefix(200)) + "..."
    }
    var debugIsGenerationActive: Bool { runtime.isGenerating }
    
    init() {
        print("[MultiGalleryAudioStore] 🏗️ Initializing (using shared CuratorRuntime)")
        setupRuntimeCallbacks()
    }
    
    func setLibraryStore(_ store: ExhibitLibraryStore) {
        self.libraryStore = store
    }
    
    private func setupRuntimeCallbacks() {
        runtime.onStreamingText = { [weak self] text in
            self?.streamingText.append(text)
        }
        
        runtime.onStatusChange = { [weak self] status in
            self?.status = status
        }
        
        runtime.onGenerationComplete = { [weak self] completion in
            self?.handleGenerationComplete(completion)
        }
        
        runtime.onGenerationError = { [weak self] error in
            self?.handleGenerationError(error)
        }
        
        runtime.onPlaybackComplete = { [weak self] in
            print("[MultiGalleryAudioStore] 🔊 Playback complete, triggering callback")
            self?.onAudioPlaybackComplete?()
        }
        
        runtime.onAudioLevel = { [weak self] level in
            self?.audioLevel = level
        }
        
        runtime.onConversationStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                self.isConversationActive = false
                self.isGenerating = false
            case .listening:
                self.isGenerating = false
            case .processing:
                self.isGenerating = true
            case .speaking:
                self.isGenerating = false
            }
        }
    }
    
    func setContext(_ context: MultiGalleryContext) {
        print("[MultiGalleryAudioStore] 📍 Context changed to: \(debugContextType)")
        currentContext = context
    }
    
    func setHomeContext() {
        currentContext = .home
    }
    
    func setGalleriesOverviewContext() {
        currentContext = .galleriesOverview
    }
    
    func setExhibitContext(_ exhibit: ExhibitMeta) {
        currentContext = .exhibit(exhibit)
    }
    
    func setArtworkContext(exhibit: ExhibitMeta, artwork: Artwork) {
        currentContext = .artwork(exhibit, artwork)
    }
    
    func clearHistory() {
        messages.removeAll()
        streamingText = ""
        lastPromptDebug = ""
        print("[MultiGalleryAudioStore] History cleared")
    }
    
    private func clearHistoryForAutoplay() {
        if messages.count > 4 {
            messages.removeAll()
            print("[MultiGalleryAudioStore] Autoplay history cleared to free memory")
        }
    }
    
    private func trimHistoryIfNeeded() {
        if messages.count > 6 {
            let keepCount = 2
            messages = Array(messages.suffix(keepCount))
            print("[MultiGalleryAudioStore] Trimmed history to \(keepCount) messages")
        }
    }
    
    private func buildContextPacket() -> String {
        guard let store = libraryStore else {
            return "[No context available]"
        }
        
        switch currentContext {
        case .home:
            return HomeContextBuilder.buildContextPacket(
                artist: store.activeArtist ?? defaultArtist(),
                exhibits: store.exhibits,
                appHelp: store.appHelp
            )
            
        case .galleriesOverview:
            return ExhibitOverviewContextBuilder.buildContextPacket(
                exhibits: store.exhibits,
                artist: store.activeArtist ?? defaultArtist()
            )
            
        case .exhibit(let exhibit):
            return ExhibitContextBuilder.buildGeneralExhibitContext(
                exhibit: exhibit,
                artist: store.activeArtist,
                artworks: store.activeWorks
            )
            
        case .artwork(let exhibit, let artwork):
            return ExhibitContextBuilder.buildContextPacket(
                exhibit: exhibit,
                artist: store.activeArtist,
                artwork: artwork
            )
        }
    }
    
    private func defaultArtist() -> Artist {
        Artist(
            name: "Alex Covo",
            mission: "Fashion photography as story.",
            bio: "NYC-based fashion photographer",
            themes: ["street fashion", "editorial", "cinematic"]
        )
    }
    
    private func getCuratorInstructions() -> String {
        switch currentContext {
        case .home:
            return HomeContextBuilder.curatorInstructions
        case .galleriesOverview:
            return ExhibitOverviewContextBuilder.curatorInstructions
        case .exhibit, .artwork:
            return ExhibitContextBuilder.curatorInstructions
        }
    }
    
    /// Simple system prompt for push-to-talk (context is in user message)
    private func getSystemPrompt() -> String {
        return SystemPrompts.interleavedTextAndAudio
    }
    
    /// System prompt for conversation mode - MUST be exactly this string for LFM2.5
    private func getConversationSystemPrompt() -> String {
        return SystemPrompts.interleavedTextAndAudio
    }
    
    /// Compact context prefix for conversation mode audio - prepended to user audio
    func getConversationContextPrefix() -> String {
        let rules = getCuratorInstructions()
        let context = buildContextPacket()
        return buildUserPrompt(rules: rules, context: context, question: "[AUDIO]")
    }
    
    func setupModel() async {
        guard !runtime.isModelLoaded else {
            print("[MultiGalleryAudioStore] Model already loaded via runtime")
            messages.append(
                CuratorMessage(role: .assistant, text: "Welcome! I'm the curator for Alex Covo's photography exhibitions. Ask me anything or tap Enter Galleries to explore.", audioData: nil)
            )
            status = "Ready"
            return
        }
        
        isModelLoading = true
        status = "Loading model..."
        
        do {
            try await runtime.loadModel()
            messages.append(
                CuratorMessage(role: .assistant, text: "Welcome! I'm the curator for Alex Covo's photography exhibitions. Ask me anything or tap Enter Galleries to explore.", audioData: nil)
            )
            status = "Ready"
        } catch {
            print("[MultiGalleryAudioStore] Failed to load model: \(error)")
            status = "Failed to load model: \(error.localizedDescription)"
        }
        
        isModelLoading = false
    }
    
    func speakAboutCurrentArtwork() {
        print("[MultiGalleryAudioStore] 🎬 speakAboutCurrentArtwork()")
        clearHistoryForAutoplay()
        let prompt = "Tell me about this artwork in 2-3 sentences."
        sendTextPrompt(prompt)
    }
    
    func startAutoTourMode() async {
        print("[MultiGalleryAudioStore] 🎬 Starting Auto Tour mode")
        await runtime.startAutoTour()
    }
    
    func startPushToTalkMode() async {
        print("[MultiGalleryAudioStore] 🎤 Starting Push-to-Talk mode")
        await runtime.startPushToTalk()
    }
    
    func hardReset() async {
        print("[MultiGalleryAudioStore] 🔄 Requesting hard reset")
        await runtime.hardReset()
        isGenerating = false
        isRecording = false
        streamingText = ""
        status = "Ready"
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
        
        let rules = getCuratorInstructions()
        let contextPacket = buildContextPacket()
        let fullText = buildUserPrompt(rules: rules, context: contextPacket, question: trimmed)
        
        lastPromptDebug = "RULES:\n\(rules)\n\nCONTEXT:\n\(contextPacket)\n\nUSER QUESTION:\n\(trimmed)"
        print("[MultiGalleryAudioStore] 📝 Text prompt with context (\(fullText.count) chars)")
        
        let message = ChatMessage(role: .user, content: [.text(fullText)])
        appendUserMessage(text: trimmed)
        
        streamingText = ""
        isGenerating = true
        
        Task {
            await runtime.generate(message: message, systemPrompt: getSystemPrompt())
        }
    }
    
    func stopPlayback() {
        print("[MultiGalleryAudioStore] 🛑 stopPlayback()")
        Task {
            await runtime.hardReset()
        }
        isGenerating = false
        status = "Ready"
        trimHistoryIfNeeded()
    }
    
    func toggleRecording() {
        if isRecording {
            print("[MultiGalleryAudioStore] 🎤 Stopping recording")
            isRecording = false
            guard let capture = runtime.stopRecordingAndCapture() else {
                status = "No audio captured."
                return
            }
            sendAudioPrompt(samples: capture.samples, sampleRate: capture.sampleRate)
        } else {
            print("[MultiGalleryAudioStore] 🎤 Starting recording")
            do {
                try runtime.startRecording()
                isRecording = true
                status = "Recording..."
            } catch {
                status = "Recording failed: \(error.localizedDescription)"
            }
        }
    }
    
    func cancelRecording() {
        print("[MultiGalleryAudioStore] 🎤 Cancelling recording")
        runtime.cancelRecording()
        isRecording = false
        status = "Recording cancelled."
    }
    
    // MARK: - Conversation Mode
    
    /// Start real-time conversational mode
    /// Model handles speech flow natively - continuous listening and responding
    func startConversation() async {
        print("[MultiGalleryAudioStore] 💬 Starting conversation mode")
        
        let systemPrompt = getConversationSystemPrompt()
        let contextPrefix = getConversationContextPrefix()
        
        do {
            try await runtime.startConversation(systemPrompt: systemPrompt, contextPrefix: contextPrefix)
            isConversationActive = true
            status = "Listening..."
        } catch {
            status = "Failed to start conversation: \(error.localizedDescription)"
            print("[MultiGalleryAudioStore] ❌ Conversation start failed: \(error)")
        }
    }
    
    /// Stop conversational mode
    func stopConversation() {
        print("[MultiGalleryAudioStore] 💬 Stopping conversation mode")
        runtime.stopConversation()
        isConversationActive = false
        status = "Ready"
    }
    
    /// Toggle conversation mode on/off
    func toggleConversation() async {
        if isConversationActive {
            stopConversation()
        } else {
            await startConversation()
        }
    }
    
    /// Interrupt current model response (e.g., user wants to speak)
    func interruptConversation() {
        runtime.interruptConversation()
    }
    
    private func sendAudioPrompt(samples: [Float], sampleRate: Int) {
        guard !samples.isEmpty else {
            status = "Audio capture was empty."
            return
        }
        
        // Resample to 16kHz (model's expected rate) if needed
        let resampledSamples: [Float]
        let targetSampleRate: Int
        
        if sampleRate != AudioResampler.modelSampleRate {
            guard let resampled = AudioResampler.resampleTo16kHz(samples: samples, sourceSampleRate: sampleRate) else {
                status = "Failed to process audio."
                print("[MultiGalleryAudioStore] ❌ Failed to resample audio")
                return
            }
            resampledSamples = resampled
            targetSampleRate = AudioResampler.modelSampleRate
        } else {
            resampledSamples = samples
            targetSampleRate = sampleRate
        }
        
        let rules = getCuratorInstructions()
        let contextPacket = buildContextPacket()
        let fullContext = buildUserPrompt(rules: rules, context: contextPacket, question: "[AUDIO]")
        
        let audioContent = ChatMessageContent.fromFloatSamples(resampledSamples, sampleRate: targetSampleRate)
        let textContent = ChatMessageContent.text(fullContext)
        
        let chatMessage = ChatMessage(role: .user, content: [textContent, audioContent])
        
        lastPromptDebug = "RULES:\n\(rules)\n\nCONTEXT:\n\(contextPacket)\n\nUSER QUESTION:\n[AUDIO]"
        print("[MultiGalleryAudioStore] 🎙️ Audio prompt with context (\(fullContext.count) chars text + audio)")
        
        var display = "Voice question"
        if samples.count < sampleRate / 4 {
            display = "Voice question (brief)"
        }
        
        appendUserMessage(text: display)
        
        streamingText = ""
        isGenerating = true
        
        Task {
            await runtime.generate(message: chatMessage, systemPrompt: getSystemPrompt())
        }
    }
    
    private func appendUserMessage(text: String) {
        messages.append(CuratorMessage(role: .user, text: text, audioData: nil))
    }
    
    private func handleGenerationComplete(_ completion: MessageCompletion) {
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
        status = audioData != nil ? "Response complete." : "Ready"
        trimHistoryIfNeeded()
        print("[MultiGalleryAudioStore] ✅ Generation complete, message added")
    }
    
    private func handleGenerationError(_ error: Error) {
        isGenerating = false
        streamingText = ""
        status = "Error: \(error.localizedDescription)"
        print("[MultiGalleryAudioStore] ❌ Generation error: \(error)")
    }

    private func buildUserPrompt(rules: String, context: String, question: String) -> String {
        """
        RULES:
        \(rules)

        CONTEXT:
        \(context)

        USER QUESTION:
        \(question)
        """
    }
    
    func debugStatus() -> String {
        """
        [MultiGalleryAudioStore]
        context: \(debugContextType)
        messages: \(messages.count)
        isGenerating: \(isGenerating)
        isRecording: \(isRecording)
        status: \(status ?? "nil")
        
        \(runtime.debugStatus())
        """
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

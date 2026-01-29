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
    
    private let runtime = CuratorRuntime.shared
    
    init() {
        print("[CuratorAudioStore] 🏗️ Initializing (using shared CuratorRuntime)")
        setupRuntimeCallbacks()
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
        
        runtime.onGenerationStopped = { [weak self] in
            print("[CuratorAudioStore] ⏹️ Generation stopped (soft-stop)")
            self?.isGenerating = false
            self?.status = "Ready"
        }
        
        runtime.onPlaybackComplete = { [weak self] in
            print("[CuratorAudioStore] 🔊 Playback complete, triggering callback")
            self?.onAudioPlaybackComplete?()
        }
    }
    
    func speakAboutCurrentArtwork() {
        print("[CuratorAudioStore] 🎬 speakAboutCurrentArtwork()")
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
        streamingText = ""
        lastPromptDebug = ""
        print("[CuratorAudioStore] History cleared")
    }
    
    private func clearHistoryForAutoplay() {
        if messages.count > 4 {
            messages.removeAll()
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
        guard !runtime.isModelLoaded else {
            print("[CuratorAudioStore] Model already loaded via runtime")
            messages.append(
                CuratorMessage(role: .assistant, text: "Curator ready. Ask me about the exhibition.", audioData: nil)
            )
            status = "Ready"
            return
        }
        
        isModelLoading = true
        status = "Loading model..."
        
        do {
            try await runtime.loadModel()
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
    
    func startAutoTourMode() async {
        print("[CuratorAudioStore] 🎬 Starting Auto Tour mode")
        await runtime.startAutoTour()
    }
    
    func startPushToTalkMode() async {
        print("[CuratorAudioStore] 🎤 Starting Push-to-Talk mode")
        await runtime.startPushToTalk()
    }
    
    func hardReset() async {
        print("[CuratorAudioStore] 🔄 Requesting hard reset")
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
        
        let rules = CuratorContextBuilder.curatorInstructions
        let contextPacket = buildContextPacket()
        let fullText = buildUserPrompt(rules: rules, context: contextPacket, question: trimmed)
        
        lastPromptDebug = "RULES:\n\(rules)\n\nCONTEXT:\n\(contextPacket)\n\nUSER QUESTION:\n\(trimmed)"
        print("[CuratorAudioStore] 📝 Text prompt with context (\(fullText.count) chars)")
        
        let message = ChatMessage(role: .user, content: [.text(fullText)])
        appendUserMessage(text: trimmed)
        
        streamingText = ""
        isGenerating = true
        
        Task {
            await runtime.generate(message: message, systemPrompt: SystemPrompts.interleavedTextAndAudio)
        }
    }
    
    func stopPlayback() {
        print("[CuratorAudioStore] 🛑 stopPlayback()")
        Task {
            await runtime.hardReset()
        }
        isGenerating = false
        status = "Ready"
        trimHistoryIfNeeded()
    }
    
    func toggleRecording() {
        if isRecording {
            print("[CuratorAudioStore] 🎤 Stopping recording")
            isRecording = false
            guard let capture = runtime.stopRecordingAndCapture() else {
                status = "No audio captured."
                return
            }
            sendAudioPrompt(samples: capture.samples, sampleRate: capture.sampleRate)
        } else {
            print("[CuratorAudioStore] 🎤 Starting recording")
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
        print("[CuratorAudioStore] 🎤 Cancelling recording")
        runtime.cancelRecording()
        isRecording = false
        status = "Recording cancelled."
    }
    
    func playAudio(_ data: Data) {
        print("[CuratorAudioStore] 🔊 Playing audio data")
    }
    
    private func sendAudioPrompt(samples: [Float], sampleRate: Int) {
        guard !samples.isEmpty else {
            status = "Audio capture was empty."
            return
        }
        
        let rules = CuratorContextBuilder.curatorInstructions
        let contextPacket = buildContextPacket()
        let fullContext = buildUserPrompt(rules: rules, context: contextPacket, question: "[AUDIO]")
        
        let audioContent = ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate)
        let textContent = ChatMessageContent.text(fullContext)
        
        let chatMessage = ChatMessage(role: .user, content: [textContent, audioContent])
        
        lastPromptDebug = "RULES:\n\(rules)\n\nCONTEXT:\n\(contextPacket)\n\nUSER QUESTION:\n[AUDIO]"
        print("[CuratorAudioStore] 🎙️ Audio prompt with context (\(fullContext.count) chars text + audio)")
        
        var display = "Voice question"
        if samples.count < sampleRate / 4 {
            display = "Voice question (brief)"
        }
        
        appendUserMessage(text: display)
        
        streamingText = ""
        isGenerating = true
        
        Task {
            await runtime.generate(message: chatMessage, systemPrompt: SystemPrompts.interleavedTextAndAudio)
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
        print("[CuratorAudioStore] ✅ Generation complete, message added")
    }
    
    private func handleGenerationError(_ error: Error) {
        isGenerating = false
        streamingText = ""
        status = "Error: \(error.localizedDescription)"
        print("[CuratorAudioStore] ❌ Generation error: \(error)")
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
        [CuratorAudioStore]
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

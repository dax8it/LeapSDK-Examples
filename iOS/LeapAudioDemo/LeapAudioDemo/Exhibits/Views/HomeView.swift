import SwiftUI

struct HomeView: View {
    @Bindable var libraryStore: ExhibitLibraryStore
    @Bindable var audioStore: MultiGalleryAudioStore
    let onEnterGalleries: () -> Void
    
    @State private var showResponseOverlay = false
    @State private var lastResponseText = ""
    
    private let suggestedQuestions = [
        "Who is the artist?",
        "What galleries are available?",
        "How do I use this app?"
    ]
    
    private var videoURL: URL? {
        Bundle.main.url(forResource: "pari_rotate", withExtension: "mp4")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url = videoURL {
                    LoopingVideoPlayer(url: url)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    headerSection
                    
                    Spacer()
                    
                    if showResponseOverlay || audioStore.isGenerating || audioStore.status == "Speaking..." {
                        responseOverlay
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    
                    suggestedQuestionsSection
                        .padding(.bottom, 16)
                    
                    inputSection
                        .padding(.bottom, 16)
                    
                    enterGalleriesButton
                        .padding(.bottom, 40)
                }
            }
        }
        .task {
            audioStore.setLibraryStore(libraryStore)
            audioStore.setHomeContext()
            await audioStore.setupModel()
        }
        .onChange(of: audioStore.isGenerating) { _, isGenerating in
            if isGenerating {
                showResponseOverlay = true
            }
        }
        .onChange(of: audioStore.streamingText) { _, newText in
            if !newText.isEmpty {
                lastResponseText = newText
            }
        }
        .onDisappear {
            audioStore.stopAllActivities(reason: .navigationAway)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Text("Alex Covo")
                .font(.system(size: 42, weight: .light, design: .serif))
                .foregroundStyle(.white)
            
            Text("Fashion photography as story")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
    
    private var responseOverlay: some View {
        let textSource = audioStore.streamingText.isEmpty ? lastResponseText : audioStore.streamingText
        let cleanedText = textSource
            .replacingOccurrences(of: "<|text_end|>", with: "")
            .replacingOccurrences(of: "<|text_start|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return HStack(alignment: .top, spacing: 8) {
            if cleanedText.isEmpty && (audioStore.isGenerating || audioStore.status == "Speaking...") {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                    Text(audioStore.status == "Speaking..." ? "Speaking..." : "Thinking...")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(.white.opacity(0.9))
                }
            } else if !cleanedText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(cleanedText)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .id("responseText")
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: cleanedText) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("responseText", anchor: .bottom)
                        }
                    }
                }
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showResponseOverlay = false
                    lastResponseText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }
    
    private var suggestedQuestionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        audioStore.sendTextPrompt(question)
                    } label: {
                        Text(question)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .disabled(audioStore.isGenerating || audioStore.isModelLoading)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            if audioStore.isConversationActive {
                conversationActiveView
            } else {
                HStack(spacing: 12) {
                    TextField("Ask me anything...", text: $audioStore.inputText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .onSubmit {
                            audioStore.sendTextPrompt()
                        }
                    
                    // Push-to-talk button
                    Button {
                        audioStore.toggleRecording()
                    } label: {
                        Image(systemName: audioStore.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(audioStore.isRecording ? Color.red : Color.white.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .disabled(audioStore.isModelLoading || audioStore.isGenerating)
                    
                    // Conversation mode button
                    Button {
                        Task {
                            await audioStore.startConversation()
                        }
                    } label: {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .disabled(audioStore.isModelLoading || audioStore.isGenerating || audioStore.isRecording)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var conversationActiveView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(Double(i) < Double(audioStore.audioLevel * 7) ? 1.0 : 0.3))
                        .frame(width: 6, height: CGFloat(8 + i * 4))
                }
            }
            .frame(height: 36)
            
            HStack(spacing: 16) {
                // Mute button
                Button {
                    audioStore.toggleMute()
                } label: {
                    Image(systemName: audioStore.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(audioStore.isMuted ? Color.orange.opacity(0.8) : Color.white.opacity(0.3))
                        .clipShape(Circle())
                }
                
                // End Conversation button
                Button {
                    audioStore.stopAllActivities(reason: .manualStop)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        Text("End Conversation")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var enterGalleriesButton: some View {
        Button {
            audioStore.stopAllActivities(reason: .navigationAway)
            onEnterGalleries()
        } label: {
            Text("Enter Galleries")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
                .background(.white)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    HomeView(
        libraryStore: ExhibitLibraryStore(),
        audioStore: MultiGalleryAudioStore(),
        onEnterGalleries: {}
    )
}

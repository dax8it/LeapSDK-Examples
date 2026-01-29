import SwiftUI

struct GalleriesOverviewView: View {
    @Bindable var libraryStore: ExhibitLibraryStore
    @Bindable var audioStore: MultiGalleryAudioStore
    let onSelectExhibit: (ExhibitMeta) -> Void
    let onGoHome: () -> Void
    
    @State private var showResponseOverlay = false
    @State private var lastResponseText = ""
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private let suggestedQuestions = [
        "What is Black Canvas about?",
        "Which gallery should I start with?",
        "Tell me about Moon Rising"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                            .padding(.top, 16)
                        
                        if showResponseOverlay || audioStore.isGenerating || audioStore.status == "Speaking..." {
                            responseOverlay
                                .padding(.horizontal, 20)
                        }
                        
                        suggestedQuestionsSection
                        
                        exhibitGrid
                            .padding(.horizontal, 16)
                        
                        inputSection
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Galleries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        audioStore.stopAllActivities(reason: .navigationAway)
                        onGoHome()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .task {
            audioStore.setLibraryStore(libraryStore)
            audioStore.setGalleriesOverviewContext()
            audioStore.clearHistory()
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
        VStack(spacing: 8) {
            Text("Select a Gallery")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            
            Text("Tap to enter, or ask me about any collection")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
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
                    .frame(maxHeight: 100)
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
        .background(Color.white.opacity(0.1))
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
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .disabled(audioStore.isGenerating || audioStore.isModelLoading)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var exhibitGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(libraryStore.exhibitsWithImages) { exhibit in
                ExhibitCard(exhibit: exhibit) {
                    audioStore.stopAllActivities(reason: .contextSwitch)
                    onSelectExhibit(exhibit)
                }
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            if audioStore.isConversationActive {
                conversationActiveView
            } else {
                HStack(spacing: 12) {
                    TextField("Ask about galleries...", text: $audioStore.inputText)
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
        .padding(.vertical, 8)
    }
}

struct ExhibitCard: View {
    let exhibit: ExhibitMeta
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let imageName = exhibit.effectiveCoverImageName,
                       let uiImage = loadCoverImage(named: imageName) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "photo.stack")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exhibit.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(exhibit.shortStatement)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private func loadCoverImage(named name: String) -> UIImage? {
        ImageLoader.loadArtworkImage(named: name)
    }
}

#Preview {
    GalleriesOverviewView(
        libraryStore: ExhibitLibraryStore(),
        audioStore: MultiGalleryAudioStore(),
        onSelectExhibit: { _ in },
        onGoHome: {}
    )
}

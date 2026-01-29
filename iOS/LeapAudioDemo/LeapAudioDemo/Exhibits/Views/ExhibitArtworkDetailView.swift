import SwiftUI

struct ExhibitArtworkDetailView: View {
    @Bindable var libraryStore: ExhibitLibraryStore
    @Bindable var audioStore: MultiGalleryAudioStore
    let exhibit: ExhibitMeta
    let artworks: [Artwork]
    let initialIndex: Int
    let startAutoplay: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showSummaryOverlay = false
    @State private var showResponseOverlay = false
    @State private var lastResponseText = ""
    @State private var isAutoplayActive = false
    @State private var autoplayPaused = false
    @State private var tourSessionID = UUID()
    @State private var autoplayCompletionToken: UUID?
    @State private var isAdvancing = false
    
    init(libraryStore: ExhibitLibraryStore, audioStore: MultiGalleryAudioStore, exhibit: ExhibitMeta, artworks: [Artwork], initialIndex: Int, startAutoplay: Bool = false) {
        self.libraryStore = libraryStore
        self.audioStore = audioStore
        self.exhibit = exhibit
        self.artworks = artworks
        self.initialIndex = initialIndex
        self.startAutoplay = startAutoplay
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    private var currentArtwork: Artwork {
        artworks[currentIndex]
    }
    
    var body: some View {
        Group {
            if artworks.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    ZStack {
                        fullScreenImage(geometry: geometry)
                        
                        VStack(spacing: 0) {
                            navigationArrows
                            Spacer()
                            
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 4) {
                                    titleOverlay
                                    if showResponseOverlay || audioStore.isGenerating || audioStore.status == "Speaking..." {
                                        responseOverlay
                                    }
                                }
                                
                                Spacer()
                                
                                if currentArtwork.hasMetadata {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            showSummaryOverlay = true
                                        }
                                    } label: {
                                        Circle()
                                            .fill(Color.white.opacity(0.65))
                                            .frame(width: 44, height: 44)
                                            .overlay {
                                                Image(systemName: "info")
                                                    .font(.system(size: 20, weight: .medium))
                                                    .foregroundStyle(.black.opacity(0.8))
                                            }
                                    }
                                    .padding(.trailing, 16)
                                }
                            }
                            .padding(.bottom, 16)
                            
                            inputSection
                                .padding(.top, 24)
                        }
                        
                        if showSummaryOverlay {
                            summaryOverlay
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if currentIndex < artworks.count - 1 {
                                currentIndex += 1
                            } else {
                                currentIndex = 0
                            }
                        }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if currentIndex > 0 {
                                currentIndex -= 1
                            } else {
                                currentIndex = artworks.count - 1
                            }
                        }
                    }
                }
        )
        .task {
            updateContext()
            setupAutoplayCallback()
            if startAutoplay {
                startAutoplayTour()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            audioStore.stopAllActivities(reason: .contextSwitch)
            autoplayCompletionToken = nil
            updateContext()
            if isAutoplayActive && !autoplayPaused {
                showResponseOverlay = true
                beginNarration(for: tourSessionID)
            }
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
            stopAutoplay()
        }
    }
    
    private func setupAutoplayCallback() {
        audioStore.onAudioPlaybackComplete = { [self] in
            guard let token = autoplayCompletionToken else { return }
            guard shouldAdvance(for: token) else { return }
            autoplayCompletionToken = nil
            advanceToNextArtwork(for: token)
        }
    }
    
    private func startAutoplayTour() {
        print("[ExhibitArtworkDetailView] 🎬 Starting autoplay tour")
        audioStore.stopAllActivities(reason: .newRequest)
        isAutoplayActive = true
        autoplayPaused = false
        isAdvancing = false
        tourSessionID = UUID()
        autoplayCompletionToken = nil
        showResponseOverlay = true
        Task {
            await audioStore.startAutoTourMode()
            beginNarration(for: tourSessionID)
        }
    }
    
    private func toggleAutoplayPause() {
        if autoplayPaused {
            print("[ExhibitArtworkDetailView] ▶️ Resuming autoplay")
            autoplayPaused = false
            beginNarration(for: tourSessionID)
        } else {
            print("[ExhibitArtworkDetailView] ⏸️ Pausing autoplay")
            autoplayPaused = true
            autoplayCompletionToken = nil
            audioStore.stopAllActivities(reason: .manualStop)
        }
    }
    
    private func stopAutoplay() {
        print("[ExhibitArtworkDetailView] 🛑 Stopping autoplay")
        isAutoplayActive = false
        autoplayPaused = false
        isAdvancing = false
        autoplayCompletionToken = nil
        tourSessionID = UUID()
        audioStore.stopAllActivities(reason: .manualStop)
    }
    
    private func shouldAdvance(for token: UUID) -> Bool {
        isAutoplayActive && !autoplayPaused && tourSessionID == token
    }

    private func beginNarration(for token: UUID) {
        guard shouldAdvance(for: token) else { return }
        autoplayCompletionToken = token
        audioStore.speakAboutCurrentArtwork()
    }

    private func advanceToNextArtwork(for token: UUID) {
        guard shouldAdvance(for: token) else { return }
        guard !isAdvancing else { return }
        isAdvancing = true

        if currentIndex < artworks.count - 1 {
            showResponseOverlay = false
            lastResponseText = ""
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex += 1
            }
            isAdvancing = false
        } else {
            isAdvancing = false
            stopAutoplay()
        }
    }
    
    private func updateContext() {
        guard currentIndex >= 0, currentIndex < artworks.count else { return }
        libraryStore.selectArtwork(currentArtwork)
        audioStore.setArtworkContext(exhibit: exhibit, artwork: currentArtwork)
    }
    
    @ViewBuilder
    private func fullScreenImage(geometry: GeometryProxy) -> some View {
        if let uiImage = loadImage(named: currentArtwork.imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .ignoresSafeArea()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                }
                .ignoresSafeArea()
        }
    }
    
    private var navigationArrows: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    audioStore.stopAllActivities(reason: .navigationAway)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.65))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if currentIndex > 0 {
                            currentIndex -= 1
                        } else {
                            currentIndex = artworks.count - 1
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.65))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                if isAutoplayActive {
                    Button {
                        toggleAutoplayPause()
                    } label: {
                        Image(systemName: autoplayPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if currentIndex < artworks.count - 1 {
                            currentIndex += 1
                        } else {
                            currentIndex = 0
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.65))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var titleOverlay: some View {
        HStack {
            Text("\"\(currentArtwork.displayTitle)\"")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
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
                            .italic()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .id("responseText")
                    }
                    .frame(maxHeight: 80)
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
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: audioStore.streamingText)
    }
    
    private var summaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSummaryOverlay = false
                    }
                }
            
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(currentArtwork.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSummaryOverlay = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !currentArtwork.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("About")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(currentArtwork.summary)
                                    .font(.body)
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        if !currentArtwork.story.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Story")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(currentArtwork.story)
                                    .font(.body)
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        if !currentArtwork.technique.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Technique")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(currentArtwork.technique)
                                    .font(.body)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity)
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            if audioStore.isModelLoading {
                HStack {
                    ProgressView()
                        .tint(.gray)
                    Text("Loading curator...")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                .padding(.bottom, 8)
            }
            
            if let status = audioStore.status, status != "Ready" {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
            
            // Conversation mode active view
            if audioStore.isConversationActive {
                conversationActiveView
            } else {
                // Standard input controls
                HStack(spacing: 12) {
                    TextField("Ask about this work", text: $audioStore.inputText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .onSubmit {
                            if isAutoplayActive {
                                stopAutoplay()
                            }
                            audioStore.sendTextPrompt()
                        }
                    
                    // Push-to-talk button
                    Button {
                        if isAutoplayActive {
                            stopAutoplay()
                        }
                        audioStore.toggleRecording()
                    } label: {
                        Image(systemName: audioStore.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(audioStore.isRecording ? Color.red : Color.gray.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .disabled(audioStore.isModelLoading || audioStore.isGenerating)
                    
                    // Conversation mode button
                    Button {
                        if isAutoplayActive {
                            stopAutoplay()
                        }
                        Task {
                            await audioStore.startConversation()
                        }
                    } label: {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .disabled(audioStore.isModelLoading || audioStore.isGenerating || audioStore.isRecording)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Color(white: 0.15))
    }
    
    private var conversationActiveView: some View {
        VStack(spacing: 12) {
            // Audio level indicator
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(Double(i) < Double(audioStore.audioLevel * 7) ? 1.0 : 0.3))
                        .frame(width: 6, height: CGFloat(8 + i * 4))
                }
            }
            .frame(height: 36)
            
            // Stop conversation button
            Button {
                audioStore.stopConversation()
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
        .padding(.vertical, 16)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No artwork available")
                .font(.headline)
                .foregroundStyle(.white)
            Button("Close") {
                dismiss()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
    
    private func loadImage(named name: String) -> UIImage? {
        ImageLoader.loadArtworkImage(named: name)
    }
}

#Preview {
    ExhibitArtworkDetailView(
        libraryStore: ExhibitLibraryStore(),
        audioStore: MultiGalleryAudioStore(),
        exhibit: ExhibitMeta(id: "test", title: "Test", shortStatement: "Test", coverImageName: nil, order: 1),
        artworks: [
            Artwork(
                id: "work-01",
                title: "In-Between, DUMBO",
                year: "2023",
                medium: "Photograph (Black & White)",
                summary: "A test summary",
                story: "A test story",
                technique: "A test technique",
                tags: ["black and white", "street", "fashion"],
                imageName: "work-01.jpg",
                quote: "The best moments are the ones you almost miss."
            )
        ],
        initialIndex: 0
    )
}

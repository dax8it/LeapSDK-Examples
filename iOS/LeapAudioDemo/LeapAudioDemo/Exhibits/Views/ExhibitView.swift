import SwiftUI

struct ExhibitView: View {
    @Bindable var libraryStore: ExhibitLibraryStore
    @Bindable var audioStore: MultiGalleryAudioStore
    let exhibit: ExhibitMeta
    let onGoHome: () -> Void
    let onGoBack: () -> Void
    
    @State private var selectedIndex: Int?
    @State private var startAutoplay = false
    @State private var showResponseOverlay = false
    @State private var lastResponseText = ""
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        exhibitHeader
                            .padding(.top, 8)
                        
                        if showResponseOverlay || audioStore.isGenerating || audioStore.status == "Speaking..." {
                            responseOverlay
                                .padding(.horizontal, 16)
                        }
                        
                        tourControls
                            .padding(.horizontal, 16)
                        
                        artworkGrid
                        
                        inputSection
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(exhibit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await audioStore.hardReset()
                            }
                            onGoHome()
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.subheadline)
                        }
                        
                        Button {
                            Task {
                                await audioStore.hardReset()
                            }
                            onGoBack()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                Text("Galleries")
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .fullScreenCover(item: Binding(
                get: { selectedIndex.map { ExhibitIndexWrapper(index: $0, autoplay: startAutoplay, exhibit: exhibit) } },
                set: {
                    selectedIndex = $0?.index
                    startAutoplay = false
                }
            )) { wrapper in
                ExhibitArtworkDetailView(
                    libraryStore: libraryStore,
                    audioStore: audioStore,
                    exhibit: wrapper.exhibit,
                    artworks: libraryStore.activeWorks,
                    initialIndex: wrapper.index,
                    startAutoplay: wrapper.autoplay
                )
            }
        }
        .task {
            libraryStore.selectExhibit(exhibit)
            audioStore.setLibraryStore(libraryStore)
            audioStore.setExhibitContext(exhibit)
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
    }
    
    private var exhibitHeader: some View {
        VStack(spacing: 8) {
            Text(exhibit.shortStatement)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            if let artist = libraryStore.activeArtist {
                Text("by \(artist.name)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
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
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }
    
    private var tourControls: some View {
        HStack(spacing: 16) {
            Button {
                guard !libraryStore.activeWorks.isEmpty else { return }
                startAutoplay = true
                selectedIndex = 0
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Start Auto Tour")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white)
                .clipShape(Capsule())
            }
            .disabled(libraryStore.activeWorks.isEmpty)
            
            Text("\(libraryStore.activeWorks.count) works")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    
    private var artworkGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(libraryStore.activeWorks.enumerated()), id: \.element.id) { index, artwork in
                ExhibitArtworkThumbnail(artwork: artwork)
                    .onTapGesture {
                        startAutoplay = false
                        selectedIndex = index
                    }
            }
        }
    }
    
    private var inputSection: some View {
        HStack(spacing: 12) {
            TextField("Ask about this gallery...", text: $audioStore.inputText)
                .textFieldStyle(.plain)
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
                .onSubmit {
                    audioStore.sendTextPrompt()
                }
            
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
        }
        .padding(.horizontal, 20)
    }
}

struct ExhibitIndexWrapper: Identifiable {
    let index: Int
    let autoplay: Bool
    let exhibit: ExhibitMeta
    var id: String { "\(exhibit.id)-\(index)" }
}

struct ExhibitArtworkThumbnail: View {
    let artwork: Artwork
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let uiImage = loadImage(named: artwork.imageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.gray)
                        }
                }
                
                if !artwork.title.isEmpty {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    
                    Text(artwork.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(8)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func loadImage(named name: String) -> UIImage? {
        let baseName = name.replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".png", with: "")
        
        if let bundlePath = Bundle.main.path(forResource: baseName, ofType: "jpg", inDirectory: "Artworks") {
            return UIImage(contentsOfFile: bundlePath)
        }
        if let bundlePath = Bundle.main.path(forResource: baseName, ofType: "jpg") {
            return UIImage(contentsOfFile: bundlePath)
        }
        if let asset = UIImage(named: baseName) {
            return asset
        }
        return nil
    }
}

#Preview {
    ExhibitView(
        libraryStore: ExhibitLibraryStore(),
        audioStore: MultiGalleryAudioStore(),
        exhibit: ExhibitMeta(
            id: "black-canvas",
            title: "Black Canvas",
            shortStatement: "A gritty black-and-white collection.",
            coverImageName: nil,
            order: 1
        ),
        onGoHome: {},
        onGoBack: {}
    )
}

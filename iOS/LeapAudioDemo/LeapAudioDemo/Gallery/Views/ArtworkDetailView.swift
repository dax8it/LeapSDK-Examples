import SwiftUI

struct ArtworkDetailView: View {
    let artworks: [Artwork]
    let initialIndex: Int
    let artist: Artist?
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var store = CuratorAudioStore()
    
    init(artworks: [Artwork], initialIndex: Int, artist: Artist?) {
        self.artworks = artworks
        self.initialIndex = initialIndex
        self.artist = artist
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    private var currentArtwork: Artwork {
        artworks[currentIndex]
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    imageSection(geometry: geometry)
                    quoteSection
                    Spacer(minLength: 0)
                    inputSection
                }
            }
        }
        .task {
            await store.setupModel()
            updateContext()
        }
        .onChange(of: currentIndex) { _, _ in
            updateContext()
        }
    }
    
    private func updateContext() {
        store.setContext(artist: artist, artwork: currentArtwork)
    }
    
    @ViewBuilder
    private func imageSection(geometry: GeometryProxy) -> some View {
        let imageHeight = geometry.size.height * 0.65
        
        ZStack {
            if let uiImage = loadImage(named: currentArtwork.imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: imageHeight)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: geometry.size.width, height: imageHeight)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                    }
            }
            
            VStack {
                navigationArrows
                Spacer()
                titleOverlay
            }
            .frame(width: geometry.size.width, height: imageHeight)
        }
        .frame(height: imageHeight)
    }
    
    private var navigationArrows: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(.white)
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
                        .foregroundStyle(.black)
                        .frame(width: 50, height: 50)
                        .background(.white)
                        .clipShape(Circle())
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
                        .foregroundStyle(.black)
                        .frame(width: 50, height: 50)
                        .background(.white)
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
    
    private var quoteSection: some View {
        VStack(spacing: 0) {
            if let quote = currentArtwork.quote, !quote.isEmpty {
                Text("\"\(quote)\" – AC")
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
        .background(Color.black)
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            if store.isModelLoading {
                HStack {
                    ProgressView()
                        .tint(.gray)
                    Text("Loading curator...")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                .padding(.bottom, 8)
            }
            
            if let status = store.status, status != "Ready" {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
            
            HStack(spacing: 12) {
                TextField("Ask about this work", text: $store.inputText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .onSubmit {
                        store.sendTextPrompt()
                    }
                
                Button {
                    store.toggleRecording()
                } label: {
                    Image(systemName: store.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(store.isRecording ? Color.red : Color.gray.opacity(0.8))
                        .clipShape(Circle())
                }
                .disabled(store.isModelLoading || store.isGenerating)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color(white: 0.15))
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
    ArtworkDetailView(
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
        initialIndex: 0,
        artist: nil
    )
}

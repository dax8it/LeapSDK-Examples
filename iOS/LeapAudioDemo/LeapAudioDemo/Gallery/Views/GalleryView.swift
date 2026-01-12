import SwiftUI

struct GalleryView: View {
    let exhibitStore: ExhibitStore
    @State private var selectedArtwork: Artwork?
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = exhibitStore.loadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(exhibitStore.artworks) { artwork in
                            ArtworkThumbnail(artwork: artwork)
                                .onTapGesture {
                                    selectedArtwork = artwork
                                }
                        }
                    }
                }
            }
            .navigationTitle(exhibitStore.artist?.name ?? "Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedArtwork) { artwork in
                ArtworkDetailView(
                    artwork: artwork,
                    artist: exhibitStore.artist
                )
            }
        }
    }
}

struct ArtworkThumbnail: View {
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
    GalleryView(exhibitStore: ExhibitStore())
}

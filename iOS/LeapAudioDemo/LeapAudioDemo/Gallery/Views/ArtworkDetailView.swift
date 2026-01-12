import SwiftUI

struct ArtworkDetailView: View {
    let artwork: Artwork
    let artist: Artist?
    @Environment(\.dismiss) private var dismiss
    @State private var showCurator = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    artworkImage
                    
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        
                        if !artwork.summary.isEmpty {
                            section(title: "About", content: artwork.summary)
                        }
                        
                        if !artwork.story.isEmpty {
                            section(title: "Story", content: artwork.story)
                        }
                        
                        if !artwork.technique.isEmpty {
                            section(title: "Technique", content: artwork.technique)
                        }
                        
                        if !artwork.tags.isEmpty {
                            tagsSection
                        }
                        
                        askCuratorButton
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCurator) {
                ArtworkCuratorSheet(artwork: artwork, artist: artist)
            }
        }
    }
    
    private var artworkImage: some View {
        GeometryReader { geometry in
            if let uiImage = loadImage(named: artwork.imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.width * 1.2)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.gray)
                    }
            }
        }
        .aspectRatio(1/1.2, contentMode: .fit)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artwork.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack(spacing: 8) {
                if !artwork.year.isEmpty {
                    Text(artwork.year)
                        .foregroundStyle(.secondary)
                }
                if !artwork.medium.isEmpty {
                    if !artwork.year.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                    }
                    Text(artwork.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
    }
    
    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(content)
                .font(.body)
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(artwork.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private var askCuratorButton: some View {
        Button {
            showCurator = true
        } label: {
            Label("Ask about this work", systemImage: "mic.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 12)
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}

struct ArtworkCuratorSheet: View {
    let artwork: Artwork
    let artist: Artist?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            CuratorChatView(
                exhibitStore: nil,
                focusedArtwork: artwork,
                focusedArtist: artist
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ArtworkDetailView(
        artwork: Artwork(
            id: "work-01",
            title: "In-Between, DUMBO",
            year: "2023",
            medium: "Photograph (Black & White)",
            summary: "A test summary",
            story: "A test story",
            technique: "A test technique",
            tags: ["black and white", "street", "fashion"],
            imageName: "work-01.jpg"
        ),
        artist: nil
    )
}

import SwiftUI

enum MultiGalleryScreen {
    case home
    case galleriesOverview
    case exhibit(ExhibitMeta)
}

struct MultiGalleryRootView: View {
    @State private var libraryStore = ExhibitLibraryStore()
    @State private var audioStore = MultiGalleryAudioStore()
    @State private var currentScreen: MultiGalleryScreen = .home
    @State private var showDebugPanel = false
    
    var body: some View {
        ZStack {
            Group {
                switch currentScreen {
                case .home:
                    HomeView(
                        libraryStore: libraryStore,
                        audioStore: audioStore,
                        onEnterGalleries: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentScreen = .galleriesOverview
                            }
                        }
                    )
                    .transition(.opacity)
                    
                case .galleriesOverview:
                    GalleriesOverviewView(
                        libraryStore: libraryStore,
                        audioStore: audioStore,
                        onSelectExhibit: { exhibit in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentScreen = .exhibit(exhibit)
                            }
                        },
                        onGoHome: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentScreen = .home
                            }
                        }
                    )
                    .transition(.opacity)
                    
                case .exhibit(let exhibit):
                    ExhibitView(
                        libraryStore: libraryStore,
                        audioStore: audioStore,
                        exhibit: exhibit,
                        onGoHome: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                libraryStore.clearActiveExhibit()
                                currentScreen = .home
                            }
                        },
                        onGoBack: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                libraryStore.clearActiveExhibit()
                                currentScreen = .galleriesOverview
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
            
            if showDebugPanel {
                debugOverlay
            }
        }
        .task {
            libraryStore.loadIndex()
        }
        .gesture(
            TapGesture(count: 3)
                .onEnded {
                    showDebugPanel.toggle()
                }
        )
    }
    
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DEBUG")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
                Spacer()
                Button {
                    showDebugPanel = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            
            Divider().background(.white.opacity(0.3))
            
            Group {
                debugRow("Screen", value: screenName)
                debugRow("Active Exhibit", value: libraryStore.debugActiveExhibitID)
                debugRow("Selected Artwork", value: libraryStore.debugSelectedArtworkID)
                debugRow("Context", value: audioStore.debugContextType)
                debugRow("Generation Active", value: audioStore.debugIsGenerationActive ? "YES" : "no")
                debugRow("Messages", value: "\(audioStore.messages.count)")
            }
            
            Divider().background(.white.opacity(0.3))
            
            Text("Context Preview:")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            
            Text(audioStore.debugContextPacketPreview)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(6)
            
            Button {
                Task {
                    await audioStore.hardReset()
                }
            } label: {
                Text("Hard Reset")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }
    
    private var screenName: String {
        switch currentScreen {
        case .home: return "Home"
        case .galleriesOverview: return "Galleries Overview"
        case .exhibit(let e): return "Exhibit: \(e.id)"
        }
    }
}

#Preview {
    MultiGalleryRootView()
}

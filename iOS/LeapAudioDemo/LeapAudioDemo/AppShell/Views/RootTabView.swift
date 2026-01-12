import SwiftUI

struct RootTabView: View {
    @State private var exhibitStore = ExhibitStore()
    @State private var showIntro = true
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if showIntro {
                IntroView(artist: exhibitStore.artist) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showIntro = false
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    GalleryView(exhibitStore: exhibitStore)
                        .tabItem {
                            Label("Gallery", systemImage: "photo.on.rectangle")
                        }
                        .tag(0)
                    
                    CuratorChatView(exhibitStore: exhibitStore)
                        .tabItem {
                            Label("Curator", systemImage: "mic.circle")
                        }
                        .tag(1)
                }
            }
        }
        .task {
            exhibitStore.load()
        }
    }
}

#Preview {
    RootTabView()
}

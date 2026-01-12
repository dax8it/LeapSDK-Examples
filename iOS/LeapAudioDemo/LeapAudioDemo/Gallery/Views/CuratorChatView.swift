import SwiftUI

struct CuratorChatView: View {
    var exhibitStore: ExhibitStore?
    var focusedArtwork: Artwork?
    var focusedArtist: Artist?
    
    @State private var store = CuratorAudioStore()
    
    init(exhibitStore: ExhibitStore) {
        self.exhibitStore = exhibitStore
        self.focusedArtwork = nil
        self.focusedArtist = nil
    }
    
    init(exhibitStore: ExhibitStore?, focusedArtwork: Artwork?, focusedArtist: Artist?) {
        self.exhibitStore = exhibitStore
        self.focusedArtwork = focusedArtwork
        self.focusedArtist = focusedArtist
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if store.isModelLoading {
                    ProgressView("Loading curator...")
                        .padding()
                }
                
                messageList
                
                if let status = store.status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                inputControls
            }
            .padding()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await store.setupModel()
            configureContext()
        }
    }
    
    private var navigationTitle: String {
        if let artwork = focusedArtwork {
            return artwork.displayTitle
        }
        return "Curator"
    }
    
    private func configureContext() {
        if let artwork = focusedArtwork {
            store.setContext(artist: focusedArtist ?? exhibitStore?.artist, artwork: artwork)
        } else if let exhibitStore = exhibitStore {
            store.setContext(artist: exhibitStore.artist, artworks: exhibitStore.artworks)
        }
    }
    
    private var messageList: some View {
        List {
            ForEach(store.messages) { message in
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                            .padding(12)
                            .background(message.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                            .cornerRadius(14)
                            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    }
                    
                    if let audioData = message.audioData {
                        Button {
                            store.playAudio(audioData)
                        } label: {
                            Label("Play audio", systemImage: "play.circle")
                        }
                        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
            
            if !store.streamingText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.streamingText)
                        .font(.body)
                        .padding(12)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
    }
    
    private var inputControls: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Ask the curator...", text: $store.inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Send") {
                    store.sendTextPrompt()
                }
                .disabled(
                    store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || store.isGenerating
                )
            }
            
            HStack {
                Button {
                    store.toggleRecording()
                } label: {
                    Label(
                        store.isRecording ? "Stop" : "Ask",
                        systemImage: store.isRecording ? "stop.circle.fill" : "mic.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                if store.isRecording {
                    Button("Cancel") {
                        store.cancelRecording()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if store.isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
    }
}

#Preview {
    CuratorChatView(exhibitStore: ExhibitStore())
}

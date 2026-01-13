import SwiftUI
import AVKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView(url: url)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    class PlayerUIView: UIView {
        private var playerLayer = AVPlayerLayer()
        private var playerLooper: AVPlayerLooper?
        
        init(url: URL) {
            super.init(frame: .zero)
            
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let queuePlayer = AVQueuePlayer(playerItem: item)
            
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            
            queuePlayer.isMuted = true
            playerLayer.player = queuePlayer
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            
            queuePlayer.play()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

struct IntroView: View {
    let artist: Artist?
    let onEnter: () -> Void
    
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
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        if let artist = artist {
                            Text(artist.name)
                                .font(.system(size: 42, weight: .light, design: .serif))
                                .foregroundStyle(.white)
                            
                            Text(artist.mission)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("Gallery")
                                .font(.system(size: 42, weight: .light, design: .serif))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onEnter) {
                        Text("Enter Exhibition")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 60)
                }
            }
        }
    }
}

#Preview {
    IntroView(
        artist: Artist(
            name: "Alex Covo",
            mission: "Fashion photography as story.",
            bio: "NYC-based photographer",
            themes: ["street", "editorial"]
        ),
        onEnter: {}
    )
}

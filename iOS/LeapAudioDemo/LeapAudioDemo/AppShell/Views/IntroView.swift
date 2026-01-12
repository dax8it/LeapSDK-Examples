import SwiftUI

struct IntroView: View {
    let artist: Artist?
    let onEnter: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
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

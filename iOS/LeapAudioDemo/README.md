# LeapAudioDemo — Gallery Curator

A SwiftUI app demonstrating on-device AI audio interaction using the LeapSDK and LFM2.5 Audio model. Features a **Gallery Curator** mode where visitors can browse artworks and interact with an AI curator via voice.

## Features

### Audio Demo (Original)
- Real-time audio recording and playback
- Audio processing with LFM2.5 Audio model
- Streaming audio response playback
- Local on-device AI inference

### Gallery Curator
- **Artwork Gallery** — Browse up to 20 artworks in a full-screen grid
- **Push-to-Talk** — Ask questions about any artwork via voice
- **Autoplay Tour** — AI automatically narrates each artwork sequentially
- **Offline Operation** — No network required, fully on-device
- **Context-Aware AI** — Responses grounded in exhibit metadata

## Requirements

- iOS 18.0+
- Xcode 15.0+
- XcodeGen: `brew install xcodegen`
- Python 3.8+ (for downloading models)

## Quick Start

### 1. Download the Model
```bash
pip install leap-bundle
leap-bundle download LFM2.5-Audio-1.5B --quantization=Q8_0
```

Downloads 4 GGUF files (~1.9GB total):
- `LFM2.5-Audio-1.5B-Q8_0.gguf` — Main language model
- `mmproj-LFM2.5-Audio-1.5B-Q8_0.gguf` — Audio encoder
- `vocoder-LFM2.5-Audio-1.5B-Q8_0.gguf` — Audio decoder
- `tokenizer-LFM2.5-Audio-1.5B-Q8_0.gguf` — Audio tokenizer

### 2. Copy Model Files
```bash
cp LiquidAI_LeapBundles_LFM2_5_Audio_1_5B_GGUF_Q8_0/*.gguf LeapAudioDemo/Resources/
```

### 3. Setup & Run
```bash
make setup    # Generate Xcode project
make open     # Open in Xcode
# Press Cmd+R to build and run
```

## Project Structure

```
LeapAudioDemo/
├── project.yml                          # XcodeGen configuration
├── Makefile                             # Build automation
├── README.md                            # This file
├── Docs/
│   ├── PRD_GALLERY_CURATOR.md          # Full technical specification
│   └── MVP_GALLERY_CURATOR.md          # Original MVP plan
└── LeapAudioDemo/
    ├── AudioDemoApp.swift               # App entry point
    ├── AudioDemoStore.swift             # Original audio demo logic
    ├── AudioPlaybackManager.swift       # Audio playback + completion callback
    ├── AudioRecorder.swift              # Microphone input
    ├── AppShell/
    │   └── Views/
    │       ├── MainTabView.swift        # Tab navigation
    │       └── IntroView.swift          # Intro splash screen
    ├── Gallery/
    │   ├── Data/
    │   │   ├── works.json               # Artwork metadata
    │   │   └── artist.json              # Artist profile
    │   ├── Models/
    │   │   ├── Artwork.swift            # Artwork data model
    │   │   └── Artist.swift             # Artist data model
    │   ├── Stores/
    │   │   ├── ExhibitStore.swift       # Loads exhibit data
    │   │   ├── CuratorRuntime.swift     # Singleton: model, audio session, inference queue
    │   │   ├── CuratorAudioStore.swift  # AI conversation controller
    │   │   └── CuratorContextBuilder.swift
    │   └── Views/
    │       ├── GalleryView.swift        # Artwork grid + Tour button
    │       ├── ArtworkDetailView.swift  # Full-screen artwork view
    │       └── CuratorChatView.swift    # Debug chat interface
    ├── Assets.xcassets/
    │   └── Artworks/                    # Artwork images
    └── Resources/
        └── *.gguf                       # Model files (add here)
```

## Usage

### Gallery Mode
1. Launch app → Select **Gallery** tab
2. Browse artworks in the grid
3. Tap any artwork for full-screen view
4. **Ask a question**: Type or tap mic button (push-to-talk)
5. **Info overlay**: Tap ⓘ button for artwork details

### Autoplay Tour
1. Tap **▶ Tour** button in Gallery toolbar
2. AI will narrate each artwork (2-3 sentences)
3. Auto-advances after 2 seconds
4. Tap pause to stop, play to resume
5. Tap X to exit tour

### Audio Demo Mode
1. Select **Audio Demo** tab
2. Tap record button to speak
3. AI responds with streaming audio

## Architecture

### Key Components

| Component | Purpose |
|-----------|---------|
| `CuratorRuntime` | Singleton managing model, audio session, serial inference queue |
| `CuratorAudioStore` | Thin controller for AI conversation using CuratorRuntime |
| `ExhibitStore` | Loads artwork/artist data from JSON |
| `CuratorContextBuilder` | Builds context prompts for AI |
| `AudioPlaybackManager` | Streaming audio with completion callback |
| `ArtworkDetailView` | Full-screen artwork with interaction |

### AI Configuration

**System Prompt** (required for audio output):
```swift
"Respond with interleaved text and audio."
```

**Context Injection** (per-turn):
```swift
let curatorInstructions = """
You are the exhibition curator. Use ONLY the provided Exhibit Context.
If the answer is not in the context, say you don't know.
"""
```

**Model Options**:
```swift
LiquidInferenceEngineOptions(
    contextSize: 4096,  // Reduced for memory
    nGpuLayers: 0
)
```

## Customization

### Adding Artworks
1. Add image to `Assets.xcassets/Artworks/` (e.g., `work-21.jpg`)
2. Add entry to `Gallery/Data/works.json`:
```json
{
  "id": "work-21",
  "title": "New Artwork",
  "summary": "Brief description for AI context",
  "imageName": "work-21.jpg"
}
```

### Changing Artist Profile
Edit `Gallery/Data/artist.json`:
```json
{
  "name": "Artist Name",
  "mission": "Used in AI context",
  "themes": ["theme1", "theme2"]
}
```

### Modifying AI Behavior
- Edit `CuratorContextBuilder.swift` for prompt changes
- Modify `speakAboutCurrentArtwork()` for tour narration style

## Known Limitations

- **Audio sync**: Response text may stream slightly ahead of audio playback.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Model loading fails | Ensure all 4 GGUF files in `Resources/` |
| No audio output | Check system prompt is exactly as specified |
| Images not showing | Verify `imageName` matches file in Assets |

```bash
# Reset project
make clean
make setup
```

## Documentation

- **[PRD_GALLERY_CURATOR.md](Docs/PRD_GALLERY_CURATOR.md)** — Complete technical specification for rebuilding the app
- **[MVP_GALLERY_CURATOR.md](Docs/MVP_GALLERY_CURATOR.md)** — Original MVP build plan

## License

See repository root for license information.

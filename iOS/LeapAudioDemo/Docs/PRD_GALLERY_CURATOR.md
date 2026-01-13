# Gallery Curator App — Product Requirements Document

> **Purpose**: This document provides complete technical specifications for an AI to rebuild the Gallery Curator application from scratch.

---

## 1. Overview

**Gallery Curator** is an offline iOS gallery/exhibition app built on top of **LeapAudioDemo**. It uses the **LFM2.5-Audio-1.5B Q8_0 GGUF** model for on-device AI inference, enabling visitors to:

- Browse up to ~20 artworks in a full-screen gallery
- Use **push-to-talk** to ask questions about artworks
- Receive **instant interleaved voice responses** from an AI curator
- Take an **autoplay tour** where the AI narrates each artwork sequentially
- Stay completely **offline** (no network, no cloud)

---

## 2. Technical Stack

### Platform Requirements
- **iOS 18.0+**
- **Xcode 15.0+**
- **SwiftUI** (declarative UI framework)
- **LeapSDK** (on-device AI inference)
- **XcodeGen** for project generation

### Model Requirements
- **LFM2.5-Audio-1.5B-Q8_0.gguf** (~1.2GB) - Main language model
- **mmproj-LFM2.5-Audio-1.5B-Q8_0.gguf** (~332MB) - Audio encoder projection
- **vocoder-LFM2.5-Audio-1.5B-Q8_0.gguf** (~280MB) - Audio decoder/waveform generator
- **tokenizer-LFM2.5-Audio-1.5B-Q8_0.gguf** (~77MB) - Audio tokenizer

### Key Configuration
```swift
LiquidInferenceEngineOptions(
    bundlePath: modelURL.path(),
    contextSize: 4096,  // Reduced for memory optimization
    nGpuLayers: 0,
    mmProjPath: mmProjPath,
    audioDecoderPath: vocoderPath,
    audioTokenizerPath: audioTokenizerPath
)
```

**Critical**: System prompt MUST be `"Respond with interleaved text and audio."` for proper audio output.

---

## 3. Architecture

### Directory Structure
```
LeapAudioDemo/
├── project.yml                          # XcodeGen configuration
├── Makefile                             # Build automation
├── README.md                            # Project documentation
├── Docs/
│   └── PRD_GALLERY_CURATOR.md          # This file
└── LeapAudioDemo/
    ├── AudioDemoApp.swift               # App entry point
    ├── AudioDemoStore.swift             # Original audio demo logic
    ├── AudioPlaybackManager.swift       # Audio playback with completion callback
    ├── AudioRecorder.swift              # Microphone input handling
    ├── AppShell/
    │   ├── Views/
    │   │   ├── MainTabView.swift        # Tab navigation (Audio Demo, Gallery)
    │   │   └── IntroView.swift          # Intro video splash screen
    │   └── Assets/
    │       └── intro-video.mp4          # Looping intro video
    ├── Gallery/
    │   ├── Data/
    │   │   ├── works.json               # Artwork metadata (up to 20 items)
    │   │   └── artist.json              # Artist profile
    │   ├── Models/
    │   │   ├── Artwork.swift            # Artwork data model
    │   │   └── Artist.swift             # Artist data model
    │   ├── Stores/
    │   │   ├── ExhibitStore.swift       # Loads exhibit data from JSON
    │   │   ├── CuratorAudioStore.swift  # AI conversation + audio management
    │   │   └── CuratorContextBuilder.swift # Builds context prompts
    │   └── Views/
    │       ├── GalleryView.swift        # Grid of artwork thumbnails + Tour button
    │       ├── ArtworkDetailView.swift  # Full-screen artwork with AI interaction
    │       └── CuratorChatView.swift    # Debug chat interface
    ├── Assets.xcassets/
    │   └── Artworks/                    # Artwork images (work-01.jpg, etc.)
    └── Resources/
        └── *.gguf                       # Model files
```

---

## 4. Data Models

### Artist (`artist.json`)
```json
{
  "name": "Artist Name",
  "mission": "Artist mission statement (used in context)",
  "bio": "Full biography",
  "themes": ["theme1", "theme2", "theme3"]
}
```

### Artwork (`works.json`)
```json
[
  {
    "id": "work-01",
    "title": "Artwork Title",
    "year": "2024",
    "medium": "Photograph",
    "summary": "Brief description for AI context",
    "story": "Extended story behind the work",
    "technique": "Technical details",
    "tags": ["tag1", "tag2"],
    "imageName": "work-01.jpg",
    "quote": "Optional artist quote about this work"
  }
]
```

### Swift Models

```swift
// Artist.swift
struct Artist: Codable {
    let name: String
    let mission: String
    let bio: String
    let themes: [String]
}

// Artwork.swift
struct Artwork: Codable, Identifiable {
    let id: String
    let title: String
    let year: String
    let medium: String
    let summary: String
    let story: String
    let technique: String
    let tags: [String]
    let imageName: String
    let quote: String?
    
    var displayTitle: String { title.isEmpty ? id : title }
    var hasMetadata: Bool { !title.isEmpty || !summary.isEmpty || !story.isEmpty }
}
```

---

## 5. Core Components

### 5.1 ExhibitStore
Loads and manages exhibit data from bundled JSON files.

```swift
@Observable
final class ExhibitStore {
    var artist: Artist?
    var artworks: [Artwork] = []
    var loadError: String?
    
    init() { loadData() }
    
    private func loadData() {
        // Load from Bundle.main: "works.json" and "artist.json"
    }
}
```

### 5.2 CuratorAudioStore
Manages AI conversation, audio recording, and playback.

**Key Properties:**
```swift
@MainActor
final class CuratorAudioStore {
    var inputText: String = ""
    var messages: [CuratorMessage] = []
    var status: String?
    var streamingText: String = ""
    var isModelLoading = false
    var isGenerating = false
    var isRecording = false
    var onAudioPlaybackComplete: (() -> Void)?  // For autoplay
    
    private let playbackManager = AudioPlaybackManager()
    private let recorder = AudioRecorder()
    private var conversation: Conversation?
    private var modelRunner: ModelRunner?
}
```

**Key Methods:**
- `setupModel()` - Loads the LFM2.5 model
- `setContext(artist:artwork:)` - Sets context for current artwork
- `sendTextPrompt()` / `sendTextPrompt(_ text:)` - Send text query
- `toggleRecording()` - Push-to-talk recording
- `speakAboutCurrentArtwork()` - Autoplay trigger
- `stopPlayback()` - Stop current generation/playback
- `clearHistory()` - Memory cleanup

### 5.3 CuratorContextBuilder
Builds context prompts for the AI.

```swift
struct CuratorContextBuilder {
    static let systemPrompt = "Respond with interleaved text and audio."
    
    static let curatorInstructions = """
    You are the exhibition curator. Use ONLY the provided Exhibit Context. \
    If the answer is not in the context, say you don't know. Do not invent details. Keep answers concise.
    """
    
    static func buildContextPacket(artist: Artist?, artwork: Artwork?) -> String
    static func buildGeneralContextPacket(artist: Artist?, artworks: [Artwork]) -> String
}
```

### 5.4 AudioPlaybackManager
Handles streaming audio playback with completion callback.

```swift
final class AudioPlaybackManager {
    private var pendingBuffers = 0
    private var isPlaybackActive = false
    var onPlaybackComplete: (() -> Void)?
    
    func enqueue(samples: [Float], sampleRate: Int)  // Stream audio buffers
    func reset()  // Stop and clear
    var isPlaying: Bool  // Current playback state
}
```

**Critical**: Uses `.dataPlayedBack` completion callback type with 0.3s delay check for accurate completion detection.

---

## 6. View Components

### 6.1 GalleryView
Grid display of artwork thumbnails with Tour button.

```swift
struct GalleryView: View {
    let exhibitStore: ExhibitStore
    @State private var selectedIndex: Int?
    @State private var startAutoplay = false
    
    // 2-column LazyVGrid of ArtworkThumbnail views
    // Toolbar with "Tour" button (play.fill icon)
    // fullScreenCover presentation of ArtworkDetailView
}
```

### 6.2 ArtworkDetailView
Full-screen artwork display with AI interaction.

**Parameters:**
```swift
init(artworks: [Artwork], initialIndex: Int, artist: Artist?, startAutoplay: Bool = false)
```

**Features:**
- Full-bleed artwork image
- Navigation arrows (left/right) + swipe gestures
- Title overlay at bottom
- Response text overlay (auto-scrolling, replaces quote)
- Info button → summary overlay
- Text input + microphone button for questions
- Autoplay controls (play/pause) when tour active

**Autoplay Logic:**
1. When `startAutoplay=true`, begins tour automatically
2. `speakAboutCurrentArtwork()` triggers AI narration
3. `onAudioPlaybackComplete` callback advances to next after 2s delay
4. Tour stops at last artwork

### 6.3 IndexWrapper
Helper for fullScreenCover binding.

```swift
struct IndexWrapper: Identifiable {
    let index: Int
    let autoplay: Bool
    var id: Int { index }
}
```

---

## 7. Autoplay Tour Feature

### Flow
1. User taps "Tour" button in GalleryView toolbar
2. Opens ArtworkDetailView at index 0 with `startAutoplay=true`
3. Model automatically speaks about artwork (2-3 sentences)
4. After audio completes → 2 second delay
5. Response overlay clears → advance to next artwork
6. Repeat until last artwork

### Implementation Details

```swift
// ArtworkDetailView autoplay state
@State private var isAutoplayActive = false
@State private var autoplayPaused = false

// Setup callback
private func setupAutoplayCallback() {
    store.onAudioPlaybackComplete = { [self] in
        guard isAutoplayActive && !autoplayPaused else { return }
        advanceToNextArtwork()
    }
}

// Advance logic
private func advanceToNextArtwork() {
    if currentIndex < artworks.count - 1 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Clear overlay, animate to next, trigger speech
        }
    } else {
        isAutoplayActive = false
    }
}
```

---

## 8. Memory Management

### Optimizations
- **Context size**: 4096 tokens (reduced from 8192)
- **History trimming**: Keep only last 2 messages when count > 6
- **Autoplay cleanup**: Clear history after 4+ messages
- **No audio storage**: Don't store audio blobs in message history

```swift
private func trimHistoryIfNeeded() {
    if messages.count > 6 {
        messages = Array(messages.suffix(2))
    }
}

private func clearHistoryForAutoplay() {
    if messages.count > 4 {
        messages.removeAll()
        conversation = nil
    }
}
```

### Known Limitation
Switching between Tour autoplay and push-to-talk may cause performance degradation due to model resource accumulation. Recommend completing one mode before using the other.

---

## 9. UI/UX Guidelines

### Design Principles
- **Full-bleed imagery** - Images fill the screen
- **Minimal UI** - Translucent overlays (50-70% opacity)
- **Human content first** - AI is opt-in, not intrusive
- **Fast load** - Target < 2 seconds

### Translucency Values
- Navigation arrows: 65% white background
- Title overlay: 70% black background
- Response overlay: 50% black background
- Info button: 65% white background

### Response Overlay
- Auto-scrolling text (ScrollViewReader)
- Max height: 80pt
- Small X button to dismiss
- Shows "Thinking..." or "Speaking..." status

---

## 10. Build & Run

### Setup
```bash
# Install dependencies
brew install xcodegen
pip install leap-bundle

# Download model
leap-bundle download LFM2.5-Audio-1.5B --quantization=Q8_0

# Copy model files
cp LiquidAI_LeapBundles_LFM2_5_Audio_1_5B_GGUF_Q8_0/*.gguf LeapAudioDemo/Resources/

# Generate project
make setup

# Open Xcode
make open
```

### Xcode Build
- Select iOS 18.0+ device
- Press Cmd+R to build and run
- Grant microphone permission when prompted

---

## 11. Extending the App

### Adding Artworks
1. Add image to `Assets.xcassets/Artworks/`
2. Add entry to `works.json` with matching `imageName`
3. Rebuild

### Customizing AI Behavior
- Modify `curatorInstructions` in `CuratorContextBuilder.swift`
- Adjust `buildContextPacket()` for different context structure
- Change prompt in `speakAboutCurrentArtwork()` for different tour style

### Adding New Tabs
1. Add view to `AppShell/Views/`
2. Update `MainTabView.swift` with new tab item

---

## 12. Troubleshooting

| Issue | Solution |
|-------|----------|
| Model loading fails | Ensure all 4 GGUF files in Resources/ |
| No audio output | Check system prompt is exactly `"Respond with interleaved text and audio."` |
| Memory pressure | Restart app between Tour and push-to-talk modes |
| Laggy responses | Clear history, reduce context size |
| Images not loading | Check imageName matches filename in Assets |

---

## 13. Version History

| Date | Version | Changes |
|------|---------|---------|
| Jan 12, 2026 | 1.0 | Initial Gallery Curator with autoplay tour |


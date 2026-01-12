# LeapAudioDemo

A SwiftUI app demonstrating audio input and output with the LeapSDK for on-device AI inference using the LFM2.5 Audio model.

## Features

- Real-time audio recording and playback
- Audio processing with LFM2.5 Audio model
- Demonstrates LeapSDK integration with audio handling
- Streaming audio response playback
- Local on-device AI inference
- Microphone permission handling

## Requirements

- iOS 18.0+
- Xcode 15.0+
- XcodeGen: `brew install xcodegen`
- Python 3.8+ (for downloading models)

## Getting Started

### 1. Download the LFM2.5 Audio Model

Install the leap-bundle tool and download the model files:
```bash
pip install leap-bundle
leap-bundle download LFM2.5-Audio-1.5B --quantization=Q8_0
```

This downloads 4 required GGUF files:
- `LFM2.5-Audio-1.5B-Q8_0.gguf` (main language model, ~1.2GB)
- `mmproj-LFM2.5-Audio-1.5B-Q8_0.gguf` (audio encoder projection, ~332MB)
- `vocoder-LFM2.5-Audio-1.5B-Q8_0.gguf` (audio decoder/waveform generator, ~280MB)
- `tokenizer-LFM2.5-Audio-1.5B-Q8_0.gguf` (audio tokenizer, ~77MB)

### 2. Copy Model Files to Resources

Copy all `.gguf` files to `LeapAudioDemo/Resources/`:
```bash
cp LiquidAI_LeapBundles_LFM2_5_Audio_1_5B_GGUF_Q8_0/*.gguf LeapAudioDemo/Resources/
```

### 3. Setup the Project
```bash
make setup
```

### 4. Open in Xcode
```bash
make open
```

### 5. Build and Run
- Select an iOS 18.0+ device (simulator or physical)
- Press Cmd+R to build and run
- Grant microphone permission when prompted

## Usage

1. Launch the app
2. Allow microphone access when prompted
3. Tap the record button to start audio capture
4. Speak into the microphone
5. Tap stop to end recording
6. The app will process the audio and display results
7. Tap play to hear the audio response

## Project Structure

```
LeapAudioDemo/
├── project.yml                      # XcodeGen configuration
├── Makefile                        # Build automation
├── README.md                       # This file
└── LeapAudioDemo/                  # Source code
    ├── AudioDemoApp.swift              # App entry point
    ├── Views/
    │   └── AudioDemoView.swift        # Main UI
    ├── AudioRecorder.swift            # Audio recording
    ├── AudioPlaybackManager.swift     # Audio playback
    ├── AudioDemoStore.swift           # Business logic
    ├── Assets.xcassets               # App assets
    └── Resources/                    # Model bundles (add GGUF files here)
        ├── LFM2.5-Audio-1.5B-Q8_0.gguf
        ├── mmproj-LFM2.5-Audio-1.5B-Q8_0.gguf
        ├── vocoder-LFM2.5-Audio-1.5B-Q8_0.gguf
        └── tokenizer-LFM2.5-Audio-1.5B-Q8_0.gguf
```

## Code Overview

### Key Components

**AudioDemoStore**: Manages LeapSDK interaction and audio processing
```swift
@MainActor
class AudioDemoStore: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    
    func processAudio(_ url: URL) async {
        // LeapSDK audio integration
    }
}
```

**AudioRecorder**: Handles microphone input
```swift
@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    
    func startRecording() { }
    func stopRecording() { }
}
```

**AudioPlaybackManager**: Handles audio output
```swift
@MainActor
class AudioPlaybackManager: NSObject, ObservableObject {
    func play(url: URL) async { }
}
```

**AudioDemoView**: SwiftUI interface
```swift
struct AudioDemoView: View {
    @StateObject private var store = AudioDemoStore()
    // UI implementation
}
```

## How it Works

The app uses the LeapSDK to:

1. Load a local audio AI model
2. Capture audio from the device microphone
3. Process audio through the model
4. Generate audio output or text responses
5. Playback results to the user

## Customization

### Adding New Features
- Modify `AudioDemoStore.swift` for business logic changes
- Update `Views/AudioDemoView.swift` for UI modifications
- Enhance `AudioRecorder.swift` for additional audio capture features
- Extend `AudioPlaybackManager.swift` for advanced playback options

### Model Configuration
The model is configured in `AudioDemoStore.swift` with companion file paths:
```swift
var options = LiquidInferenceEngineOptions(
    bundlePath: modelURL.path(),
    contextSize: 8192,
    nGpuLayers: 0,
    mmProjPath: mmProjPath,
    audioDecoderPath: vocoderPath,
    audioTokenizerPath: audioTokenizerPath
)
let runner = try Leap.load(options: options)
```

**Note**: The LFM2.5 audio engine requires a fresh conversation for each turn (audio history is not replayable). The app handles this automatically.

## Permissions

The app requires the following permissions:
- **Microphone**: Required for audio input
- **Background Modes**: Audio processing can continue in the background

These are configured in `project.yml`:
```yaml
INFOPLIST_KEY_NSMicrophoneUsageDescription: "Audio input is used to capture prompts."
INFOPLIST_KEY_UIBackgroundModes: "audio"
```

## Troubleshooting

### Build Issues
```bash
make clean
make setup
```

### XcodeGen not found
```bash
brew install xcodegen
```

### Model Loading Errors
Ensure the model file exists in `LeapAudioDemo/Resources/`

### Permission Denied
Ensure microphone permissions are granted in Settings > Privacy > Microphone

## Next Steps

- Try the [LeapChatExample](../LeapChatExample/) for text-based interaction
- Explore the [LeapSloganExample](../LeapSloganExample/) for simpler integration
- Review the [LeapSDK documentation](https://leap.liquid.ai/docs/ios-quick-start-guide)
- Experiment with different audio models

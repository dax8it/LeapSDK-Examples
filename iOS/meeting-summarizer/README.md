# MeetingSummary iOS App

**Important:** Open `MeetingSummary.xcodeproj` (not the folder).

A fully on-device meeting summarization app using Liquid LEAP Edge SDK and LFM2-2.6B-Transcript model.

## Requirements

- iOS 15.0+
- Xcode 15+
- Swift 5.9+

## Setup Instructions

### 1. Open the Project
```bash
open MeetingSummary.xcodeproj
```

### 2. Add LeapSDK Dependency
In Xcode:
1. Select the "MeetingSummary" project in the navigator
2. Go to "Package Dependencies" tab
3. Click "+" to add package dependency
4. Enter URL: `https://github.com/Liquid4All/leap-ios.git`
5. Select version 0.7.0 or later
6. Click "Add Package"

### 3. Configure Model
The app is configured to use:
- **Model**: LFM2-2.6B-Transcript
- **Quantization**: Q4_K_M (1.56GB)
- **System Prompt**: "You are an expert meeting analyst. Analyze the transcript carefully and provide clear, accurate information based on the content."
- **Temperature**: 0.3

### 4. Build and Run
1. Select your target device (iPhone/iPad)
2. Build and run the app (`Cmd+R`)

## Features

- **Offline Operation**: Runs entirely on-device after initial model download
- **Multiple Summary Types**: Executive, Detailed, Action Items, Key Decisions, Participants, Topics
- **Streaming Output**: Real-time summary generation
- **Progress Tracking**: Model download progress with speed indicator
- **Copy & Share**: Easy sharing of generated summaries
- **Format Helper**: Template transcript insertion
- **Error Handling**: Clear error messages and toasts

## Architecture

### Models
- `SummaryType`: Enum defining available summary types with their respective prompts

### Services
- `ModelManager`: Handles model loading/unloading and download progress
- `SummarizerService`: Manages single-turn conversation generation
- `PromptBuilder`: Constructs prompts from user input and summary type

### ViewModels
- `MeetingSummaryViewModel`: Main view model coordinating all services

### Views
- `ContentView`: Main UI with transcript editor, summary picker, and output
- `MeetingSummaryApp`: App entry point

## Usage

1. **Download Model**: Tap "Download Model" button to download the LFM2-2.6B-Transcript model
2. **Enter Transcript**: Paste or type meeting transcript, or use "Format Helper" for template
3. **Select Summary Type**: Choose from available summary types
4. **Generate**: Tap "Generate Summary" to create summary
5. **Share**: Use Copy or Share buttons to share the summary

## File Structure

```
MeetingSummary/
├── MeetingSummaryApp.swift          # App entry point
├── ContentView.swift                # Main UI
├── Models/
│   └── SummaryType.swift            # Summary type enum
├── Services/
│   ├── ModelManager.swift           # Model loading/unloading
│   ├── SummarizerService.swift      # Generation service
│   └── PromptBuilder.swift          # Prompt construction
├── ViewModels/
│   └── MeetingSummaryViewModel.swift # Main view model
└── Preview Content/
    └── Assets.xcassets/              # App icons and colors
```

## Technical Details

- **Model Storage**: Caches model locally after download
- **Memory Usage**: Under 3GB RAM during operation
- **Single-turn**: No conversation history maintained
- **Streaming**: Real-time text generation display
- **Error Handling**: Comprehensive error management

## Troubleshooting

- **Model Download Fails**: Check internet connection and available storage (needs ~2GB)
- **Generation Fails**: Ensure model is fully loaded and transcript isn't empty
- **Performance**: Device with Neural Engine recommended for optimal performance
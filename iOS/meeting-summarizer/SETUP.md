# MeetingSummary iOS App - Setup Instructions

## Quick Start (Follow These Steps Exactly)

### 1. Create New Xcode Project
1. Open Xcode → File → New → Project…
2. Choose **iOS → App** (SwiftUI, Swift)
3. **Product Name**: MeetingSummary
4. **Save in**: meeting-summarizer (same folder as this README)
5. This will create `MeetingSummary.xcodeproj`

### 2. Add LeapSDK Dependency
1. In Xcode, select the **MeetingSummary** project in navigator
2. Go to **Package Dependencies** tab
3. Click **+** to add package dependency
4. Enter URL: `https://github.com/Liquid4All/leap-ios.git`
5. Select version: **0.9.1** or "Up to Next Major" from 0.9.1
6. Click **Add Package**

### 3. Add Files to Project
Drag these files into the new Xcode project (ensure "MeetingSummary" target is checked):

**Root Level Files:**
- `MeetingSummaryFinal/MeetingSummaryApp.swift`
- `MeetingSummaryFinal/ContentView.swift`

**Models Folder:**
- `MeetingSummaryFinal/Models/SummaryType.swift`

**Services Folder:**
- `MeetingSummaryFinal/Services/ModelManager.swift`
- `MeetingSummaryFinal/Services/SummarizerService.swift`
- `MeetingSummaryFinal/Services/PromptBuilder.swift`

**ViewModels Folder:**
- `MeetingSummaryFinal/ViewModels/MeetingSummaryViewModel.swift`

### 4. Build and Run
1. Select your target device (iPhone/iPad)
2. Build (**Cmd+B**) and run (**Cmd+R**)

## App Configuration

The app is pre-configured with:

- **Model**: LFM2-2.6B-Transcript
- **Quantization**: Q4_K_M (1.56GB)
- **System Prompt**: "You are an expert meeting analyst. Analyze the transcript carefully and provide clear, accurate information based on the content."
- **Temperature**: 0.3
- **iOS Target**: 15.0+
- **Deployment**: Fully on-device after model download

## Features

✅ **Offline Operation**: Runs entirely on-device after initial model download  
✅ **6 Summary Types**: Executive, Detailed, Action Items, Key Decisions, Participants, Topics  
✅ **Streaming Output**: Real-time summary generation display  
✅ **Progress Tracking**: Model download progress with speed indicator  
✅ **Error Handling**: Comprehensive error messages and toasts  
✅ **Format Helper**: Template transcript insertion  
✅ **Copy & Share**: Full sharing functionality  
✅ **Character Counter**: Real-time transcript character count  
✅ **Cancel Generation**: Stop generation mid-process  

## Usage

1. **Download Model**: Tap "Download Model" button
2. **Enter Transcript**: Paste or type meeting transcript, use "Format Helper" for template
3. **Select Summary Type**: Choose from 6 available types
4. **Generate**: Tap "Generate Summary" 
5. **Share**: Use Copy or Share buttons

## Architecture

**Models:**
- `SummaryType`: Enum with 6 summary types and prompts

**Services:**
- `ModelManager`: LeapSDK model loading with progress tracking
- `SummarizerService`: Single-turn generation with streaming
- `PromptBuilder`: Constructs prompts and provides templates

**ViewModels:**
- `MeetingSummaryViewModel`: Main coordinator with @MainActor

**Views:**
- `ContentView`: SwiftUI interface with all UI components
- `MeetingSummaryApp`: App entry point

## Troubleshooting

- **Model Download Fails**: Check internet connection and storage (needs ~2GB)
- **Generation Fails**: Ensure model is loaded and transcript isn't empty
- **Build Errors**: Verify LeapSDK package is properly added and all files are included in target
- **Performance**: Device with Neural Engine recommended for optimal performance

All core functionality is implemented with no placeholder code. The app will work offline after the initial model download.
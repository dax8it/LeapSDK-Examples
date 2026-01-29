---
name: ios-swift-expert
description: Elite iOS and macOS development expertise for Swift, SwiftUI, UIKit, Xcode, and the entire Apple development ecosystem. Automatically activates when working with .swift files, Xcode projects (.xcodeproj, .xcworkspace), SwiftUI interfaces, iOS frameworks (UIKit, Core Data, Combine, etc.), app architecture, or Apple platform development.
---
# iOS Swift Expert

## Overview
Use for Swift/SwiftUI architecture, AVFoundation, and performance correctness.

## Agent Behavior Contract
1. Keep CuratorRuntime as single owner of model/audio/inference queue.
2. Enforce main-thread UI updates and safe concurrency.
3. Avoid overlapping inferences; cancel cleanly on navigation.
4. Respect required system prompt string exactly once.

## Project Notes
- Audio pipeline: mic 48k → 16k resample, stream text+audio.
- Playback uses chunking/jitter buffering; avoid stutters.

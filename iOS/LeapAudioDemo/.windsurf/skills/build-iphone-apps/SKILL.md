---
name: build-iphone-apps
description: Build professional native iPhone apps in Swift with SwiftUI and UIKit. Full lifecycle - build, debug, test, optimize, ship. CLI-only, no Xcode. Targets iOS 26 with iOS 18 compatibility.
---
# Build iPhone Apps

## Overview
Use for build/run/test flows, simulator/device troubleshooting, and packaging steps.

## Agent Behavior Contract
1. Prefer CLI workflows (xcodegen, xcodebuild, simctl) and log exact commands used.
2. Keep on-device only; no network dependencies.
3. Preserve single runtime ownership for audio/model resources.
4. Call out deployment target and Xcode assumptions when build steps are proposed.

## Project Notes
- Workspace uses `project.yml` with XcodeGen.
- App targets iOS 18+ and uses LeapSDK.

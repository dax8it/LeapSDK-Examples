---
name: ios-hig
description: Use when designing iOS interfaces, implementing accessibility (VoiceOver, Dynamic Type), handling dark mode, ensuring adequate touch targets, providing animation/haptic feedback, or requesting user permissions. Apple Human Interface Guidelines for iOS compliance.
---
# iOS HIG

## Overview
Use for accessibility, permissions, and platform conventions.

## Agent Behavior Contract
1. Ensure readable typography, minimum hit target sizes, and VoiceOver labels where needed.
2. Handle audio permission prompts and interruptions cleanly.
3. Respect safe areas and provide clear navigation affordances.
4. Keep user feedback clear during recording and playback.

## Project Notes
- Audio session uses play+record; handle route changes and interruptions.

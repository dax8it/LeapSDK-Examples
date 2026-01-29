# LFM2.5-Audio Model - Best Practices

This document captures audio optimization settings and implementation patterns for smooth real-time audio on iPhone with the LeapSDK LFM2.5-Audio model.

---

## 1. Model Options Configuration

### Recommended "Ship" Config

```swift
let options = LiquidInferenceEngineOptions(
    bundlePath: modelURL.path(),
    cpuThreads: 4,              // ⭐️ Steady throughput without stealing from audio engine
    contextSize: 2048,          // ⭐️ Reduced for lower latency (not 4096)
    nGpuLayers: 0,
    mmProjPath: mmProjPath,
    audioDecoderPath: vocoderPath,
    audioDecoderUseGpu: true,   // ⭐️ Offload vocoder to GPU for smoother audio
    audioTokenizerPath: audioTokenizerPath
)
```

### Parameter Details

| Parameter | Recommended | Notes |
|-----------|-------------|-------|
| `cpuThreads` | 4 | Start here. Try 5 if underrunning. Avoid 6+ (may cause jank). |
| `contextSize` | 2048 | 4096 is expensive, causes latency spikes. For short turns, even 1024 works. |
| `audioDecoderUseGpu` | true | Offloads vocoder step. If crashes occur, flip back to false. |
| `nGpuLayers` | 0 | Keep at 0 for stability on iPhone. |

---

## 2. Audio Playback Buffering

### Fixed-Size Re-Chunking

Don't enqueue raw incoming chunks—re-chunk to fixed-duration frames:

```swift
// AudioPlaybackManager settings
private let frameDurationMs: Double = 30        // 30ms frames
private var frameSize: Int { Int(Double(currentSampleRate) * frameDurationMs / 1000.0) }
```

### Jitter Buffer + Hysteresis

```swift
// Wait for minimum audio before starting playback
private let jitterBufferMs: Double = 250        // 250ms jitter buffer

// Hysteresis: refill mode to prevent stutter oscillation
private let refillThresholdMs: Double = 120     // Enter refill mode if buffer dips below this

// Max queue cap to prevent runaway latency (backpressure)
private let maxQueueMs: Double = 1500           // 1.5 seconds max
```

### Frame Math

- 30ms @ 24,000 Hz = 720 samples
- 30ms @ 48,000 Hz = 1440 samples
- Always compute `frameSize` from actual `sampleRate`

### Playback Logic

1. **Start playback** when queued ≥ 250ms
2. **Refill mode** if buffer dips below 120ms (pause scheduling briefly)
3. **Backpressure** if buffer exceeds 1.5s

---

## 3. Mic Audio Resampling

### Critical: Model expects 16kHz

The audio encoder expects **16,000 Hz**. iPhone mic captures at **48,000 Hz**.

```swift
enum AudioResampler {
    static let modelSampleRate: Int = 16000
    
    static func resampleTo16kHz(samples: [Float], sourceSampleRate: Int) -> [Float]? {
        // 1. Convert to mono
        // 2. Convert to Float32
        // 3. Resample 48k → 16k (linear interpolation)
        // 4. Normalize to [-1, 1] and remove DC offset
    }
}
```

**Acceptance test:** A 2.1s clip should be ~33,600 samples after resampling (not 100,800).

---

## 4. Threading / QoS

| Task | Queue | QoS |
|------|-------|-----|
| Audio scheduling | Dedicated queue | `.userInteractive` |
| Inference | Background queue | `.userInitiated` |
| Aggregation/resampling | Background queue | `.userInitiated` |

**Rule:** Keep audio callback thread untouched. Never block main thread.

---

## 5. Identity Guardrail

In all system prompts, include:

```
Never say "I am Alex Covo" or "I'm Alex Covo." If asked who you are, say you are his curator.
```

This prevents the model from claiming to be the artist when audio decoding fails.

---

## 6. Safety Caps (Backpressure)

Prevent runaway audio or GGML crashes:

```swift
private let maxOutputTokens: Int = 200          // Limit response length
private let maxPendingAudioMs: Double = 2000    // Soft stop if buffered audio > 2s
private let maxEmittedAudioMs: Double = 6000    // Hard cap: max 6s per response
```

---

## 7. Troubleshooting

### "Robotic stutter"
→ Add fixed-size re-chunking + jitter buffer

### "Wrong answers" / generic greetings
→ Check mic resampling (must be 16kHz, not 48kHz)

### "Smooth at first then degrades"
→ Thermal throttling. Try:
- `cpuThreads = 5`
- Larger jitter buffer (300–400ms)
- Drop to Q6_K/Q5_K_M quantization

### Periodic latency spikes
→ Reduce `contextSize` to 2048 or 1024

---

## 8. Current Implementation Status

| Feature | Status | File |
|---------|--------|------|
| `cpuThreads = 4` | ✅ | `CuratorRuntime.swift` |
| `contextSize = 2048` | ✅ | `CuratorRuntime.swift` |
| `audioDecoderUseGpu = true` | ✅ | `CuratorRuntime.swift` |
| 30ms frame re-chunking | ✅ | `AudioPlaybackManager.swift` |
| 250ms jitter buffer | ✅ | `AudioPlaybackManager.swift` |
| 120ms refill hysteresis | ✅ | `AudioPlaybackManager.swift` |
| 1500ms max queue cap | ✅ | `AudioPlaybackManager.swift` |
| 48kHz → 16kHz resampling | ✅ | `ConversationLoop.swift` (AudioResampler) |
| Identity guardrail | ✅ | All `*ContextBuilder.swift` files |
| Safety caps | ✅ | `CuratorRuntime.swift` |

---

*Last updated: January 2026*

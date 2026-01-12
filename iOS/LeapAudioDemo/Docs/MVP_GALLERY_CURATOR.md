# Gallery Curator App — MVP Build Plan (Windsurf Reference)

## Purpose
Convert **LeapAudioDemo** (offline, on-device **LFM2.5-Audio-1.5B Q8_0 GGUF** interleaved speech+text) into an **offline gallery/exhibition app** that:
- Lets visitors browse up to ~20 artworks.
- Uses **push-to-talk** to ask questions.
- Responds with **instant interleaved voice** as a curator/artist agent.
- Stays grounded in local exhibit data (no network, no cloud).

## Non-negotiables
- **Do not break the current audio demo.**
- **Do not modify existing audio codepaths**:
  - `AudioDemoStore.swift`
  - `AudioDemoView.swift`
  - `AudioRecorder.swift`
  - `AudioPlaybackManager.swift`
- Build MVP by **adding new files** + **minimal app-shell wiring**.
- Keep everything **offline**.

---

## Git safety workflow (5 commands)
Run from repo root:

```bash
git status
git add -A
git commit -m "Snapshot: working LeapAudioDemo audio-to-audio baseline"
git switch -c gallery-mvp
git log --oneline -5
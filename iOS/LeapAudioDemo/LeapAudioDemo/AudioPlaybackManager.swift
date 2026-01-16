import AVFoundation
import Foundation

final class AudioPlaybackManager {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  
  // High-priority queue for audio scheduling (userInteractive QoS)
  private let queue = DispatchQueue(label: "ai.leap.audio.playback", qos: .userInteractive)
  
  private var format: AVAudioFormat?
  private var sessionConfigured = false
  private var scheduledFrameCount = 0  // Counter-based playback tracking (incremented on schedule, decremented on completion)
  private var totalBuffersEnqueued = 0
  private var generationComplete = false
  
  // Frame-based buffering: aggregate samples into fixed-duration frames
  private var sampleBuffer: [Float] = []
  private var currentSampleRate: Int = 24000
  private let frameDurationMs: Double = 30  // 30ms frames
  private var frameSize: Int { Int(Double(currentSampleRate) * frameDurationMs / 1000.0) }
  
  // Jitter buffer: wait for minimum audio before starting playback
  private let jitterBufferMs: Double = 250  // 250ms jitter buffer
  private var jitterBufferSamples: Int { Int(Double(currentSampleRate) * jitterBufferMs / 1000.0) }
  private var hasStartedPlayback = false
  
  // Hysteresis: refill mode to prevent stutter oscillation
  private let refillThresholdMs: Double = 120  // Enter refill mode if buffer dips below this
  private var refillThresholdSamples: Int { Int(Double(currentSampleRate) * refillThresholdMs / 1000.0) }
  private var isInRefillMode = false
  
  // Max queue cap to prevent runaway latency (backpressure)
  private let maxQueueMs: Double = 1500  // 1.5 seconds max
  private var maxQueueSamples: Int { Int(Double(currentSampleRate) * maxQueueMs / 1000.0) }
  
  // Diagnostic logging
  private var logTimer: DispatchSourceTimer?
  private var lastLogTime: Date = Date()
  
  // Playback stuck detection
  private var playbackStartTime: Date?
  private var lastProgressTime: Date?
  private let playbackStuckTimeoutSeconds: Double = 10.0  // Auto-reset if stuck for 10s
  
  var onPlaybackComplete: (() -> Void)?
  
  // MUTE STATE: When muted, drop all incoming samples and stop playback
  private var _isMuted = false
  var isMuted: Bool {
    get { queue.sync { _isMuted } }
    set { setMuted(newValue) }
  }

  init() {
    print("[AudioPlaybackManager] 🔊 Initializing (frame-based buffering with hysteresis)")
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: nil)
  }
  
  /// Start diagnostic logging (call when playback begins)
  private func startDiagnosticLogging() {
    guard logTimer == nil else { return }
    
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(250))
    timer.setEventHandler { [weak self] in
      self?.logBufferDepth()
    }
    timer.resume()
    logTimer = timer
  }
  
  /// Stop diagnostic logging
  private func stopDiagnosticLogging() {
    logTimer?.cancel()
    logTimer = nil
  }
  
  /// Log current buffer depth for diagnostics
  private func logBufferDepth() {
    let bufferedMs = Double(sampleBuffer.count) / Double(currentSampleRate) * 1000.0
    let pendingMs = Double(scheduledFrameCount * frameSize) / Double(currentSampleRate) * 1000.0
    let totalMs = bufferedMs + pendingMs
    let status = isInRefillMode ? "REFILL" : "OK"
    
    // Check for stuck playback (only log occasionally to reduce noise)
    if totalMs > 0, let lastProgress = lastProgressTime {
      let stuckDuration = Date().timeIntervalSince(lastProgress)
      if stuckDuration > playbackStuckTimeoutSeconds {
        print("[AudioPlaybackManager] ⚠️ STUCK DETECTED: no progress for \(Int(stuckDuration))s, forcing reset")
        forceResetDueToStuck()
        return
      }
    }
    
    // Only log if buffer state changed significantly or every 2 seconds
    let now = Date()
    if now.timeIntervalSince(lastLogTime) >= 2.0 {
      print("[AudioPlaybackManager] 📊 Buffer: \(Int(bufferedMs))ms queued + \(Int(pendingMs))ms pending = \(Int(totalMs))ms total [\(status)]")
      lastLogTime = now
    }
  }
  
  /// Force reset due to stuck playback
  private func forceResetDueToStuck() {
    print("[AudioPlaybackManager] 🔄 Forcing reset due to stuck playback")
    
    // Clear all state
    sampleBuffer.removeAll()
    scheduledFrameCount = 0
    hasStartedPlayback = false
    isInRefillMode = false
    generationComplete = false
    playbackStartTime = nil
    lastProgressTime = nil
    
    // Stop player
    player.stop()
    
    // Notify completion (so the turn loop can continue)
    DispatchQueue.main.async { [weak self] in
      self?.onPlaybackComplete?()
    }
    
    stopDiagnosticLogging()
  }
  
  /// Counter-based playback active check (more reliable than playerNode.isPlaying)
  var isPlaying: Bool {
    queue.sync {
      return scheduledFrameCount > 0 || !sampleBuffer.isEmpty
    }
  }
  
  /// Reliable playback active state based on scheduled frame counter
  var playbackActive: Bool {
    queue.sync {
      return scheduledFrameCount > 0
    }
  }
  
  /// Total pending audio duration in milliseconds (for output length limiting)
  var pendingDurationMs: Double {
    queue.sync {
      let bufferedMs = Double(sampleBuffer.count) / Double(currentSampleRate) * 1000.0
      let pendingMs = Double(scheduledFrameCount * frameSize) / Double(currentSampleRate) * 1000.0
      return bufferedMs + pendingMs
    }
  }
  
  /// Check if playback is completely idle (no scheduled frames, no queued samples)
  var isIdle: Bool {
    queue.sync {
      return sampleBuffer.isEmpty && scheduledFrameCount == 0
    }
  }

  func prepareSession() {
    queue.async {
      self.configureSessionIfNeeded()
    }
  }

  func enqueue(samples: [Float], sampleRate: Int) {
    guard !samples.isEmpty else { return }
    
    queue.async { [weak self] in
      guard let self else { return }
      
      // MUTE: Drop samples immediately when muted
      guard !self._isMuted else { return }
      
      self.configureSessionIfNeeded(sampleRate: Double(sampleRate))
      self.currentSampleRate = sampleRate
      
      // Append incoming samples to ring buffer
      self.sampleBuffer.append(contentsOf: samples)
      
      // Backpressure: cap queue at max to prevent runaway latency
      if self.sampleBuffer.count > self.maxQueueSamples {
        let excess = self.sampleBuffer.count - self.maxQueueSamples
        self.sampleBuffer.removeFirst(excess)
        print("[AudioPlaybackManager] ⚠️ Backpressure: dropped \(excess) oldest samples (queue capped at \(self.maxQueueMs)ms)")
      }
      
      // Check if we have enough for jitter buffer (first time only)
      if !self.hasStartedPlayback {
        if self.sampleBuffer.count >= self.jitterBufferSamples {
          print("[AudioPlaybackManager] 🔊 === PLAYBACK START === (jitter buffer filled: \(self.sampleBuffer.count) samples)")
          self.hasStartedPlayback = true
          self.isInRefillMode = false
          self.playbackStartTime = Date()  // Track start time for stuck detection
          self.lastProgressTime = Date()   // Initialize progress time
          self.startDiagnosticLogging()
          self.drainBufferToFrames()
        }
      } else if self.isInRefillMode {
        // In refill mode: wait until we reach jitter buffer threshold again
        if self.sampleBuffer.count >= self.jitterBufferSamples {
          print("[AudioPlaybackManager] 🔄 Exiting refill mode (buffer restored to \(self.sampleBuffer.count) samples)")
          self.isInRefillMode = false
          self.drainBufferToFrames()
        }
      } else {
        // Normal mode: drain available frames
        self.drainBufferToFrames()
        
        // Check if we need to enter refill mode (hysteresis)
        if self.sampleBuffer.count < self.refillThresholdSamples && self.sampleBuffer.count > 0 {
          print("[AudioPlaybackManager] 🔄 Entering refill mode (buffer low: \(self.sampleBuffer.count) samples)")
          self.isInRefillMode = true
        }
      }
    }
  }
  
  /// Drain sample buffer into fixed-size frames and schedule them
  private func drainBufferToFrames() {
    guard let audioFormat = ensureFormat(sampleRate: Double(currentSampleRate)) else { return }
    
    // Process all complete frames in the buffer
    while sampleBuffer.count >= frameSize {
      // Extract exactly frameSize samples
      let frameSamples = Array(sampleBuffer.prefix(frameSize))
      sampleBuffer.removeFirst(frameSize)
      
      // Create and schedule the buffer
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: AVAudioFrameCount(frameSize)
      ) else { continue }
      
      buffer.frameLength = AVAudioFrameCount(frameSize)
      if let channelData = buffer.floatChannelData {
        frameSamples.withUnsafeBufferPointer { pointer in
          channelData[0].update(from: pointer.baseAddress!, count: pointer.count)
        }
      }
      
      scheduledFrameCount += 1
      totalBuffersEnqueued += 1
      
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        self?.queue.async {
          self?.scheduledFrameCount -= 1
          self?.lastProgressTime = Date()  // Track progress for stuck detection
          self?.checkPlaybackComplete()
        }
      }
    }
    
    // Start playback if not already playing
    if !player.isPlaying && hasStartedPlayback {
      player.play()
    }
  }
  
  private func checkPlaybackComplete() {
    // Only fire complete if generation is done AND scheduledFrameCount == 0 AND buffer is drained
    if scheduledFrameCount == 0 && generationComplete && sampleBuffer.count < frameSize {
      print("[AudioPlaybackManager] 🔊 === PLAYBACK COMPLETE === (total frames: \(totalBuffersEnqueued))")
      stopDiagnosticLogging()
      totalBuffersEnqueued = 0
      generationComplete = false
      hasStartedPlayback = false
      isInRefillMode = false
      sampleBuffer.removeAll()
      DispatchQueue.main.async { [weak self] in
        self?.onPlaybackComplete?()
      }
    }
  }
  
  /// Signal that generation is complete - flush remaining samples and fire completion when done
  func markGenerationComplete() {
    queue.async { [weak self] in
      guard let self else { return }
      self.generationComplete = true
      
      // Flush any remaining samples as a final partial frame
      if !self.sampleBuffer.isEmpty, let audioFormat = self.ensureFormat(sampleRate: Double(self.currentSampleRate)) {
        let remainingSamples = self.sampleBuffer
        self.sampleBuffer.removeAll()
        
        guard let buffer = AVAudioPCMBuffer(
          pcmFormat: audioFormat,
          frameCapacity: AVAudioFrameCount(remainingSamples.count)
        ) else {
          self.checkPlaybackComplete()
          return
        }
        
        buffer.frameLength = AVAudioFrameCount(remainingSamples.count)
        if let channelData = buffer.floatChannelData {
          remainingSamples.withUnsafeBufferPointer { pointer in
            channelData[0].update(from: pointer.baseAddress!, count: pointer.count)
          }
        }
        
        self.scheduledFrameCount += 1
        self.totalBuffersEnqueued += 1
        
        self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
          self?.queue.async {
            self?.scheduledFrameCount -= 1
            self?.checkPlaybackComplete()
          }
        }
        
        if !self.player.isPlaying && self.hasStartedPlayback {
          self.player.play()
        }
      } else {
        self.checkPlaybackComplete()
      }
    }
  }

  func play(wavData: Data) {
    queue.async {
      let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")
      var shouldRemoveImmediately = true
      do {
        try wavData.write(to: tmpURL)
        let file = try AVAudioFile(forReading: tmpURL)
        self.configureSessionIfNeeded(sampleRate: file.fileFormat.sampleRate)
        self.ensureFormat(sampleRate: file.fileFormat.sampleRate)
        self.player.scheduleFile(
          file, at: nil,
          completionHandler: {
            try? FileManager.default.removeItem(at: tmpURL)
          })
        if !self.player.isPlaying {
          self.player.play()
        }
        shouldRemoveImmediately = false
      } catch {
        try? FileManager.default.removeItem(at: tmpURL)
        print("AudioPlaybackManager error: \(error)")
      }

      if shouldRemoveImmediately {
        try? FileManager.default.removeItem(at: tmpURL)
      }
    }
  }

  /// Stop playback immediately (without full reset)
  func stop() {
    queue.async {
      print("[AudioPlaybackManager] 🛑 === STOP === (scheduledFrames: \(self.scheduledFrameCount))")
      self.player.stop()
    }
  }

  func reset() {
    queue.async {
      print("[AudioPlaybackManager] 🔇 === RESET === (scheduledFrames: \(self.scheduledFrameCount), buffered: \(self.sampleBuffer.count))")
      self.stopDiagnosticLogging()
      self.player.stop()
      self.player.reset()
      self.format = nil
      self.scheduledFrameCount = 0
      self.totalBuffersEnqueued = 0
      self.generationComplete = false
      self.hasStartedPlayback = false
      self.isInRefillMode = false
      self.sampleBuffer.removeAll()
      self.playbackStartTime = nil  // Clear stuck detection
      self.lastProgressTime = nil
    }
  }
  
  /// Set mute state - when muted, stops playback and clears buffers
  func setMuted(_ muted: Bool) {
    queue.async {
      let wasMuted = self._isMuted
      self._isMuted = muted
      
      if muted && !wasMuted {
        // Just became muted: stop playback and clear all buffers
        print("[AudioPlaybackManager] 🔇 === MUTED === (clearing buffers)")
        self.stopDiagnosticLogging()
        self.player.stop()
        self.player.reset()
        self.scheduledFrameCount = 0
        self.totalBuffersEnqueued = 0
        self.generationComplete = false
        self.hasStartedPlayback = false
        self.isInRefillMode = false
        self.sampleBuffer.removeAll()
        self.playbackStartTime = nil
        self.lastProgressTime = nil
      } else if !muted && wasMuted {
        print("[AudioPlaybackManager] 🔊 === UNMUTED ===")
      }
    }
  }

  @discardableResult
  private func ensureFormat(sampleRate: Double) -> AVAudioFormat? {
    if let format, format.sampleRate == sampleRate {
      return format
    }

    guard let newFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    else {
      return nil
    }

    engine.disconnectNodeOutput(player)
    engine.connect(player, to: engine.mainMixerNode, format: newFormat)
    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        print("AudioPlaybackManager engine start error: \(error)")
      }
    }
    format = newFormat
    return newFormat
  }

  private func configureSessionIfNeeded(sampleRate: Double? = nil) {
    if !sessionConfigured {
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord,
          mode: .default,
          options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: [])
      } catch {
        print("AudioPlaybackManager session error: \(error)")
      }
      sessionConfigured = true
    }

    if let sampleRate {
      _ = ensureFormat(sampleRate: sampleRate)
    } else if let format {
      _ = ensureFormat(sampleRate: format.sampleRate)
    }

    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        print("AudioPlaybackManager engine restart error: \(error)")
      }
    }
  }
}

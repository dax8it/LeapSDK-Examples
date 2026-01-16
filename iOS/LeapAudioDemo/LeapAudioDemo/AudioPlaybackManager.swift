import AVFoundation
import Foundation

final class AudioPlaybackManager {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  
  // High-priority queue for audio scheduling (userInteractive QoS)
  private let queue = DispatchQueue(label: "ai.leap.audio.playback", qos: .userInteractive)
  
  private var format: AVAudioFormat?
  private var sessionConfigured = false
  private var pendingBuffers = 0
  private var isPlaybackActive = false
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
  
  var onPlaybackComplete: (() -> Void)?

  init() {
    print("[AudioPlaybackManager] 🔊 Initializing (frame-based buffering)")
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: nil)
  }
  
  var isPlaying: Bool {
    return isPlaybackActive || player.isPlaying
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
      
      self.configureSessionIfNeeded(sampleRate: Double(sampleRate))
      self.currentSampleRate = sampleRate
      self.isPlaybackActive = true
      
      // Append incoming samples to ring buffer
      self.sampleBuffer.append(contentsOf: samples)
      
      // Check if we have enough for jitter buffer (first time only)
      if !self.hasStartedPlayback {
        if self.sampleBuffer.count >= self.jitterBufferSamples {
          print("[AudioPlaybackManager] 🔊 === PLAYBACK START === (jitter buffer filled: \(self.sampleBuffer.count) samples)")
          self.hasStartedPlayback = true
          self.drainBufferToFrames()
        }
      } else {
        // Already playing, drain available frames
        self.drainBufferToFrames()
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
      
      pendingBuffers += 1
      totalBuffersEnqueued += 1
      
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        self?.queue.async {
          self?.pendingBuffers -= 1
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
    // Only fire complete if generation is done AND no pending buffers AND buffer is drained
    if pendingBuffers == 0 && isPlaybackActive && generationComplete && sampleBuffer.count < frameSize {
      print("[AudioPlaybackManager] 🔊 === PLAYBACK COMPLETE === (total frames: \(totalBuffersEnqueued))")
      isPlaybackActive = false
      totalBuffersEnqueued = 0
      generationComplete = false
      hasStartedPlayback = false
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
        
        self.pendingBuffers += 1
        self.totalBuffersEnqueued += 1
        
        self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
          self?.queue.async {
            self?.pendingBuffers -= 1
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

  func reset() {
    queue.async {
      print("[AudioPlaybackManager] 🔇 === RESET === (pending: \(self.pendingBuffers), buffered: \(self.sampleBuffer.count))")
      self.player.stop()
      self.player.reset()
      self.format = nil
      self.pendingBuffers = 0
      self.isPlaybackActive = false
      self.totalBuffersEnqueued = 0
      self.generationComplete = false
      self.hasStartedPlayback = false
      self.sampleBuffer.removeAll()
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

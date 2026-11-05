import AVFoundation

// TTS bytes are already downloaded. Keep playback and pitch changes local so
// cached passages need no new synthesis, and preserve pause/seek semantics.
final class PitchAudioPlayer {
  let engine = AVAudioEngine()
  let node = AVAudioPlayerNode()
  let timePitch = AVAudioUnitTimePitch()
  var onComplete: (() -> Void)?
  private var file: AVAudioFile?
  private var offset: AVAudioFramePosition = 0
  private var revision = 0
  private var scheduled = false
  private(set) var isPlaying = false

  init() {
    engine.attach(node)
    engine.attach(timePitch)
  }

  var duration: Double { file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0 }
  var position: Double {
    guard let file else { return 0 }
    let frames = node.lastRenderTime.flatMap { node.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
    return min(duration, Double(offset + max(0, frames)) / file.processingFormat.sampleRate)
  }

  func load(_ url: URL) throws {
    reset()
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.length <= Int64(UInt32.max) else {
      throw NSError(domain: "ModuTtsAudio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid TTS audio length"])
    }
    self.file = file
    engine.disconnectNodeOutput(node)
    engine.disconnectNodeOutput(timePitch)
    engine.connect(node, to: timePitch, format: file.processingFormat)
    engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    engine.prepare()
  }

  func setPitch(_ multiplier: Double) {
    timePitch.pitch = Float(1200 * log2(multiplier))
  }

  func setRate(_ rate: Double) { timePitch.rate = Float(rate) }
  func setVolume(_ volume: Double) { node.volume = Float(volume) }

  func resume() throws {
    guard let file else { return }
    if !engine.isRunning { try engine.start() }
    if !scheduled {
      let remaining = file.length - offset
      guard remaining > 0 else {
        onComplete?()
        return
      }
      let token = revision
      scheduled = true
      node.scheduleSegment(file, startingFrame: offset, frameCount: AVAudioFrameCount(remaining),
                           at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.revision == token, self.scheduled else { return }
          self.scheduled = false
          self.offset = file.length
          self.node.stop()
          if self.isPlaying {
            self.isPlaying = false
            self.onComplete?()
          }
        }
      }
    }
    node.play()
    isPlaying = true
  }

  func pause() {
    node.pause()
    isPlaying = false
    engine.pause()
  }

  func seek(_ seconds: Double) throws {
    guard let file else { return }
    let playing = isPlaying
    revision += 1
    node.stop()
    scheduled = false
    offset = AVAudioFramePosition(min(duration, max(0, seconds)) * file.processingFormat.sampleRate)
    if playing { try resume() }
  }

  func reset() {
    revision += 1
    node.stop()
    engine.stop()
    scheduled = false
    isPlaying = false
    offset = 0
    file = nil
  }

  deinit { reset() }
}

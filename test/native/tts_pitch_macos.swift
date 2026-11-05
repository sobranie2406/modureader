import AVFoundation

@main
struct PitchTest {
  static func main() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("modu-pitch-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
    tone.frameLength = tone.frameCapacity
    for i in 0..<Int(tone.frameLength) {
      tone.floatChannelData![0][i] = Float(0.2 * sin(2 * .pi * 440 * Double(i) / 24000))
    }
    do {
      let output = try AVAudioFile(forWriting: url, settings: format.settings)
      try output.write(from: tone)
    }
    for (rate, pitch) in [(1.0, 0.5), (1.0, 1.0), (1.0, 2.0), (0.1, 1.0), (0.6, 1.2), (4.0, 1.0)] {
      let player = PitchAudioPlayer()
      try player.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
      try player.load(url)
      player.setRate(rate)
      player.setPitch(pitch)
      try player.resume()
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
      var samples: [Float] = []
      let frames = Int((2 / rate + 0.4) * 24000)
      while samples.count < frames {
        let status = try player.engine.renderOffline(AVAudioFrameCount(min(4096, frames - samples.count)), to: buffer)
        if status == .cannotDoInCurrentContext { continue }
        precondition(status == .success)
        samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
      }
      // Skip TimePitch's start/end padding when measuring pitch.
      let start = Int(0.15 * 24000)
      let end = min(samples.count, Int((2 / rate - 0.1) * 24000))
      let crossings = (start + 1..<end).filter { samples[$0 - 1] < 0 && samples[$0] >= 0 }.count
      let frequency = Double(crossings) * 24000 / Double(end - start)
      precondition(abs(frequency - 440 * pitch) < 15, "Pitch drift: \(frequency), rate=\(rate), pitch=\(pitch)")
      let active = samples.indices.filter { abs(samples[$0]) > 0.02 }
      let duration = Double(active.last! - active.first!) / 24000
      precondition(abs(duration - 2 / rate) < 0.25, "Speed drift: \(duration), rate=\(rate)")
      player.pause()
      player.setRate(1.7)
      player.setPitch(0.8)
      precondition(!player.isPlaying && !player.engine.isRunning)
      try player.seek(0.5)
      precondition(abs(player.position - 0.5) < 0.01)
      precondition(!player.isPlaying)
      player.reset()
      precondition(player.duration == 0 && player.position == 0 && !player.isPlaying)
      print("PASS rate=\(rate) pitch=\(pitch) frequency=\(Int(frequency))Hz duration=\(duration)s")
    }
    // Verify real compressed TTS audio, source positions and callbacks too.
    if CommandLine.arguments.count > 1 {
      let player = PitchAudioPlayer()
      try player.load(URL(fileURLWithPath: CommandLine.arguments[1]))
      player.setVolume(0)
      player.setRate(1.7)
      player.setPitch(0.8)
      var completed = 0
      player.onComplete = { completed += 1 }
      try player.resume()
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      let first = player.position
      precondition(first > 0.1)
      player.pause()
      let paused = player.position
      player.setPitch(1.3)
      player.setRate(4)
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      precondition(abs(player.position - paused) < 0.03 && !player.isPlaying)
      try player.resume()
      let deadline = Date().addingTimeInterval(player.duration / 4 + 2)
      while completed == 0 && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }
      precondition(completed == 1, "Real TTS must complete exactly once")
      print("PASS actual TTS MP3: duration=\(player.duration)s, source position=\(first)s, pause/resume, live rate/pitch, completion")
      player.reset()
    }
  }
}

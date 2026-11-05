import AVKit

private let defaultPlaybackRate: Double = 1.0

private let defaultVolume: Double = 1.0

private let defaultReleaseMode: ReleaseMode = ReleaseMode.release

typealias Completer = () -> Void

typealias CompleterError = (Error?) -> Void

enum ReleaseMode: String {
  case stop
  case release
  case loop
}

class WrappedMediaPlayer {
  private(set) var eventHandler: AudioPlayersStreamHandler
  private(set) var isPlaying: Bool
  var releaseMode: ReleaseMode

  private var reference: SwiftAudioplayersDarwinPlugin
  private var player: AVPlayer
  private var playbackRate: Double
  private var volume: Double
  private var url: String?
  private var pitchPlayer: PitchAudioPlayer?

  private var completionObserver: TimeObserver?
  private var playerItemStatusObservation: NSKeyValueObservation?

  init(
    reference: SwiftAudioplayersDarwinPlugin,
    eventHandler: AudioPlayersStreamHandler,
    player: AVPlayer = AVPlayer.init(),
    playbackRate: Double = defaultPlaybackRate,
    volume: Double = defaultVolume,
    releaseMode: ReleaseMode = defaultReleaseMode,
    url: String? = nil
  ) {
    self.reference = reference
    self.eventHandler = eventHandler
    self.player = player
    self.completionObserver = nil
    self.playerItemStatusObservation = nil

    self.isPlaying = false
    self.playbackRate = playbackRate
    self.volume = volume
    self.releaseMode = releaseMode
    self.url = url
  }

  func setSourceUrl(
    url: String,
    isLocal: Bool,
    mimeType: String? = nil,
    completer: Completer? = nil,
    completerError: CompleterError? = nil
  ) {
    if let pitchPlayer {
      do {
        guard isLocal else { throw AudioPlayerError.error("Local TTS audio required for pitch control") }
        if self.url != url {
          try pitchPlayer.load(URL(fileURLWithPath: url.deletingPrefix("file://")))
          self.url = url
          isPlaying = false
        }
        completer?()
        updateDuration()
      } catch {
        self.url = nil
        completerError?(error)
      }
      return
    }
    let playbackStatus = player.currentItem?.status

    if self.url != url || playbackStatus == .failed || playbackStatus == nil {
      reset()
      self.url = url
      do {
        let playerItem = try createPlayerItem(url: url, isLocal: isLocal, mimeType: mimeType)
        // Need to observe item status immediately after creating:
        setUpPlayerItemStatusObservation(
          playerItem,
          completer: completer,
          completerError: completerError)
        // Replacing the player item triggers completion in setUpPlayerItemStatusObservation
        self.player.replaceCurrentItem(with: playerItem)
        self.setUpSoundCompletedObserver(self.player, playerItem)
      } catch {
        completerError?(error)
      }
    } else {
      if playbackStatus == .readyToPlay {
        completer?()
      }
    }
  }

  func getDuration() -> Int? {
    if let pitchPlayer { return Int(pitchPlayer.duration * 1000) }
    guard let duration = getDurationCMTime() else {
      return nil
    }
    return fromCMTime(time: duration)
  }

  func getCurrentPosition() -> Int? {
    if let pitchPlayer { return Int(pitchPlayer.position * 1000) }
    guard let time = getCurrentCMTime() else {
      return nil
    }
    return fromCMTime(time: time)
  }

  func pause() {
    isPlaying = false
    player.pause()
    pitchPlayer?.pause()
  }

  func resume() throws {
    if let pitchPlayer {
      isPlaying = true
      do { try pitchPlayer.resume() } catch { isPlaying = false; throw error }
      updateDuration()
      return
    }
    isPlaying = true
    configParameters(player: player)
    if #available(iOS 10.0, macOS 10.12, *) {
      player.playImmediately(atRate: Float(playbackRate))
    } else {
      player.play()
    }
    updateDuration()
  }

  func setVolume(volume: Double) {
    self.volume = volume
    player.volume = Float(volume)
    pitchPlayer?.setVolume(volume)
  }

  func setPlaybackRate(playbackRate: Double) {
    self.playbackRate = playbackRate
    if let pitchPlayer { pitchPlayer.setRate(playbackRate); return }
    if isPlaying {
      // Setting the rate causes the player to resume playing. So setting it only, when already playing.
      player.rate = Float(playbackRate)
    }
  }

  func setPitch(pitch: Double) {
    if pitchPlayer == nil {
      reset()
      let local = PitchAudioPlayer()
      local.setRate(playbackRate)
      local.setVolume(volume)
      local.onComplete = { [weak self] in
        guard let self, self.isPlaying else { return }
        self.isPlaying = false
        self.pitchPlayer?.pause()
        try? self.pitchPlayer?.seek(0)
        if self.releaseMode == .loop {
          do { try self.resume() } catch { self.reportPitchError(error) }
        } else if self.releaseMode == .release {
          self.reset()
        }
        self.reference.controlAudioSession()
        self.eventHandler.onComplete()
      }
      pitchPlayer = local
    }
    pitchPlayer?.setPitch(pitch)
  }

  private func reportPitchError(_ error: Error) {
    isPlaying = false
    pitchPlayer?.pause()
    eventHandler.onError(code: "DarwinAudioError", message: "TTS playback failed", details: "\(error)")
  }

  func seek(time: CMTime, completer: Completer? = nil) {
    if let pitchPlayer {
      do { try pitchPlayer.seek(CMTimeGetSeconds(time)) } catch { reportPitchError(error) }
      eventHandler.onSeekComplete()
      completer?()
      return
    }
    guard let currentItem = player.currentItem else {
      completer?()
      return
    }
    currentItem.seek(to: time) {
      finished in
      if !self.isPlaying {
        self.player.pause()
      }
      self.eventHandler.onSeekComplete()
      if finished {
        completer?()
      }
    }
  }

  func stop(completer: Completer? = nil) {
    pause()
    seek(time: toCMTime(millis: 0), completer: completer)
    if releaseMode == ReleaseMode.release {
      release(completer: completer)
    }
  }

  func release(completer: Completer? = nil) {
    if self.isPlaying {
      // Avoid loop of stop and release
      stop {
        self.reset()
        completer?()
      }
      return
    }
    self.reset()
    completer?()
  }

  func dispose(completer: Completer? = nil) {
    release {
      completer?()
    }
  }

  private func getDurationCMTime() -> CMTime? {
    return player.currentItem?.asset.duration
  }

  private func getCurrentCMTime() -> CMTime? {
    return player.currentItem?.currentTime()
  }

  private func createPlayerItem(
    url: String,
    isLocal: Bool,
    mimeType: String? = nil
  ) throws -> AVPlayerItem {
    guard
      let parsedUrl = isLocal
        ? URL(fileURLWithPath: url.deletingPrefix("file://")) : URL(string: url)
    else {
      throw AudioPlayerError.error("Url not valid: \(url)")
    }

    let playerItem: AVPlayerItem

    if let unwrappedMimeType = mimeType {
      if #available(iOS 17, macOS 14.0, *) {
        let asset = AVURLAsset(
          url: parsedUrl, options: [AVURLAssetOverrideMIMETypeKey: unwrappedMimeType])
        playerItem = AVPlayerItem(asset: asset)
      } else {
        let asset = AVURLAsset(
          url: parsedUrl, options: ["AVURLAssetOutOfBandMIMETypeKey": unwrappedMimeType])
        playerItem = AVPlayerItem(asset: asset)
      }
    } else {
      playerItem = AVPlayerItem(url: parsedUrl)
    }

    playerItem.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.timeDomain
    return playerItem
  }

  private func setUpPlayerItemStatusObservation(
    _ playerItem: AVPlayerItem,
    completer: Completer? = nil,
    completerError: CompleterError? = nil
  ) {
    playerItemStatusObservation = playerItem.observe(\AVPlayerItem.status) { (playerItem, change) in
      let status = playerItem.status
      self.eventHandler.onLog(message: "player status: \(status), change: \(change)")

      switch playerItem.status {
      case .readyToPlay:
        completer?()
        // Needs to be called after preparation callback.
        self.updateDuration()
      case .failed:
        self.reset()
        completerError?(nil)
      default:
        break
      }
    }
  }

  private func setUpSoundCompletedObserver(_ player: AVPlayer, _ playerItem: AVPlayerItem) {
    let observer = NotificationCenter.default.addObserver(
      forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
      object: playerItem,
      queue: nil
    ) {
      [weak self] (notification) in
      self?.onSoundComplete()
    }
    self.completionObserver = TimeObserver(player: player, observer: observer)
  }

  private func configParameters(player: AVPlayer) {
    if isPlaying {
      player.volume = Float(volume)
      player.rate = Float(playbackRate)
    }
  }

  private func reset() {
    pitchPlayer?.reset()
    playerItemStatusObservation?.invalidate()
    playerItemStatusObservation = nil
    if let cObserver = completionObserver {
      NotificationCenter.default.removeObserver(cObserver.observer)
      completionObserver = nil
    }
    player.replaceCurrentItem(with: nil)
    self.url = nil
  }

  private func updateDuration() {
    if let pitchPlayer { eventHandler.onDuration(millis: Int(pitchPlayer.duration * 1000)); return }
    guard let duration = player.currentItem?.asset.duration else {
      return
    }
    if CMTimeGetSeconds(duration) > 0 {
      let millis = fromCMTime(time: duration)
      eventHandler.onDuration(millis: millis)
    }
  }

  private func onSoundComplete() {
    if !isPlaying {
      return
    }

    seek(time: toCMTime(millis: 0)) {
      if self.releaseMode == ReleaseMode.loop {
        do { try self.resume() } catch { self.reportPitchError(error) }
      } else if self.releaseMode == ReleaseMode.release {
        self.release()
      } else {
        self.isPlaying = false
      }
    }

    reference.controlAudioSession()
    eventHandler.onComplete()
  }
}

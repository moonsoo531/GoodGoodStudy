import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// iPhone audio owns playback, looping, deadlines and remote controls even when
/// the Flutter page isn't receiving events. No network or third-party decoder.
final class IOSAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = IOSAudioPlugin()
    let methods = FlutterMethodChannel(
      name: "offline_player/ios_audio", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(
      name: "offline_player/ios_audio_events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
    instance.eventChannel = events
  }

  private let player = AVPlayer()
  private let diagnostics = IOSAudioDiagnostics()
  private var eventChannel: FlutterEventChannel?
  private var sink: FlutterEventSink?
  private var path: String?
  private var title = ""
  private var requestedRate = 1.0
  private var volume = 100.0
  private var lastError: String?
  private var intent = IOSPlaybackIntent()
  private var loop: IOSAudioLoop?
  private var stopAtEpochMs: Int64?
  private var stopTimer: Timer?
  private var positionObserver: Any?
  private var boundaryObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var durationObservation: NSKeyValueObservation?
  private var controlObservation: NSKeyValueObservation?
  private var notifications: [NSObjectProtocol] = []
  private var remoteTargets: [(MPRemoteCommand, Any)] = []
  private var opening = false
  private var finishingOpen = false
  private var pendingOpen: FlutterResult?
  private var pendingAutoplay = false
  private var openTimeout: DispatchWorkItem?
  private var openGeneration = 0
  private var loopGeneration = 0
  private var seekingLoop = false

  override init() {
    super.init()
    positionObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 1000), queue: .main
    ) { [weak self] _ in self?.tick() }
    controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateNowPlaying()
        self?.emit()
      }
    }
    observeAudioEvents()
    configureRemoteCommands()
  }

  deinit {
    openTimeout?.cancel()
    stopTimer?.invalidate()
    if let observer = positionObserver { player.removeTimeObserver(observer) }
    if let observer = boundaryObserver { player.removeTimeObserver(observer) }
    notifications.forEach { NotificationCenter.default.removeObserver($0) }
    remoteTargets.forEach { $0.0.removeTarget($0.1) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    emit()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in self?.handle(call, result: result) }
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method != "snapshot" { diagnostics.record("command", detail: ["name": call.method]) }
    do {
      _ = checkStopDeadline()
      if call.method != "snapshot" { lastError = nil }
      switch call.method {
      case "open": try open(args, result: result); return
      case "play": try requireReady(); try play()
      case "pause": pause()
      case "seek":
        try requireReady()
        let position = try integer(args, "positionMs")
        guard position >= 0 else { throw IOSAudioRuleError.invalid("Negative playback position.") }
        seek(position, result: result)
        return
      case "setRate":
        let rate = try number(args, "rate")
        guard IOSAudioRules.validRate(rate) else {
          throw IOSAudioRuleError.invalid("Playback speed must be between 0.25 and 3.")
        }
        requestedRate = rate
        if intent.wantsPlayback && !intent.interrupted { player.rate = Float(rate) }
      case "setVolume":
        let value = try number(args, "volume")
        guard (0...100).contains(value) else {
          throw IOSAudioRuleError.invalid("Volume must be between 0 and 100.")
        }
        volume = value
        player.volume = Float(value / 100)
      case "setLoop":
        try requireReady()
        var newLoop = try IOSAudioLoop(
          startMs: try integer(args, "startMs"), endMs: try integer(args, "endMs"),
          repeatCount: try optionalInteger(args, "repeatCount").map { Int($0) },
          completedPasses: Int(try optionalInteger(args, "completedPasses") ?? 0))
        guard newLoop.endMs <= durationMs else {
          throw IOSAudioRuleError.invalid("The loop ends after the audio file.")
        }
        if newLoop.completed { pause() }
        // Completed loops stay visible; Play starts a fresh repetition set.
        if newLoop.completed { newLoop.completedPasses = newLoop.repeatCount! }
        loop = newLoop
        installBoundaryObserver()
        if !newLoop.completed && !newLoop.contains(positionMs) {
          seek(newLoop.startMs, result: result, preserveLoop: true)
          return
        }
      case "clearLoop": clearLoop()
      case "setStopAt":
        let stop = try optionalInteger(args, "epochMs")
        if let stop = stop, stop < 0 {
          throw IOSAudioRuleError.invalid("Invalid stop time.")
        }
        stopAtEpochMs = stop
        installStopTimer()
        _ = checkStopDeadline()
      case "snapshot": break
      case "dispose": close()
      default: throw IOSAudioRuleError.invalid("Unknown audio command: \(call.method)")
      }
      updateNowPlaying()
      emit()
      result(snapshot())
    } catch {
      lastError = error.localizedDescription
      emit()
      result(snapshot())
    }
  }

  private func open(_ args: [String: Any], result: @escaping FlutterResult) throws {
    guard let rawPath = args["path"] as? String else {
      throw IOSAudioRuleError.invalid("An absolute local audio path is required.")
    }
    let url = try IOSAudioRules.localFile(rawPath)
    let rate = try args["rate"].map { _ in try number(args, "rate") } ?? 1
    guard IOSAudioRules.validRate(rate) else {
      throw IOSAudioRuleError.invalid("Playback speed must be between 0.25 and 3.")
    }
    let requestedPosition = try optionalInteger(args, "positionMs") ?? 0
    guard requestedPosition >= 0 else { throw IOSAudioRuleError.invalid("Negative playback position.") }
    let autoplay = args["autoplay"] as? Bool ?? false
    if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
      IOSAudioRules.isImportedCopy(url, mediaDirectory: documents.appendingPathComponent("Media"))
    {
      // Never alter a file supplied by another provider or outside our imports.
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }
    cancelPendingOpen("The pending audio open was replaced.")
    openGeneration += 1
    let generation = openGeneration
    pause()
    clearLoop()
    player.replaceCurrentItem(with: nil)
    // Echo the caller's validated identity. Foundation and Dart may spell the
    // same sandbox file with different /var and /private/var prefixes. Opening
    // and protection still use the canonical URL verified above.
    path = rawPath
    let suppliedTitle = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    title = suppliedTitle?.isEmpty == false ? suppliedTitle! : url.deletingPathExtension().lastPathComponent
    requestedRate = rate
    lastError = nil
    opening = true
    finishingOpen = false
    pendingOpen = result
    pendingAutoplay = autoplay
    let item = AVPlayerItem(url: url)
    item.audioTimePitchAlgorithm = .timeDomain
    player.replaceCurrentItem(with: item)
    player.volume = Float(volume / 100)
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.finishOpenIfReady(generation, requestedPosition: requestedPosition)
      }
    }
    durationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.finishOpenIfReady(generation, requestedPosition: requestedPosition)
      }
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self, generation == self.openGeneration, self.pendingOpen != nil else { return }
      self.failOpen("The local audio file did not become ready within 15 seconds.")
    }
    openTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    updateNowPlaying()
    emit()
  }

  private func finishOpenIfReady(_ generation: Int, requestedPosition: Int64) {
    guard generation == openGeneration, let item = player.currentItem else { return }
    if item.status == .failed {
      failOpen(item.error?.localizedDescription ?? "The audio file could not be decoded.")
      return
    }
    guard pendingOpen != nil, !finishingOpen, item.status == .readyToPlay,
      item.duration.seconds.isFinite, item.duration.seconds > 0
    else { return }
    finishingOpen = true
    let target = min(requestedPosition, durationMs)
    player.seek(to: time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async {
        guard let self = self, generation == self.openGeneration, self.pendingOpen != nil else { return }
        guard finished else { self.failOpen("The initial audio seek was interrupted."); return }
        self.opening = false
        self.finishingOpen = false
        self.openTimeout?.cancel()
        self.openTimeout = nil
        if self.pendingAutoplay {
          do { try self.play() } catch { self.lastError = error.localizedDescription }
        }
        let completion = self.pendingOpen
        self.pendingOpen = nil
        self.pendingAutoplay = false
        self.diagnostics.record("open.ready")
        self.updateNowPlaying()
        self.emit()
        completion?(self.snapshot())
      }
    }
  }

  private func failOpen(_ message: String) {
    diagnostics.record("open.failed")
    opening = false
    finishingOpen = false
    openTimeout?.cancel()
    openTimeout = nil
    intent.userPause()
    player.pause()
    lastError = message
    let completion = pendingOpen
    pendingOpen = nil
    pendingAutoplay = false
    updateNowPlaying()
    emit()
    completion?(snapshot())
  }

  private func cancelPendingOpen(_ message: String) {
    openTimeout?.cancel()
    openTimeout = nil
    statusObservation = nil
    durationObservation = nil
    if let completion = pendingOpen {
      pendingOpen = nil
      var cancelled = snapshot()
      cancelled["error"] = message
      completion(cancelled)
    }
    opening = false
    finishingOpen = false
    pendingAutoplay = false
  }

  private func requireReady() throws {
    guard !opening, player.currentItem?.status == .readyToPlay, durationMs > 0 else {
      throw IOSAudioRuleError.invalid("Open an audio file before using playback controls.")
    }
  }

  private func play(userInitiated: Bool = true) throws {
    let activate = {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try AVAudioSession.sharedInstance().setActive(true)
    }
    if userInitiated {
      try intent.userPlay(activating: activate)
    } else {
      // Automatic recovery is only requested after endInterruption has accepted
      // shouldResume, preserved user intent and the unexpired stop deadline.
      guard intent.wantsPlayback && !intent.interrupted else { return }
      try activate()
    }
    if var active = loop, active.completed || !active.contains(positionMs) {
      active.completedPasses = 0
      loop = active
      installBoundaryObserver()
      seek(active.startMs, result: nil, preserveLoop: true)
    } else if positionMs >= durationMs {
      seek(0, result: nil, preserveLoop: true)
    } else {
      player.playImmediately(atRate: Float(requestedRate))
    }
  }

  private func pause() {
    pendingAutoplay = false
    intent.userPause()
    player.pause()
  }

  private func seek(_ milliseconds: Int64, result: FlutterResult?, preserveLoop: Bool = false) {
    let target = min(max(0, milliseconds), durationMs)
    if !preserveLoop, let active = loop, !active.contains(target) { clearLoop() }
    let generation = openGeneration
    player.seek(to: time(target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if generation != self.openGeneration || !finished {
          var cancelled = self.snapshot()
          cancelled["error"] = "The audio seek was superseded."
          result?(cancelled)
          return
        }
        if !self.checkStopDeadline(), self.intent.wantsPlayback, !self.intent.interrupted {
          self.player.playImmediately(atRate: Float(self.requestedRate))
        }
        self.updateNowPlaying()
        self.emit()
        result?(self.snapshot())
      }
    }
  }

  private func clearLoop() {
    loopGeneration += 1
    loop = nil
    seekingLoop = false
    if let observer = boundaryObserver { player.removeTimeObserver(observer) }
    boundaryObserver = nil
    player.currentItem?.forwardPlaybackEndTime = .invalid
  }

  private func installBoundaryObserver() {
    loopGeneration += 1
    seekingLoop = false
    if let observer = boundaryObserver { player.removeTimeObserver(observer) }
    boundaryObserver = nil
    guard let active = loop, !active.completed else {
      player.currentItem?.forwardPlaybackEndTime = .invalid
      return
    }
    let generation = loopGeneration
    player.currentItem?.forwardPlaybackEndTime = time(active.endMs)
    boundaryObserver = player.addBoundaryTimeObserver(
      forTimes: [NSValue(time: time(active.endMs))], queue: .main
    ) { [weak self] in
      guard let self = self, self.loopGeneration == generation else { return }
      self.finishLoopPass()
    }
  }

  private func finishLoopPass() {
    guard !checkStopDeadline(), !seekingLoop, intent.wantsPlayback,
      var active = loop, !active.completed, positionMs >= active.endMs - 5
    else { return }
    seekingLoop = true
    active.finishPass()
    loop = active
    diagnostics.record("loop.pass", detail: ["completedPasses": active.completedPasses, "completed": active.completed])
    if active.completed {
      pause()
      installBoundaryObserver()
      updateNowPlaying()
      emit()
      return
    }
    let generation = loopGeneration
    player.seek(to: time(active.startMs), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async {
        guard let self = self, self.loopGeneration == generation else { return }
        self.seekingLoop = false
        if finished, !self.checkStopDeadline(), self.intent.wantsPlayback, !self.intent.interrupted {
          self.player.playImmediately(atRate: Float(self.requestedRate))
        }
        self.updateNowPlaying()
        self.emit()
      }
    }
  }

  private func installStopTimer() {
    stopTimer?.invalidate()
    stopTimer = nil
    guard stopAtEpochMs != nil else { return }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self = self, self.checkStopDeadline() else { return }
      self.updateNowPlaying()
      self.emit()
    }
    RunLoop.main.add(timer, forMode: .common)
    stopTimer = timer
  }

  @discardableResult private func checkStopDeadline() -> Bool {
    guard let stop = stopAtEpochMs,
      Date().timeIntervalSince1970 * 1000 >= Double(stop)
    else { return false }
    stopAtEpochMs = nil
    diagnostics.record("stop.deadline")
    stopTimer?.invalidate()
    stopTimer = nil
    pause()
    return true
  }

  private func tick() {
    if checkStopDeadline() { updateNowPlaying() }
    if let active = loop, !active.completed, positionMs >= active.endMs { finishLoopPass() }
    if path != nil { emit() }
  }

  private func observeAudioEvents() {
    let center = NotificationCenter.default
    notifications.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self = self,
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      self.diagnostics.record("interruption", detail: ["type": type == .began ? "began" : "ended"])
      if type == .began {
        if self.opening { self.pendingAutoplay = false }
        self.intent.beginInterruption()
        self.player.pause()
      } else {
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        let expired = self.checkStopDeadline()
        let resume = self.intent.endInterruption(
          systemAllowsResume: options.contains(.shouldResume), deadlinePassed: expired)
        if resume {
          do { try self.play(userInitiated: false) } catch { self.lastError = error.localizedDescription; self.pause() }
        }
      }
      self.updateNowPlaying()
      self.emit()
    })
    notifications.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self = self,
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      else { return }
      self.diagnostics.record("route", detail: ["reason": reason])
      guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { self.emit(); return }
      self.diagnostics.record("route.oldDeviceUnavailable")
      self.pause()
      self.updateNowPlaying()
      self.emit()
    })
    notifications.append(center.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self = self, let item = notification.object as? AVPlayerItem,
        item === self.player.currentItem
      else { return }
      if let active = self.loop, !active.completed, self.intent.wantsPlayback {
        self.finishLoopPass()
      } else {
        self.pause()
        self.updateNowPlaying()
        self.emit()
      }
    })
    notifications.append(center.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self = self, let item = notification.object as? AVPlayerItem,
        item === self.player.currentItem
      else { return }
      self.pause()
      self.lastError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
        ?? "Audio playback failed. Reopen the file to try again."
      self.updateNowPlaying()
      self.emit()
    })
    for name in [
      UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
      UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
      UIApplication.protectedDataDidBecomeAvailableNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification,
    ] {
      notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        self?.diagnostics.record("lifecycle", detail: ["notification": notification.name.rawValue])
        self?.emit()
      })
    }
  }

  private func configureRemoteCommands() {
    let commands = MPRemoteCommandCenter.shared()
    register(commands.playCommand, name: "play") { [weak self] _ in
      guard let self = self else { return .commandFailed }
      do { try self.requireReady(); try self.play(); return .success } catch { return .commandFailed }
    }
    register(commands.pauseCommand, name: "pause") { [weak self] _ in self?.pause(); return .success }
    register(commands.togglePlayPauseCommand, name: "togglePlayPause") { [weak self] _ in
      guard let self = self else { return .commandFailed }
      if self.intent.wantsPlayback && !self.intent.interrupted { self.pause(); return .success }
      do { try self.requireReady(); try self.play(); return .success } catch { return .commandFailed }
    }
    register(commands.changePlaybackPositionCommand, name: "changePlaybackPosition") { [weak self] event in
      guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent,
        self.player.currentItem?.status == .readyToPlay, event.positionTime.isFinite
      else { return .commandFailed }
      self.seek(IOSAudioRules.milliseconds(event.positionTime), result: nil)
      return .success
    }
    commands.skipForwardCommand.preferredIntervals = [15]
    commands.skipBackwardCommand.preferredIntervals = [15]
    register(commands.skipForwardCommand, name: "skipForward") { [weak self] event in
      self?.remoteSkip(event, direction: 1) ?? .commandFailed
    }
    register(commands.skipBackwardCommand, name: "skipBackward") { [weak self] event in
      self?.remoteSkip(event, direction: -1) ?? .commandFailed
    }
    updateRemoteAvailability()
  }

  private func register(_ command: MPRemoteCommand, name: String, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
    let target = command.addTarget { [weak self] event in
      let perform = { () -> MPRemoteCommandHandlerStatus in
        guard let self = self else { return .commandFailed }
        self.diagnostics.recordRemote(name)
        _ = self.checkStopDeadline()
        let status = handler(event)
        self.updateNowPlaying()
        self.emit()
        return status
      }
      if Thread.isMainThread { return perform() }
      return DispatchQueue.main.sync(execute: perform)
    }
    remoteTargets.append((command, target))
  }

  private func remoteSkip(_ event: MPRemoteCommandEvent, direction: Int64) -> MPRemoteCommandHandlerStatus {
    guard player.currentItem?.status == .readyToPlay,
      let skip = event as? MPSkipIntervalCommandEvent, skip.interval.isFinite
    else { return .commandFailed }
    let delta = IOSAudioRules.milliseconds(min(max(0, skip.interval), 3600)) * direction
    seek(positionMs + delta, result: nil)
    return .success
  }

  private func updateRemoteAvailability() {
    let available = !opening && player.currentItem?.status == .readyToPlay
    for (command, _) in remoteTargets { command.isEnabled = available }
  }

  private func updateNowPlaying() {
    updateRemoteAvailability()
    guard path != nil else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
    var metadata: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: player.rate > 0 ? requestedRate : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: requestedRate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if #available(iOS 18.0, *) { metadata[MPNowPlayingInfoPropertyExcludeFromSuggestions] = true }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
  }

  private var positionMs: Int64 { IOSAudioRules.milliseconds(player.currentTime().seconds) }
  private var durationMs: Int64 { IOSAudioRules.milliseconds(player.currentItem?.duration.seconds ?? 0) }
  private func time(_ ms: Int64) -> CMTime { CMTime(value: ms, timescale: 1000) }

  private func snapshot() -> [String: Any] {
    [
      "path": path.map { $0 as Any } ?? NSNull(), "title": title,
      "positionMs": positionMs, "durationMs": durationMs,
      "playing": player.timeControlStatus == .playing && player.rate > 0,
      "buffering": opening || (intent.wantsPlayback && player.timeControlStatus == .waitingToPlayAtSpecifiedRate),
      "rate": requestedRate, "volume": volume,
      "error": lastError.map { $0 as Any } ?? NSNull(),
      "loop": loop.map { $0.dictionary as Any } ?? NSNull(),
      "stopAtEpochMs": stopAtEpochMs.map { $0 as Any } ?? NSNull(),
    ]
  }

  private func emit() {
    let value = snapshot()
    diagnostics.update(value)
    sink?(value)
  }

  private func number(_ args: [String: Any], _ key: String) throws -> Double {
    guard let value = args[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
      value.doubleValue.isFinite
    else { throw IOSAudioRuleError.invalid("A finite number is required for \(key).") }
    return value.doubleValue
  }

  private func integer(_ args: [String: Any], _ key: String) throws -> Int64 {
    let value = try number(args, key)
    guard value.rounded(.towardZero) == value, abs(value) <= 9_000_000_000_000_000 else {
      throw IOSAudioRuleError.invalid("An integer is required for \(key).")
    }
    return Int64(value)
  }

  private func optionalInteger(_ args: [String: Any], _ key: String) throws -> Int64? {
    guard let value = args[key], !(value is NSNull) else { return nil }
    return try integer(args, key)
  }

  private func close() {
    cancelPendingOpen("The audio player was closed.")
    openGeneration += 1
    pause()
    clearLoop()
    player.replaceCurrentItem(with: nil)
    path = nil
    title = ""
    stopAtEpochMs = nil
    stopTimer?.invalidate()
    stopTimer = nil
    lastError = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

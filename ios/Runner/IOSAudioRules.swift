import Foundation

enum IOSAudioRuleError: LocalizedError {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

/// Platform-independent rules shared by the player and its tests.
struct IOSAudioLoop {
  let startMs: Int64
  let endMs: Int64
  let repeatCount: Int?
  var completedPasses: Int

  init(startMs: Int64, endMs: Int64, repeatCount: Int?, completedPasses: Int = 0) throws {
    guard startMs >= 0, endMs > startMs else {
      throw IOSAudioRuleError.invalid("The loop must have a positive duration.")
    }
    guard repeatCount == nil || repeatCount! > 0,
      completedPasses >= 0,
      repeatCount == nil || completedPasses <= repeatCount!
    else {
      throw IOSAudioRuleError.invalid("Invalid loop repetition count.")
    }
    self.startMs = startMs
    self.endMs = endMs
    self.repeatCount = repeatCount
    self.completedPasses = completedPasses
  }

  var completed: Bool {
    repeatCount.map { completedPasses >= $0 } ?? false
  }

  mutating func finishPass() {
    if !completed, completedPasses < Int.max { completedPasses += 1 }
  }

  func contains(_ positionMs: Int64) -> Bool {
    positionMs >= startMs && positionMs < endMs
  }

  var dictionary: [String: Any] {
    [
      "startMs": startMs,
      "endMs": endMs,
      "repeatCount": repeatCount.map { $0 as Any } ?? NSNull(),
      "completedPasses": completedPasses,
      "completed": completed,
    ]
  }
}

struct IOSPlaybackIntent {
  private(set) var wantsPlayback = false
  private(set) var interrupted = false
  private var resumeAfterInterruption = false

  mutating func userPlay(activating activate: () throws -> Void) rethrows {
    // A began notification isn't guaranteed to have a matching ended event.
    // Commit an explicit Play only after the system accepts reactivation. If
    // activation throws, preserve every part of the previous interruption state.
    try activate()
    wantsPlayback = true
    interrupted = false
    resumeAfterInterruption = false
  }

  mutating func userPause() {
    wantsPlayback = false
    resumeAfterInterruption = false
  }

  mutating func beginInterruption() {
    // AVPlayer may have already paused before iOS delivers the interruption.
    // Preserve explicit user intent rather than sampling the now-paused player.
    resumeAfterInterruption = wantsPlayback
    interrupted = true
  }

  mutating func endInterruption(systemAllowsResume: Bool, deadlinePassed: Bool) -> Bool {
    // A delayed ended notification must not overwrite a newer successful
    // explicit Play that already cleared the interruption.
    guard interrupted else { return false }
    let resume = resumeAfterInterruption && wantsPlayback
      && systemAllowsResume && !deadlinePassed
    interrupted = false
    resumeAfterInterruption = false
    wantsPlayback = resume
    return resume
  }
}

enum IOSAudioRules {
  static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "aif", "aiff", "caf"]

  static func localFile(_ path: String) throws -> URL {
    guard path.hasPrefix("/"), !path.contains("\0") else {
      throw IOSAudioRuleError.invalid("Choose a local audio file using an absolute file path.")
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
      throw IOSAudioRuleError.invalid("Supported audio: MP3, M4A, WAV, AAC, AIF, AIFF, CAF.")
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      FileManager.default.isReadableFile(atPath: url.path)
    else {
      throw IOSAudioRuleError.invalid("The selected path must be a readable regular audio file.")
    }
    return url.resolvingSymlinksInPath()
  }

  static func isImportedCopy(_ url: URL, mediaDirectory: URL) -> Bool {
    let parent = mediaDirectory.standardizedFileURL.resolvingSymlinksInPath().path
    let expectedParent = mediaDirectory.deletingLastPathComponent().standardizedFileURL
      .resolvingSymlinksInPath().appendingPathComponent(mediaDirectory.lastPathComponent).path
    guard parent == expectedParent else { return false }
    let child = url.standardizedFileURL.resolvingSymlinksInPath().path
    return child.hasPrefix(parent + "/")
  }

  static func validRate(_ rate: Double) -> Bool {
    rate.isFinite && (0.25...3).contains(rate)
  }

  static func milliseconds(_ seconds: Double) -> Int64 {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    // Long before Double's representation of Int64.max can round upward.
    return Int64(min(seconds * 1000, 9_000_000_000_000_000).rounded())
  }
}

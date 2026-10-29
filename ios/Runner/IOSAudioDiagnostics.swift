import Foundation
import UIKit

/// Local-only developer validation, disabled by default in Info.plist.
/// Enable the flag explicitly for diagnostic builds. Writes are coalesced to
/// at most once every five seconds when enabled.
final class IOSAudioDiagnostics {
  private let enabled = Bundle.main.object(forInfoDictionaryKey: "IOSAudioValidationEnabled") as? Bool ?? false
  private let writer = DispatchQueue(label: "offline_player.audio_validation", qos: .utility)
  private var recentEvents: [[String: Any]] = []
  private var remoteCommandCounts: [String: Int] = [:]
  private var latestSnapshot: [String: Any] = [:]
  private var lastWrite = Date.distantPast
  private var pendingWrite: DispatchWorkItem?

  func record(_ name: String, detail: [String: Any] = [:]) {
    guard enabled else { return }
    recentEvents.append([
      "epochMs": IOSAudioRules.milliseconds(Date().timeIntervalSince1970),
      "name": name, "detail": detail,
    ])
    if recentEvents.count > 80 { recentEvents.removeFirst(recentEvents.count - 80) }
  }

  func recordRemote(_ name: String) {
    guard enabled else { return }
    remoteCommandCounts[name, default: 0] += 1
    record("remote", detail: ["command": name, "count": remoteCommandCounts[name]!])
  }

  func update(_ snapshot: [String: Any]) {
    guard enabled else { return }
    latestSnapshot = snapshot
    // Source paths, OS error text, device/account identifiers aren't needed to
    // demonstrate playback. Keep only the selected title and playback state.
    latestSnapshot.removeValue(forKey: "path")
    latestSnapshot["errorPresent"] = !(latestSnapshot["error"] is NSNull)
    latestSnapshot.removeValue(forKey: "error")
    if Date().timeIntervalSince(lastWrite) >= 5 {
      flush()
    } else if pendingWrite == nil {
      let work = DispatchWorkItem { [weak self] in
        self?.pendingWrite = nil
        self?.flush()
      }
      pendingWrite = work
      DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 5 - Date().timeIntervalSince(lastWrite)), execute: work)
    }
  }

  private func flush() {
    guard enabled, !latestSnapshot.isEmpty,
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    lastWrite = Date()
    let app = UIApplication.shared
    let state: String
    switch app.applicationState {
    case .active: state = "foreground"
    case .inactive: state = "inactive"
    case .background: state = "background"
    @unknown default: state = "unknown"
    }
    let payload: [String: Any] = [
      "schemaVersion": 1,
      "updatedAtEpochMs": IOSAudioRules.milliseconds(lastWrite.timeIntervalSince1970),
      "applicationState": state,
      "protectedDataAvailable": app.isProtectedDataAvailable,
      "snapshot": latestSnapshot,
      "remoteCommandCounts": remoteCommandCounts,
      "recentEvents": recentEvents,
    ]
    let destination = documents.appendingPathComponent("ios-audio-validation.json")
    writer.async {
      guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
      try? bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
  }
}

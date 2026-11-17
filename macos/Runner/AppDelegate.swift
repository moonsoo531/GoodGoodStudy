import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    MediaOpenInbox.shared.append(urls)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Finder can deliver documents before the main nib or Dart isolate is ready.
/// Keep the original URLs (and their sandbox grants) until Dart pulls them.
final class MediaOpenInbox {
  static let shared = MediaOpenInbox()
  static let extensions: Set<String> = [
    "mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff", "aif", "caf", "wma", "alac",
    "mkv", "mp4", "m4v", "mov", "webm", "avi", "ts", "wmv", "mpg", "mpeg", "m2ts",
  ]
  private var requests: [[URL]] = []
  var onAvailable: (() -> Void)?

  func append(_ urls: [URL]) {
    var seen = Set<String>()
    let media = urls.filter {
      $0.isFileURL && Self.extensions.contains($0.pathExtension.lowercased()) &&
        seen.insert($0.standardizedFileURL.path).inserted
    }
    guard !media.isEmpty else { return }
    requests.append(media)
    onAvailable?()
  }

  func takePending() -> [[URL]] {
    let pending = requests
    requests.removeAll()
    return pending
  }
}

import Cocoa
import XCTest
@testable import offline_player

final class RunnerTests: XCTestCase {
  private let bookmarksKey = "offlinePlayer.localFiles.bookmarks.v1"
  private var savedBookmarks: Any?
  private var temporaryDirectory: URL!
  private var pasteboards: [NSPasteboard] = []
  private var window: MainFlutterWindow!

  override func setUpWithError() throws {
    try super.setUpWithError()
    savedBookmarks = UserDefaults.standard.object(forKey: bookmarksKey)
    temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OfflinePlayerDropTests-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    // Do not call awakeFromNib: these callbacks can be tested without starting
    // Flutter, loading player state, or opening an additional application window.
    window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [], backing: .buffered, defer: false
    )
  }

  override func tearDownWithError() throws {
    window = nil
    for pasteboard in pasteboards { pasteboard.releaseGlobally() }
    pasteboards.removeAll()
    if let savedBookmarks = savedBookmarks {
      UserDefaults.standard.set(savedBookmarks, forKey: bookmarksKey)
    } else {
      UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }
    if let temporaryDirectory = temporaryDirectory {
      try FileManager.default.removeItem(at: temporaryDirectory)
    }
    try super.tearDownWithError()
  }

  func testLocalFilesAcceptCopyLinkAndGenericWithoutMovingSource() throws {
    let file = temporaryDirectory.appendingPathComponent("lesson.mp4")
    let original = Data("local media fixture".utf8)
    try original.write(to: file)
    for operation: NSDragOperation in [.copy, .link, .generic] {
      let dragging = makeDrag(urls: [file], operation: operation)
      XCTAssertEqual(window.draggingEntered(dragging), operation)
      XCTAssertEqual(window.draggingUpdated(dragging), operation)
      XCTAssertTrue(window.prepareForDragOperation(dragging))
      XCTAssertTrue(window.performDragOperation(dragging))
      window.concludeDragOperation(dragging)
      window.draggingEnded(dragging)
      XCTAssertEqual(try Data(contentsOf: file), original)
      try assertStoredBookmark(for: file)
    }
  }

  func testDirectoryDropRetainsReadableNestedFilesAndCreatesBookmark() throws {
    let folder = temporaryDirectory.appendingPathComponent("lessons", isDirectory: true)
    let nested = folder.appendingPathComponent("chapter", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let file = nested.appendingPathComponent("lesson.mkv")
    let original = Data("nested media fixture".utf8)
    try original.write(to: file)
    let dragging = makeDrag(urls: [folder], operation: .copy)
    XCTAssertEqual(window.draggingEntered(dragging), .copy)
    XCTAssertTrue(window.prepareForDragOperation(dragging))
    XCTAssertTrue(window.performDragOperation(dragging))
    try assertStoredBookmark(for: folder)
    XCTAssertEqual(try Data(contentsOf: file), original)
  }

  func testMultipleLocalFileURLsAreAllBookmarked() throws {
    let files = ["first.mp4", "second.mp3"].map { temporaryDirectory.appendingPathComponent($0) }
    for file in files { try Data("fixture".utf8).write(to: file) }
    let dragging = makeDrag(urls: files, operation: [.copy, .move])
    XCTAssertEqual(window.draggingEntered(dragging), .copy)
    XCTAssertTrue(window.prepareForDragOperation(dragging))
    XCTAssertTrue(window.performDragOperation(dragging))
    for file in files {
      try assertStoredBookmark(for: file)
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
  }

  func testRemoteURLsAreRejectedWithoutChangingBookmarks() {
    let before = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    let dragging = makeDrag(urls: [URL(string: "https://example.invalid/lesson.mp4")!], operation: .copy)
    XCTAssertEqual(window.draggingEntered(dragging), [])
    XCTAssertFalse(window.prepareForDragOperation(dragging))
    XCTAssertFalse(window.performDragOperation(dragging))
    XCTAssertEqual(UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:], before)
  }

  func testEmptyPasteboardIsRejected() {
    let dragging = makeDrag(urls: [], operation: .copy)
    XCTAssertEqual(window.draggingEntered(dragging), [])
    XCTAssertEqual(window.draggingUpdated(dragging), [])
    XCTAssertFalse(window.prepareForDragOperation(dragging))
    XCTAssertFalse(window.performDragOperation(dragging))
  }

  func testMoveOnlySourceIsRejectedAndSourceRemainsUntouched() throws {
    let file = temporaryDirectory.appendingPathComponent("leave-in-place.mp4")
    let original = Data("fixture".utf8)
    try original.write(to: file)
    let dragging = makeDrag(urls: [file], operation: .move)
    XCTAssertEqual(window.draggingEntered(dragging), [])
    XCTAssertEqual(window.draggingUpdated(dragging), [])
    // AppKit only invokes performDragOperation after a successful prepare.
    XCTAssertFalse(window.prepareForDragOperation(dragging))
    XCTAssertEqual(try Data(contentsOf: file), original)
  }

  func testHostContentRegistersFileDropAndPreservesFlutterHitTesting() throws {
    let hostWindow = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? MainFlutterWindow }.first {
      $0.contentView?.registeredDraggedTypes.contains(.fileURL) == true
    })
    let contentView = try XCTUnwrap(hostWindow.contentView)
    XCTAssertTrue(contentView.registeredDraggedTypes.contains(.fileURL))
    let flutterView = try XCTUnwrap(contentView.subviews.first)
    XCTAssertFalse(flutterView.translatesAutoresizingMaskIntoConstraints)
    contentView.layoutSubtreeIfNeeded()
    XCTAssertEqual(flutterView.frame, contentView.bounds)
    let pinnedEdges: Set<NSLayoutConstraint.Attribute> = [.leading, .trailing, .top, .bottom]
    let edgeConstraints = contentView.constraints.filter {
      $0.isActive && ($0.firstItem as? NSView) === flutterView
        && ($0.secondItem as? NSView) === contentView
        && pinnedEdges.contains($0.firstAttribute)
        && $0.firstAttribute == $0.secondAttribute
        && $0.relation == .equal && $0.multiplier == 1 && $0.constant == 0
    }
    XCTAssertEqual(Set(edgeConstraints.map(\.firstAttribute)), pinnedEdges)
    let point = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    let hit = try XCTUnwrap(contentView.hitTest(point))
    XCTAssertTrue(hit === flutterView || hit.isDescendant(of: flutterView))
  }

  func testNativeMenuCaptionsTranslateAndRestoreWithoutChangingActionsOrShortcuts() {
    let menus = NativeInterfaceMenus()
    let main = NSMenu(title: "Main Menu")
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu(title: "Edit")
    let cut = NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
    cut.keyEquivalentModifierMask = [.command]
    cut.tag = 42
    edit.submenu?.addItem(cut)
    main.addItem(edit)
    let document = NSMenuItem(title: "Edit", action: NSSelectorFromString("_bringToFront:"), keyEquivalent: "")
    document.target = window
    main.addItem(document)

    for (language, title, actionTitle) in [("zh", "编辑", "剪切"), ("ja", "編集", "カット"), ("en", "Edit", "Cut"), ("zh", "编辑", "剪切")] {
      menus.language = language
      menus.apply(to: main, fullScreen: false, appName: "Study Player")
      XCTAssertEqual(edit.title, title)
      XCTAssertEqual(edit.submenu?.title, title)
      XCTAssertEqual(cut.title, actionTitle)
      XCTAssertEqual(cut.action, NSSelectorFromString("cut:"))
      XCTAssertEqual(cut.keyEquivalent, "x")
      XCTAssertEqual(cut.keyEquivalentModifierMask, [.command])
      XCTAssertEqual(cut.tag, 42)
      XCTAssertEqual(document.title, "Edit")
    }
  }

  func testNativeMenuBrandAndFullscreenStateRemainCorrect() {
    let name = NativeInterfaceMenus.applicationName
    XCTAssertEqual(name, "GoodGoodStudy")
    XCTAssertEqual(NativeInterfaceMenus.title("About APP_NAME", action: "orderFrontStandardAboutPanel:", language: "zh", appName: name), "关于 GoodGoodStudy")
    XCTAssertEqual(NativeInterfaceMenus.title("About APP_NAME", action: "orderFrontStandardAboutPanel:", language: "ja", appName: name), "GoodGoodStudy について")
    XCTAssertEqual(NativeInterfaceMenus.title("Hide APP_NAME", action: "hide:", language: "en", appName: name), "Hide GoodGoodStudy")
    XCTAssertEqual(NativeInterfaceMenus.title("Quit APP_NAME", action: "terminate:", language: "ja", appName: name), "GoodGoodStudy を終了")
    for language in ["zh", "ja", "en"] {
      XCTAssertEqual(NativeInterfaceMenus.title("APP_NAME", language: language, appName: name), name)
    }
    XCTAssertEqual(NativeInterfaceMenus.title("课程.mp4", language: "ja", appName: name), "课程.mp4")

    let menus = NativeInterfaceMenus()
    let view = NSMenu(title: "View")
    let full = NSMenuItem(title: "Enter Full Screen", action: NSSelectorFromString("toggleFullScreen:"), keyEquivalent: "f")
    full.target = window
    full.keyEquivalentModifierMask = [.control, .command]
    view.addItem(full)
    menus.language = "zh"
    menus.apply(to: view, fullScreen: false, appName: name)
    XCTAssertEqual(full.title, "进入全屏幕")
    // AppKit may replace the caption while validating a fullscreen menu item.
    full.title = "Exit Full Screen"
    menus.language = "ja"
    menus.apply(to: view, fullScreen: true, appName: name)
    XCTAssertEqual(full.title, "フルスクリーンを解除")
    menus.language = "en"
    menus.apply(to: view, fullScreen: true, appName: name)
    XCTAssertEqual(full.title, "Exit Full Screen")
    menus.apply(to: view, fullScreen: false, appName: name)
    XCTAssertEqual(full.title, "Enter Full Screen")
    XCTAssertEqual(full.action, NSSelectorFromString("toggleFullScreen:"))
    XCTAssertEqual(full.keyEquivalentModifierMask, [.control, .command])
  }

  private func makeDrag(urls: [URL], operation: NSDragOperation) -> FakeDraggingInfo {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboards.append(pasteboard)
    if !urls.isEmpty { XCTAssertTrue(pasteboard.writeObjects(urls.map { $0 as NSURL })) }
    return FakeDraggingInfo(pasteboard: pasteboard, operation: operation)
  }

  private func assertStoredBookmark(for url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    let data = try XCTUnwrap(bookmarks[url.standardizedFileURL.path], file: file, line: line)
    XCTAssertFalse(data.isEmpty, file: file, line: line)
    var stale = false
    let restored = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
      relativeTo: nil, bookmarkDataIsStale: &stale
    )
    XCTAssertTrue(restored.isFileURL, file: file, line: line)
    XCTAssertEqual(restored.standardizedFileURL.path, url.standardizedFileURL.path, file: file, line: line)
    let didStartAccess = restored.startAccessingSecurityScopedResource()
    defer { if didStartAccess { restored.stopAccessingSecurityScopedResource() } }
    XCTAssertTrue(FileManager.default.isReadableFile(atPath: restored.path), file: file, line: line)
  }
}

private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
  let draggingPasteboard: NSPasteboard
  let draggingSourceOperationMask: NSDragOperation
  var draggingDestinationWindow: NSWindow? { nil }
  var draggingLocation: NSPoint { .zero }
  var draggedImageLocation: NSPoint { .zero }
  var draggedImage: NSImage? { nil }
  var draggingSource: Any? { nil }
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .default
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 0
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }

  init(pasteboard: NSPasteboard, operation: NSDragOperation) {
    draggingPasteboard = pasteboard
    draggingSourceOperationMask = operation
  }

  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func resetSpringLoading() {}
  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}
}

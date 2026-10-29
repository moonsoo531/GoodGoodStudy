import Cocoa
import FlutterMacOS
import QuartzCore

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private let bookmarksKey = "offlinePlayer.localFiles.bookmarks.v1"
  private var localFilesChannel: FlutterMethodChannel?
  private var scopedURLs: [String: URL] = [:]
  private var windowObservers: [NSObjectProtocol] = []
  private var dragActive = false
  private var fullScreenTransitioning = false
  private var pendingFullScreen: Bool?
  private var windowedBackgroundColor: NSColor?
  private let interfaceMenus = NativeInterfaceMenus()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let containerController = NSViewController()
    let dropView = LocalFilesDropView(frame: flutterViewController.view.frame)
    dropView.playerWindow = self
    containerController.view = dropView
    containerController.addChild(flutterViewController)
    let flutterView = flutterViewController.view
    flutterView.translatesAutoresizingMaskIntoConstraints = false
    dropView.addSubview(flutterView)
    NSLayoutConstraint.activate([
      flutterView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
      flutterView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
      flutterView.topAnchor.constraint(equalTo: dropView.topAnchor),
      flutterView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
    ])
    self.contentViewController = containerController
    self.title = NativeInterfaceMenus.applicationName
    self.contentMinSize = NSSize(width: 900, height: 600)
    self.setContentSize(NSSize(width: 1200, height: 800))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    ICloudSyncPlugin.register(with: flutterViewController.registrar(forPlugin: "ICloudSyncPlugin"))
    configureLocalFilesChannel(flutterViewController)
    configureWindowInteractions()

    super.awakeFromNib()
  }

  deinit {
    for observer in windowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    for url in scopedURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func configureLocalFilesChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "offline_player/local_files",
      binaryMessenger: controller.engine.binaryMessenger
    )
    localFilesChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "window_unavailable", message: "The player window is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "setInterfaceLanguage":
        guard let language = (call.arguments as? [String: Any])?["language"] as? String,
              ["zh", "ja", "en"].contains(language) else {
          result(FlutterError(code: "invalid_language", message: "Expected a language code: zh, ja, or en.", details: nil))
          return
        }
        self.interfaceMenus.language = language
        self.applyInterfaceMenuLanguage()
        // The first request can arrive while AppKit is finishing the main nib.
        DispatchQueue.main.async { [weak self] in self?.applyInterfaceMenuLanguage() }
        result(nil)
      case "rememberPaths":
        let mappedPaths = (call.arguments as? [String: Any])?["paths"] as? [String]
        guard let paths = call.arguments as? [String] ?? mappedPaths else {
          result(FlutterError(code: "invalid_paths", message: "Expected a list of local file paths.", details: nil))
          return
        }
        do {
          try self.rememberPaths(paths)
          result(nil)
        } catch {
          result(FlutterError(code: "bookmark_creation_failed", message: "Select the local files or their folder again to retain access.", details: error.localizedDescription))
        }
      case "restorePaths":
        result(self.restorePaths())
      case "getFullScreen":
        result(self.styleMask.contains(.fullScreen))
      case "setFullScreen":
        guard let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool else {
          result(FlutterError(code: "invalid_full_screen", message: "Expected an enabled boolean.", details: nil))
          return
        }
        self.setFullScreen(enabled)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureWindowInteractions() {
    // Retain a window-level fallback in addition to the content's drop target.
    registerForDraggedTypes([.fileURL])
    collectionBehavior.insert(.fullScreenPrimary)
    let notifications = NotificationCenter.default
    for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
      windowObservers.append(notifications.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        guard let self = self else { return }
        self.fullScreenTransitioning = true
        if name == NSWindow.willEnterFullScreenNotification {
          self.windowedBackgroundColor = self.backgroundColor
          self.backgroundColor = .black
        }
      })
    }
    for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
      windowObservers.append(notifications.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        guard let self = self else { return }
        self.fullScreenTransitioning = false
        if name == NSWindow.didExitFullScreenNotification, let color = self.windowedBackgroundColor {
          self.backgroundColor = color
          self.windowedBackgroundColor = nil
        }
        self.localFilesChannel?.invokeMethod("fullScreenChanged", arguments: self.styleMask.contains(.fullScreen))
        self.applyInterfaceMenuLanguage()
        if let enabled = self.pendingFullScreen {
          self.pendingFullScreen = nil
          DispatchQueue.main.async { [weak self] in self?.setFullScreen(enabled) }
        }
      })
    }
    windowObservers.append(notifications.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
      self?.applyInterfaceMenuLanguage()
      // AppKit may validate and rename the fullscreen item while opening it.
      DispatchQueue.main.async { [weak self] in self?.applyInterfaceMenuLanguage() }
    })
  }

  private func applyInterfaceMenuLanguage() {
    interfaceMenus.apply(
      to: NSApp.mainMenu,
      fullScreen: styleMask.contains(.fullScreen),
      appName: NativeInterfaceMenus.applicationName
    )
  }

  private func setFullScreen(_ enabled: Bool) {
    if fullScreenTransitioning {
      pendingFullScreen = enabled
      return
    }
    let actual = styleMask.contains(.fullScreen)
    guard actual != enabled else {
      localFilesChannel?.invokeMethod("fullScreenChanged", arguments: actual)
      return
    }
    toggleFullScreen(nil)
  }

  private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    return urls.filter { $0.isFileURL }
  }

  private func setDragActive(_ active: Bool) {
    guard active != dragActive else { return }
    dragActive = active
    localFilesChannel?.invokeMethod("dragStateChanged", arguments: active)
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let count = droppedURLs(sender).count
    let operation = count == 0 ? [] : acceptedDragOperation(sender)
    setDragActive(!operation.isEmpty)
    NSLog("GoodGoodStudy file drag entered: count=%ld, source=%lu, accepted=%lu", count, sender.draggingSourceOperationMask.rawValue, operation.rawValue)
    return operation
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let operation = droppedURLs(sender).isEmpty ? [] : acceptedDragOperation(sender)
    setDragActive(!operation.isEmpty)
    return operation
  }

  private func acceptedDragOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
    // Never return .move: importing references must leave the source untouched.
    for operation: NSDragOperation in [.copy, .link, .generic] {
      if sender.draggingSourceOperationMask.contains(operation) { return operation }
    }
    return []
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    setDragActive(false)
  }

  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    !droppedURLs(sender).isEmpty && !acceptedDragOperation(sender).isEmpty
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    setDragActive(false)
    let urls = droppedURLs(sender)
    guard !urls.isEmpty else { return false }
    NSLog("GoodGoodStudy file drag dropped: count=%ld", urls.count)
    do {
      // Keep the original pasteboard URLs while creating bookmarks: they carry
      // the sandbox extension granted by Finder for the dropped files/folders.
      for url in urls { retainAccess(to: url) }
      let paths = urls.map { $0.standardizedFileURL.path }
      try rememberPaths(paths)
      localFilesChannel?.invokeMethod("filesDropped", arguments: ["paths": paths])
      NSLog("GoodGoodStudy file drag delivered: count=%ld", paths.count)
      return true
    } catch {
      NSLog("GoodGoodStudy file drag bookmark failed")
      localFilesChannel?.invokeMethod("dropFailed", arguments: "无法读取拖入的文件，请重新拖入或通过打开文件夹选择：\(error.localizedDescription)")
      return false
    }
  }

  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    setDragActive(false)
  }

  func draggingEnded(_ sender: NSDraggingInfo) {
    setDragActive(false)
  }

  private func storedBookmarks() -> [String: Data] {
    UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
  }

  private func rememberPaths(_ paths: [String]) throws {
    var bookmarks = storedBookmarks()
    for path in Set(paths) {
      guard path.hasPrefix("/"), !path.contains("\0") else {
        throw CocoaError(.fileReadUnsupportedScheme)
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      let didStartAccess = retainAccess(to: url)
      do {
        let data = try url.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        bookmarks[url.path] = data
      } catch {
        if didStartAccess {
          scopedURLs.removeValue(forKey: url.path)?.stopAccessingSecurityScopedResource()
        }
        throw error
      }
    }
    UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
  }

  private func restorePaths() -> [String] {
    var bookmarks = storedBookmarks()
    var restoredPaths = Set<String>()
    var changed = false
    for (storedPath, data) in storedBookmarks().sorted(by: { $0.key < $1.key }) {
      var stale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        ).standardizedFileURL
        guard url.isFileURL else { continue }
        retainAccess(to: url)
        guard FileManager.default.isReadableFile(atPath: url.path) else { continue }
        restoredPaths.insert(url.path)
        if stale || storedPath != url.path {
          let refreshedData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          bookmarks.removeValue(forKey: storedPath)
          bookmarks[url.path] = refreshedData
          changed = true
        }
      } catch {
        continue
      }
    }
    if changed {
      UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
    return restoredPaths.sorted()
  }

  @discardableResult
  private func retainAccess(to url: URL) -> Bool {
    guard scopedURLs[url.path] == nil else { return false }
    guard url.startAccessingSecurityScopedResource() else { return false }
    scopedURLs[url.path] = url
    return true
  }
}

// This is an ordinary parent view, not an overlay: mouse, keyboard, focus and
// accessibility hit testing continue normally into the Flutter child view.
private final class LocalFilesDropView: NSView {
  weak var playerWindow: MainFlutterWindow?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.fileURL])
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    playerWindow?.draggingEntered(sender) ?? []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    playerWindow?.draggingUpdated(sender) ?? []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    playerWindow?.draggingExited(sender)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    playerWindow?.prepareForDragOperation(sender) ?? false
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    playerWindow?.performDragOperation(sender) ?? false
  }

  override func concludeDragOperation(_ sender: NSDraggingInfo?) {
    playerWindow?.concludeDragOperation(sender)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    playerWindow?.draggingEnded(sender)
  }
}

/// Localizes application-owned menu captions without replacing menu items,
/// actions, shortcuts, or document/window titles inserted by AppKit.
final class NativeInterfaceMenus {
  static let applicationName = "GoodGoodStudy"
  var language = "zh"
  private let originalItems = NSMapTable<NSMenuItem, NSString>.weakToStrongObjects()
  private let originalMenus = NSMapTable<NSMenu, NSString>.weakToStrongObjects()

  func apply(to menu: NSMenu?, fullScreen: Bool, appName: String) {
    guard let menu = menu else { return }
    let sourceMenu: String
    if let saved = originalMenus.object(forKey: menu) {
      sourceMenu = saved as String
    } else {
      sourceMenu = menu.title
      originalMenus.setObject(sourceMenu as NSString, forKey: menu)
    }
    let menuTitle = Self.title(sourceMenu, language: language, appName: appName, fullScreen: fullScreen)
    if menu.title != menuTitle { menu.title = menuTitle }

    for item in menu.items where !item.isSeparatorItem {
      let action = item.action.map(NSStringFromSelector)
      // Window menu entries may be user filenames such as "Edit" or "Help".
      let windowEntry = ["_bringToFront:", "makeKeyAndOrderFront:", "orderFront:"].contains(action ?? "")
        || (item.target is NSWindow && !Self.windowControlActions.contains(action ?? ""))
      if !windowEntry {
        let source: String
        if let saved = originalItems.object(forKey: item) {
          source = saved as String
        } else {
          source = item.title
          originalItems.setObject(source as NSString, forKey: item)
        }
        let translated = Self.title(source, action: action, language: language, appName: appName, fullScreen: fullScreen)
        if item.title != translated { item.title = translated }
      }
      apply(to: item.submenu, fullScreen: fullScreen, appName: appName)
    }
  }

  /// Pure caption mapping, also used by the independent native tests.
  static func title(
    _ source: String,
    action: String? = nil,
    language: String,
    appName: String,
    fullScreen: Bool = false
  ) -> String {
    let code = ["zh", "ja"].contains(language) ? language : "en"
    if ["_bringToFront:", "makeKeyAndOrderFront:", "orderFront:"].contains(action ?? "") {
      return source
    }
    switch action {
    case "orderFrontStandardAboutPanel:":
      return code == "zh" ? "关于 \(appName)" : code == "ja" ? "\(appName) について" : "About \(appName)"
    case "hide:":
      return code == "zh" ? "隐藏 \(appName)" : code == "ja" ? "\(appName) を非表示" : "Hide \(appName)"
    case "terminate:":
      return code == "zh" ? "退出 \(appName)" : code == "ja" ? "\(appName) を終了" : "Quit \(appName)"
    case "showHelp:":
      return code == "zh" ? "\(appName) 帮助" : code == "ja" ? "\(appName) ヘルプ" : "\(appName) Help"
    case "toggleFullScreen:":
      return caption(fullScreen ? "Exit Full Screen" : "Enter Full Screen", language: code)
    default:
      let value = source.replacingOccurrences(of: "APP_NAME", with: appName)
      return caption(value, language: code)
    }
  }

  private static func caption(_ source: String, language: String) -> String {
    guard language != "en", let variants = captions[source] else { return source }
    return language == "zh" ? variants.0 : variants.1
  }

  private static let windowControlActions: Set<String> = [
    "toggleFullScreen:", "performMiniaturize:", "performZoom:", "arrangeInFront:",
    "toggleToolbarShown:", "runToolbarCustomizationPalette:", "toggleTabBar:", "toggleTabOverview:",
  ]

  private static let captions: [String: (String, String)] = [
    "Main Menu": ("主菜单", "メインメニュー"),
    "Edit": ("编辑", "編集"),
    "View": ("显示", "表示"),
    "Window": ("窗口", "ウインドウ"),
    "Help": ("帮助", "ヘルプ"),
    "Preferences…": ("设置…", "設定…"),
    "Settings…": ("设置…", "設定…"),
    "Services": ("服务", "サービス"),
    "Hide Others": ("隐藏其他", "ほかを非表示"),
    "Show All": ("全部显示", "すべてを表示"),
    "Undo": ("撤销", "取り消す"),
    "Redo": ("重做", "やり直す"),
    "Cut": ("剪切", "カット"),
    "Copy": ("拷贝", "コピー"),
    "Paste": ("粘贴", "ペースト"),
    "Paste and Match Style": ("粘贴并匹配样式", "ペーストしてスタイルを合わせる"),
    "Delete": ("删除", "削除"),
    "Select All": ("全选", "すべてを選択"),
    "Find": ("查找", "検索"),
    "Find…": ("查找…", "検索…"),
    "Find and Replace…": ("查找与替换…", "検索と置換…"),
    "Find Next": ("查找下一个", "次を検索"),
    "Find Previous": ("查找上一个", "前を検索"),
    "Use Selection for Find": ("使用所选内容查找", "選択部分を検索に使用"),
    "Jump to Selection": ("跳到所选内容", "選択部分へ移動"),
    "Spelling and Grammar": ("拼写和语法", "スペルと文法"),
    "Spelling": ("拼写", "スペル"),
    "Show Spelling and Grammar": ("显示拼写和语法", "スペルと文法を表示"),
    "Check Document Now": ("立即检查文稿", "今すぐ書類をチェック"),
    "Check Spelling While Typing": ("键入时检查拼写", "入力中にスペルチェック"),
    "Check Grammar With Spelling": ("检查拼写时检查语法", "スペルと一緒に文法をチェック"),
    "Correct Spelling Automatically": ("自动纠正拼写", "スペルを自動的に修正"),
    "Substitutions": ("替换", "自動置換"),
    "Show Substitutions": ("显示替换", "自動置換を表示"),
    "Smart Copy/Paste": ("智能拷贝/粘贴", "スマートコピー／ペースト"),
    "Smart Quotes": ("智能引号", "スマート引用符"),
    "Smart Dashes": ("智能破折号", "スマートダッシュ"),
    "Smart Links": ("智能链接", "スマートリンク"),
    "Data Detectors": ("数据检测器", "データ検出"),
    "Text Replacement": ("文本替换", "テキスト置換"),
    "Transformations": ("转换", "変換"),
    "Make Upper Case": ("转换为大写", "大文字にする"),
    "Make Lower Case": ("转换为小写", "小文字にする"),
    "Capitalize": ("首字母大写", "単語の先頭を大文字にする"),
    "Speech": ("语音", "スピーチ"),
    "Start Speaking": ("开始朗读", "読み上げを開始"),
    "Stop Speaking": ("停止朗读", "読み上げを停止"),
    "Enter Full Screen": ("进入全屏幕", "フルスクリーンにする"),
    "Exit Full Screen": ("退出全屏幕", "フルスクリーンを解除"),
    "Minimize": ("最小化", "しまう"),
    "Zoom": ("缩放", "拡大／縮小"),
    "Bring All to Front": ("前置全部窗口", "すべてを手前に移動"),
    "Show Toolbar": ("显示工具栏", "ツールバーを表示"),
    "Hide Toolbar": ("隐藏工具栏", "ツールバーを非表示"),
    "Customize Toolbar…": ("自定工具栏…", "ツールバーをカスタマイズ…"),
    "Show Tab Bar": ("显示标签页栏", "タブバーを表示"),
    "Hide Tab Bar": ("隐藏标签页栏", "タブバーを非表示"),
    "Show All Tabs": ("显示所有标签页", "すべてのタブを表示"),
    "Emoji & Symbols": ("表情与符号", "絵文字と記号"),
  ]
}

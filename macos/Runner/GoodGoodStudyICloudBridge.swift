import Foundation
import CryptoKit
#if os(macOS)
import FlutterMacOS
import Security
#else
import Flutter
#endif

/// Transports only this app's immutable sync files. It neither interprets study
/// records nor exposes an iCloud URL to Dart. Merely registering it starts no query.
final class ICloudSyncPlugin: NSObject, FlutterPlugin {
  private struct Failure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
  }

  private struct Availability {
    let configured: Bool
    let reason: String
    let accountID: String?
    let root: URL?
    let identity: NSObjectProtocol?
    var available: Bool { reason == "available" }
    var dictionary: [String: Any] {
      var result: [String: Any] = [
        "supported": true, "configured": configured, "available": available,
        "reason": reason,
      ]
      if let accountID = accountID { result["accountID"] = accountID }
      return result
    }
  }

  private struct Item {
    let name: String
    let url: URL
    let bytes: Int64
    let downloaded: Bool
    let uploading: Bool
    let uploaded: Bool
    let conflicted: Bool
    let transferError: String?
  }

  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "goodgoodstudy.icloud.files", qos: .utility)
  private let fileManager = FileManager.default
  private let lifecycle = NSLock()
  // Access these two properties only while holding lifecycle.
  private var generation = 0
  private var requested = false
  // The query and its observers belong to the main run loop.
  private var query: NSMetadataQuery?
  private var queryObservers: [NSObjectProtocol] = []
  private var identityObserver: NSObjectProtocol?
  // The following properties belong exclusively to worker.
  private var session: Availability?
  private var items: [String: Item] = [:]
  private var pendingUploads: [String: Item] = [:]
  private var gathered = false
  private var issuedDownloads = Set<String>()
  private var cacheRoot: URL?
  private let cacheInstance = UUID().uuidString.lowercased()

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: "goodgoodstudy/icloud", binaryMessenger: messenger)
    let plugin = ICloudSyncPlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    identityObserver = NotificationCenter.default.addObserver(
      forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
    ) { [weak self] _ in self?.identityChanged() }
  }

  deinit {
    if let observer = identityObserver { NotificationCenter.default.removeObserver(observer) }
    for observer in queryObservers { NotificationCenter.default.removeObserver(observer) }
    if let query = query {
      if Thread.isMainThread { query.stop() }
      else { DispatchQueue.main.async { query.stop() } }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { self.handle(call, result: result) }
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    let expectedAccountID = arguments["expectedAccountID"] as? String
    switch call.method {
    case "status":
      perform(result) { _ in self.publicStatus(self.availability()) }
    case "start":
      start(result, expectedAccountID: expectedAccountID)
    case "stop":
      changeLifecycle(running: false, invalidate: true)
      stopQuery()
      worker.async {
        self.session = nil
        self.items.removeAll()
        self.pendingUploads.removeAll()
        self.gathered = false
      }
      finish(result, ["stopped": true])
    case "list":
      perform(result) { stamp in try self.list(stamp, expectedAccountID: expectedAccountID) }
    case "upload":
      guard let name = arguments["name"] as? String,
        let path = arguments["sourcePath"] as? String, Self.validName(name)
      else { finish(result, Failure(code: "invalidArgument", message: "A valid sync filename and sourcePath are required.")); return }
      perform(result) { stamp in try self.upload(name, sourcePath: path, stamp: stamp, expectedAccountID: expectedAccountID) }
    case "download":
      guard let name = arguments["name"] as? String, Self.validName(name)
      else { finish(result, Failure(code: "invalidArgument", message: "A valid sync filename is required.")); return }
      perform(result) { stamp in try self.download(name, stamp: stamp, expectedAccountID: expectedAccountID) }
    case "release":
      guard let path = arguments["path"] as? String
      else { finish(result, Failure(code: "invalidArgument", message: "A bridge download path is required.")); return }
      // A cancelled/old-account operation must still be able to release its local copy.
      worker.async {
        do { self.finish(result, try self.release(path)) }
        catch { self.finish(result, error) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult
  private func changeLifecycle(running: Bool, invalidate: Bool) -> Int {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    if invalidate || requested != running { generation += 1 }
    requested = running
    return generation
  }

  private func stamp() -> Int {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    return generation
  }

  private func isCurrent(_ value: Int, requireRunning: Bool = false) -> Bool {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    return generation == value && (!requireRunning || requested)
  }

  private var isRequested: Bool {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    return requested
  }

  private func perform(_ result: @escaping FlutterResult, body: @escaping (Int) throws -> Any) {
    let current = stamp()
    worker.async {
      do {
        guard self.isCurrent(current) else { throw self.cancelled() }
        let value = try body(current)
        guard self.isCurrent(current) else { throw self.cancelled() }
        self.finish(result, value)
      } catch { self.finish(result, error) }
    }
  }

  private func finish(_ result: @escaping FlutterResult, _ value: Any) {
    let output: Any
    if let failure = value as? Failure {
      output = FlutterError(code: failure.code, message: failure.localizedDescription, details: nil)
    } else if value is Error {
      // NSError descriptions can contain private cloud URLs; never forward them.
      output = FlutterError(code: "unavailable", message: "The iCloud file operation could not be completed. Please try again.", details: nil)
    } else { output = value }
    DispatchQueue.main.async { result(output) }
  }

  private func emit(_ method: String, _ value: Any? = nil) {
    DispatchQueue.main.async { [weak self] in self?.channel.invokeMethod(method, arguments: value) }
  }

  private func cancelled() -> Failure {
    Failure(code: "cancelled", message: "The iCloud session was stopped or its account changed.")
  }

  private static func validName(_ name: String) -> Bool {
    guard !name.isEmpty, name.utf16.count <= 200,
      let range = name.range(of: "^[a-z0-9_-]+\\.(ggsync|ggpack)$", options: .regularExpression)
    else { return false }
    return range == (name.startIndex..<name.endIndex)
  }

  private func availability() -> Availability {
    guard let identifier = Bundle.main.object(forInfoDictionaryKey: "GoodGoodStudyICloudContainerIdentifier") as? String,
      identifier.hasPrefix("iCloud."), identifier.count <= 255,
      identifier.range(of: "^iCloud\\.[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
    else { return Availability(configured: false, reason: "notConfigured", accountID: nil, root: nil, identity: nil) }
    let evidence = signingAllows(identifier)
    if evidence == false {
      return Availability(configured: false, reason: "notConfigured", accountID: nil, root: nil, identity: nil)
    }
    guard let identity = fileManager.ubiquityIdentityToken else {
      return Availability(configured: evidence == true, reason: evidence == true ? "notSignedIn" : "notConfigured", accountID: nil, root: nil, identity: nil)
    }
    guard let archived = try? NSKeyedArchiver.archivedData(withRootObject: identity, requiringSecureCoding: false) else {
      return Availability(configured: evidence == true, reason: "unavailable", accountID: nil, root: nil, identity: nil)
    }
    let accountID = SHA256.hash(data: archived).map { String(format: "%02x", $0) }.joined()
    // Passing nil would silently select a different default container. Never do so.
    guard let container = fileManager.url(forUbiquityContainerIdentifier: identifier) else {
      return Availability(configured: evidence == true, reason: evidence == true ? "unavailable" : "notConfigured", accountID: accountID, root: nil, identity: identity)
    }
    let root = container.appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("GoodGoodStudySync", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true).standardizedFileURL
    return Availability(configured: true, reason: "available", accountID: accountID, root: root, identity: identity)
  }

  private func signingAllows(_ identifier: String) -> Bool? {
    #if os(macOS)
    // Entitlements can also be embedded in an ad-hoc signature. Require a valid
    // certificate signature and its Team identity before claiming configuration.
    var code: SecCode?
    var staticCode: SecStaticCode?
    var requirement: SecRequirement?
    var information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code,
      SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
      let requirement = requirement,
      SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode,
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let values = information as? [String: Any],
      let flags = values[kSecCodeInfoFlags as String] as? NSNumber,
      // kSecCodeSignatureAdhoc is the public Security flag 0x0002.
      flags.uint32Value & 0x0002 == 0,
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
      let task = SecTaskCreateFromSelf(nil),
      let entitledTeam = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String,
      entitledTeam == team
    else { return false }
    let keys = ["com.apple.developer.icloud-container-identifiers", "com.apple.developer.ubiquity-container-identifiers", "com.apple.developer.icloud-services"]
    var entitlements: [String: Any] = [:]
    for key in keys { entitlements[key] = SecTaskCopyValueForEntitlement(task, key as CFString, nil) }
    return Self.entitlementsPermit(entitlements, identifier)
    #else
    // iOS has no public SecTask API. A development/ad-hoc profile proves missing
    // capabilities; App Store installs may omit it and require an explicit URL
    // from FileManager before configured=true is reported.
    guard let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
    do {
      let bytes: Data = try read(profile) { try Data(contentsOf: $0) }
      guard let first = bytes.range(of: Data("<plist".utf8))?.lowerBound,
        let last = bytes.range(of: Data("</plist>".utf8), in: first..<bytes.endIndex)?.upperBound,
        let plist = try PropertyListSerialization.propertyList(from: bytes.subdata(in: first..<last), options: [], format: nil) as? [String: Any],
        let entitlements = plist["Entitlements"] as? [String: Any]
      else { return false }
      return Self.entitlementsPermit(entitlements, identifier)
    } catch { return false }
    #endif
  }

  private static func entitlementsPermit(_ values: [String: Any], _ identifier: String) -> Bool {
    let containers = values["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
    let documents = values["com.apple.developer.ubiquity-container-identifiers"] as? [String] ?? []
    let services = values["com.apple.developer.icloud-services"] as? [String] ?? []
    return containers.contains(identifier) && documents.contains(identifier) && services.contains("CloudDocuments")
  }

  private func publicStatus(_ value: Availability) -> [String: Any] {
    var result = value.dictionary
    result["running"] = isRequested
    result["gathering"] = isRequested && value.available && !gathered
    return result
  }

  private func start(_ result: @escaping FlutterResult, expectedAccountID: String?) {
    let current = changeLifecycle(running: true, invalidate: false)
    worker.async {
      let value = self.availability()
      guard self.isCurrent(current, requireRunning: true) else { self.finish(result, self.cancelled()); return }
      guard value.available, let root = value.root else { self.finish(result, self.publicStatus(value)); return }
      do {
        try self.checkSession(value, stamp: current, expectedAccountID: expectedAccountID)
        try self.write(root, options: .forMerging) { target in
          try self.checkSession(value, stamp: current, expectedAccountID: expectedAccountID)
          guard target.standardizedFileURL.resolvingSymlinksInPath().path == root.standardizedFileURL.resolvingSymlinksInPath().path else { throw self.cancelled() }
          try self.fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        }
      } catch { self.finish(result, error); return }
      self.session = value
      var status = self.publicStatus(value)
      DispatchQueue.main.async {
        guard self.isCurrent(current, requireRunning: true) else { self.finish(result, self.cancelled()); return }
        if let query = self.query {
          status["gathering"] = query.isGathering
          self.finish(result, status)
          return
        }
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 0.5
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Metadata and FileManager URLs may spell the same path differently
        // (for example /var and /private/var on iOS). Filter the canonical exact
        // app directory on worker after discovery instead of in this predicate.
        query.predicate = NSPredicate(
          format: "%K LIKE %@ OR %K LIKE %@",
          NSMetadataItemFSNameKey, "*.ggsync", NSMetadataItemFSNameKey, "*.ggpack"
        )
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        self.query = query
        self.queryObservers = [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate].map { name in
          NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self, weak query] _ in
            guard let self = self, let query = query else { return }
            self.capture(query, root: root, stamp: current)
          }
        }
        guard query.start() else {
          self.stopQuery()
          self.finish(result, Failure(code: "unavailable", message: "The iCloud document index could not be started."))
          return
        }
        status["gathering"] = true
        self.finish(result, status)
      }
    }
  }

  private func stopQuery() {
    query?.stop()
    query = nil
    for observer in queryObservers { NotificationCenter.default.removeObserver(observer) }
    queryObservers.removeAll()
  }

  private func identityChanged() {
    changeLifecycle(running: false, invalidate: true)
    stopQuery()
    // Notify immediately so Dart invalidates in-flight downloads before any old
    // result is delivered. Only local temporary copies may subsequently be released.
    channel.invokeMethod("accountChanged", arguments: nil)
    worker.async {
      self.items.removeAll()
      self.pendingUploads.removeAll()
      self.session = nil
      self.gathered = false
    }
  }

  private func capture(_ query: NSMetadataQuery, root: URL, stamp: Int) {
    guard isCurrent(stamp, requireRunning: true), self.query === query else { return }
    query.disableUpdates()
    var snapshot: [Item] = []
    for index in 0..<query.resultCount {
      guard let item = query.result(at: index) as? NSMetadataItem,
        let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
        let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
        Self.validName(name)
      else { continue }
      let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
      snapshot.append(Item(
        name: name, url: url,
        bytes: max(0, (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0),
        downloaded: status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
        uploading: (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? NSNumber)?.boolValue ?? false,
        uploaded: (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? NSNumber)?.boolValue ?? false,
        conflicted: (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? NSNumber)?.boolValue ?? false,
        transferError: item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) is NSError ? "downloadFailed" : item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) is NSError ? "uploadFailed" : nil
      ))
    }
    let complete = !query.isGathering
    query.enableUpdates()
    worker.async {
      guard self.isCurrent(stamp, requireRunning: true) else { return }
      self.items = Dictionary(snapshot.filter { self.isCloudChild($0.url, root: root, name: $0.name) }.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
      self.gathered = complete
      for item in self.items.values where item.uploaded { self.pendingUploads.removeValue(forKey: item.name) }
      self.emit("changed")
    }
  }

  private func activeSession(_ stamp: Int, expectedAccountID: String?) throws -> Availability {
    guard isCurrent(stamp, requireRunning: true), let value = session, value.available else {
      let value = availability()
      throw Failure(code: value.available ? "notReady" : value.reason, message: "Enable a configured iCloud session before transferring files.")
    }
    try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
    return value
  }

  private func checkSession(_ value: Availability, stamp: Int, expectedAccountID: String?) throws {
    guard let expected = expectedAccountID, !expected.isEmpty, expected == value.accountID,
      let identity = value.identity, let current = fileManager.ubiquityIdentityToken,
      current.isEqual(identity)
    else { throw Failure(code: "accountChanged", message: "The iCloud account changed. Refresh the account binding before syncing.") }
    guard isCurrent(stamp, requireRunning: true) else { throw cancelled() }
  }

  private func list(_ stamp: Int, expectedAccountID: String?) throws -> [String: Any] {
    let value = availability()
    var result = publicStatus(value)
    guard value.available, isRequested, let root = value.root else { result["files"] = [[String: Any]](); return result }
    _ = try activeSession(stamp, expectedAccountID: expectedAccountID)
    let combined = items.merging(pendingUploads) { current, _ in current }
    result["files"] = combined.values.sorted { $0.name < $1.name }.map { item -> [String: Any] in
      var row: [String: Any] = ["name": item.name, "bytes": item.bytes, "downloaded": item.downloaded, "uploading": item.uploading, "uploaded": item.uploaded, "queued": pendingUploads[item.name] != nil]
      if let error = item.transferError { row["error"] = error }
      do {
        var hasConflict = item.conflicted
        if !hasConflict { hasConflict = try conflict(item.url, root: root, name: item.name) }
        if hasConflict { row["error"] = "conflict" }
      } catch { row["error"] = "metadataUnavailable" }
      return row
    }
    _ = try activeSession(stamp, expectedAccountID: expectedAccountID)
    return result
  }

  private func upload(_ name: String, sourcePath: String, stamp: Int, expectedAccountID: String?) throws -> [String: Any] {
    let value = try activeSession(stamp, expectedAccountID: expectedAccountID)
    guard gathered, let root = value.root else { throw Failure(code: "notReady", message: "Wait for the initial iCloud document index.") }
    guard (sourcePath as NSString).isAbsolutePath else { throw Failure(code: "invalidSource", message: "The upload source must be an app-owned local file.") }
    let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let staging = try localCache().appendingPathComponent("upload-" + UUID().uuidString.lowercased())
    defer { try? removeLocal(staging) }
    let bytes: Int64 = try copy(source, to: staging) { original in
      try self.checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      guard self.allowedSource(original) else { throw Failure(code: "invalidSource", message: "The upload source is outside app-owned storage.") }
      let attributes = try self.fileManager.attributesOfItem(atPath: original.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure(code: "invalidSource", message: "Only regular app-owned files may be uploaded.") }
      return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
    let destination = root.appendingPathComponent(name)
    try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
    if let existing = items[name] ?? pendingUploads[name] {
      let hasConflict = try conflict(existing.url, root: root, name: name)
      guard !existing.conflicted, !hasConflict else { throw Failure(code: "conflict", message: "The iCloud file has unresolved versions. No version was replaced.") }
      try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      return ["queued": true, "alreadyExists": true]
    }
    var exists = false
    try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
    try readWrite(staging, to: destination) { staged, target in
      guard let cache = self.cacheRoot, self.isDescendant(staged, of: cache) else { throw self.cancelled() }
      try self.checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      guard self.isCloudChild(target, root: root, name: name) else { throw self.cancelled() }
      if self.fileManager.fileExists(atPath: target.path) {
        guard NSFileVersion.unresolvedConflictVersionsOfItem(at: target)?.isEmpty != false else { throw Failure(code: "conflict", message: "The iCloud file has unresolved versions. No version was replaced.") }
        exists = true
      } else {
        try self.fileManager.copyItem(at: staged, to: target)
      }
    }
    try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
    if !exists {
      pendingUploads[name] = Item(name: name, url: destination, bytes: bytes, downloaded: true, uploading: false, uploaded: false, conflicted: false, transferError: nil)
      emit("changed")
    }
    return ["queued": true, "alreadyExists": exists]
  }

  private func download(_ name: String, stamp: Int, expectedAccountID: String?) throws -> [String: Any] {
    let value = try activeSession(stamp, expectedAccountID: expectedAccountID)
    guard let root = value.root, let item = items[name] ?? pendingUploads[name] else {
      return ["ready": false]
    }
    guard !item.conflicted else { throw Failure(code: "conflict", message: "The iCloud file has unresolved versions. No version was selected.") }
    if !item.downloaded {
      try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      try read(item.url, options: [.withoutChanges, .immediatelyAvailableMetadataOnly]) { url in
        try self.checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
        guard self.isCloudChild(url, root: root, name: name) else { throw self.cancelled() }
        try self.fileManager.startDownloadingUbiquitousItem(at: url)
      }
      return ["ready": false]
    }
    let destination = try localCache().appendingPathComponent("download-" + UUID().uuidString.lowercased() + "." + (name as NSString).pathExtension)
    var copied = false
    do {
      try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      copied = try coordinateCopy(item.url, to: destination) { cloud in
        try self.checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
        guard self.isCloudChild(cloud, root: root, name: name) else { throw self.cancelled() }
        guard NSFileVersion.unresolvedConflictVersionsOfItem(at: cloud)?.isEmpty != false else { throw Failure(code: "conflict", message: "The iCloud file has unresolved versions. No version was selected.") }
        let values = try cloud.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard values.ubiquitousItemDownloadingStatus == .current else {
          try self.fileManager.startDownloadingUbiquitousItem(at: cloud)
          return false
        }
        return true
      }
      try checkSession(value, stamp: stamp, expectedAccountID: expectedAccountID)
      if !copied { return ["ready": false] }
      let path = destination.standardizedFileURL.resolvingSymlinksInPath().path
      issuedDownloads.insert(path)
      return ["ready": true, "path": path]
    } catch {
      try? removeLocal(destination)
      throw error
    }
  }

  private func release(_ path: String) throws -> [String: Any] {
    guard issuedDownloads.contains(path), let root = cacheRoot,
      isDescendant(URL(fileURLWithPath: path), of: root)
    else { throw Failure(code: "invalidArgument", message: "Only a temporary download issued by this bridge may be released.") }
    try removeLocal(URL(fileURLWithPath: path))
    issuedDownloads.remove(path)
    return ["released": true]
  }

  private func conflict(_ url: URL, root: URL, name: String) throws -> Bool {
    try read(url, options: [.withoutChanges, .immediatelyAvailableMetadataOnly]) { coordinated in
      guard self.isCloudChild(coordinated, root: root, name: name) else { throw self.cancelled() }
      return NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinated)?.isEmpty == false
    }
  }

  private func allowedSource(_ url: URL) -> Bool {
    localSourceRoots().contains { isDescendant(url, of: $0) }
  }

  private func localSourceRoots() -> [URL] {
    #if os(macOS)
    guard let identifier = Bundle.main.bundleIdentifier else { return [] }
    var roots: [URL] = []
    if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let owned = support.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(identifier, isDirectory: true)
      if owned.resolvingSymlinksInPath().path == owned.path { roots.append(owned) }
      // Only a real sandbox Documents directory is app-owned on macOS.
      if support.path.contains("/Library/Containers/" + identifier + "/Data/Library/Application Support") {
        roots.append(support)
        roots.append(support.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Documents", isDirectory: true))
      }
    }
    if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
      let owned = caches.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(identifier, isDirectory: true)
      if owned.resolvingSymlinksInPath().path == owned.path { roots.append(owned) }
      if caches.path.contains("/Library/Containers/" + identifier + "/Data/Library/Caches") { roots.append(caches) }
    }
    return roots
    #else
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    return [home.appendingPathComponent("Documents", isDirectory: true), home.appendingPathComponent("Library/Application Support", isDirectory: true), home.appendingPathComponent("Library/Caches", isDirectory: true)].filter { isDescendant($0, of: home) }
    #endif
  }

  private func localCache() throws -> URL {
    if let root = cacheRoot { return root }
    #if os(macOS)
    guard let identifier = Bundle.main.bundleIdentifier,
      let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { throw Failure(code: "unavailable", message: "App cache storage is unavailable.") }
    let baseURL = base.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(identifier, isDirectory: true)
    guard baseURL.resolvingSymlinksInPath().path == baseURL.path else { throw Failure(code: "invalidArgument", message: "App cache storage must not redirect outside its directory.") }
    #else
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    let baseURL = home.appendingPathComponent("Library/Caches", isDirectory: true)
    guard isDescendant(baseURL, of: home) else { throw Failure(code: "invalidArgument", message: "App cache storage is outside its container.") }
    #endif
    let root = baseURL.appendingPathComponent("GoodGoodStudyICloudTransfers", isDirectory: true).appendingPathComponent(cacheInstance, isDirectory: true)
    guard isDescendant(root, of: baseURL) else { throw Failure(code: "invalidArgument", message: "The bridge cache directory is not app-owned.") }
    try ensureDirectory(root)
    cacheRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    return cacheRoot!
  }

  private func isDescendant(_ url: URL, of root: URL) -> Bool {
    let parent = root.standardizedFileURL.resolvingSymlinksInPath().path
    let value = url.standardizedFileURL.resolvingSymlinksInPath().path
    return value.hasPrefix(parent + "/")
  }

  private func isCloudChild(_ url: URL, root: URL, name: String) -> Bool {
    guard Self.validName(name), url.isFileURL, url.lastPathComponent == name
    else { return false }
    let allowed = root.standardizedFileURL.resolvingSymlinksInPath().path
    let candidate = url.standardizedFileURL
    let resolved = candidate.resolvingSymlinksInPath()
    return candidate.deletingLastPathComponent().resolvingSymlinksInPath().path == allowed
      && resolved.deletingLastPathComponent().path == allowed
      && resolved.lastPathComponent == name
  }

  private func ensureDirectory(_ url: URL) throws {
    let expected = url.standardizedFileURL.resolvingSymlinksInPath().path
    try write(url, options: .forMerging) { target in
      guard target.standardizedFileURL.resolvingSymlinksInPath().path == expected else { throw self.cancelled() }
      try self.fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    }
  }

  private func removeLocal(_ url: URL) throws {
    guard let root = cacheRoot, isDescendant(url, of: root) else {
      throw Failure(code: "invalidArgument", message: "The temporary file is outside bridge storage.")
    }
    try write(url, options: .forDeleting) { target in
      guard self.isDescendant(target, of: root) else { throw Failure(code: "invalidArgument", message: "The temporary file is outside bridge storage.") }
      if self.fileManager.fileExists(atPath: target.path) { try self.fileManager.removeItem(at: target) }
    }
  }

  private func read<T>(_ url: URL, options: NSFileCoordinator.ReadingOptions = .withoutChanges, body: (URL) throws -> T) throws -> T {
    var coordinationError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinated in
      result = Result { try body(coordinated) }
    }
    if let error = coordinationError { throw error }
    guard let result = result else { throw Failure(code: "unavailable", message: "The coordinated file read did not complete.") }
    return try result.get()
  }

  private func write<T>(_ url: URL, options: NSFileCoordinator.WritingOptions = [], body: (URL) throws -> T) throws -> T {
    var coordinationError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinated in
      result = Result { try body(coordinated) }
    }
    if let error = coordinationError { throw error }
    guard let result = result else { throw Failure(code: "unavailable", message: "The coordinated file write did not complete.") }
    return try result.get()
  }

  private func copy(_ source: URL, to destination: URL, validate: (URL) throws -> Int64) throws -> Int64 {
    var bytes: Int64 = 0
    _ = try coordinateCopy(source, to: destination) { original in bytes = try validate(original); return true }
    return bytes
  }

  private func coordinateCopy(_ source: URL, to destination: URL, validate: (URL) throws -> Bool) throws -> Bool {
    try readWrite(source, to: destination) { original, target in
      guard let root = self.cacheRoot, self.isDescendant(target, of: root) else {
        throw Failure(code: "invalidArgument", message: "The temporary destination is outside bridge storage.")
      }
      guard try validate(original) else { return false }
      try self.fileManager.copyItem(at: original, to: target)
      return true
    }
  }

  private func readWrite<T>(_ source: URL, to destination: URL, body: (URL, URL) throws -> T) throws -> T {
    var coordinationError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, writingItemAt: destination, options: [], error: &coordinationError) { original, target in
      result = Result { try body(original, target) }
    }
    if let error = coordinationError { throw error }
    guard let result = result else { throw Failure(code: "unavailable", message: "The coordinated file copy did not complete.") }
    return try result.get()
  }
}

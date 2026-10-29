import Foundation
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testFiniteLoopCountsWholePassesAndStopsAtLimit() throws {
    var loop = try IOSAudioLoop(startMs: 1000, endMs: 2000, repeatCount: 2)
    loop.finishPass()
    XCTAssertFalse(loop.completed)
    loop.finishPass()
    XCTAssertTrue(loop.completed)
    loop.finishPass()
    XCTAssertEqual(loop.completedPasses, 2)
  }

  func testInfiniteLoopAndInvalidRanges() throws {
    var loop = try IOSAudioLoop(startMs: 0, endMs: 100, repeatCount: nil)
    for _ in 0..<100 { loop.finishPass() }
    XCTAssertFalse(loop.completed)
    XCTAssertEqual(loop.completedPasses, 100)
    XCTAssertFalse(loop.contains(100))
    XCTAssertThrowsError(try IOSAudioLoop(startMs: 100, endMs: 100, repeatCount: 1))
    XCTAssertThrowsError(try IOSAudioLoop(startMs: 0, endMs: 100, repeatCount: 0))
    XCTAssertThrowsError(try IOSAudioLoop(startMs: 0, endMs: 100, repeatCount: 2, completedPasses: 3))
  }

  func testManualPauseDuringInterruptionPreventsAutomaticResume() {
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    intent.beginInterruption()
    intent.userPause()
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
    XCTAssertFalse(intent.wantsPlayback)
  }

  func testInterruptionNeedsSystemPermissionAndAnUnexpiredDeadline() {
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    intent.beginInterruption()
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: false, deadlinePassed: false))
    intent.userPlay(activating: {})
    intent.beginInterruption()
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: true, deadlinePassed: true))
    intent.userPlay(activating: {})
    intent.beginInterruption()
    XCTAssertTrue(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
  }

  func testInterruptionPreservesIntentAfterSystemHasAlreadyPausedThePlayer() {
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    // No player.rate sample is passed: iOS may have already changed it to zero.
    intent.beginInterruption()
    XCTAssertTrue(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
    intent.userPause()
    intent.beginInterruption()
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
  }

  func testExplicitPlayRecoversWhenBeganHasNoMatchingEndedNotification() {
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    intent.beginInterruption()
    XCTAssertTrue(intent.interrupted)
    var activationAttempts = 0
    intent.userPlay(activating: {
      activationAttempts += 1
    })
    XCTAssertEqual(activationAttempts, 1)
    XCTAssertFalse(intent.interrupted)
    XCTAssertTrue(intent.wantsPlayback)
  }

  func testFailedExplicitActivationPreservesPriorInterruptionAndResumeIntent() {
    enum ActivationFailure: Error { case denied }
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    intent.beginInterruption()
    XCTAssertThrowsError(try intent.userPlay(activating: { throw ActivationFailure.denied }))
    XCTAssertTrue(intent.interrupted)
    XCTAssertTrue(intent.wantsPlayback)
    XCTAssertTrue(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
  }

  func testFailedExplicitActivationNeverChangesPausedUserIntentIntoPlayback() {
    enum ActivationFailure: Error { case denied }
    var intent = IOSPlaybackIntent()
    intent.beginInterruption()
    XCTAssertThrowsError(try intent.userPlay(activating: { throw ActivationFailure.denied }))
    XCTAssertTrue(intent.interrupted)
    XCTAssertFalse(intent.wantsPlayback)
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: true, deadlinePassed: false))
  }

  func testLateEndedAfterExplicitPlayRetainsNewPlaybackIntent() {
    var intent = IOSPlaybackIntent()
    intent.userPlay(activating: {})
    intent.beginInterruption()
    intent.userPlay(activating: {})
    XCTAssertFalse(intent.interrupted)
    XCTAssertFalse(intent.endInterruption(systemAllowsResume: false, deadlinePassed: false))
    XCTAssertTrue(intent.wantsPlayback)
    XCTAssertFalse(intent.interrupted)
  }

  func testFileValidationRejectsURLsPlaylistsDirectoriesAndSymlinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audio = directory.appendingPathComponent("sample.mp3")
    try Data([0, 1]).write(to: audio)
    XCTAssertEqual(try IOSAudioRules.localFile(audio.path), audio.resolvingSymlinksInPath())
    XCTAssertThrowsError(try IOSAudioRules.localFile("https://example.com/sample.mp3"))
    XCTAssertThrowsError(try IOSAudioRules.localFile(audio.absoluteString))
    XCTAssertThrowsError(try IOSAudioRules.localFile(directory.appendingPathComponent("list.m3u").path))
    let fakeAudioDirectory = directory.appendingPathComponent("directory.mp3")
    try FileManager.default.createDirectory(at: fakeAudioDirectory, withIntermediateDirectories: true)
    XCTAssertThrowsError(try IOSAudioRules.localFile(fakeAudioDirectory.path))
    let link = directory.appendingPathComponent("link.mp3")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: audio)
    XCTAssertThrowsError(try IOSAudioRules.localFile(link.path))
  }

  func testProtectionBoundaryExcludesSiblingDirectoriesAndEscapingSymlinks() {
    let root = URL(fileURLWithPath: "/private/tmp/app/Documents/Media")
    XCTAssertTrue(IOSAudioRules.isImportedCopy(root.appendingPathComponent("a.mp3"), mediaDirectory: root))
    XCTAssertFalse(IOSAudioRules.isImportedCopy(URL(fileURLWithPath: root.path + "Other/a.mp3"), mediaDirectory: root))
    XCTAssertFalse(IOSAudioRules.isImportedCopy(root.appendingPathComponent("../outside.mp3"), mediaDirectory: root))
    XCTAssertFalse(IOSAudioRules.validRate(.nan))
    XCTAssertFalse(IOSAudioRules.validRate(0))
    XCTAssertTrue(IOSAudioRules.validRate(1.5))
    XCTAssertEqual(IOSAudioRules.milliseconds(.nan), 0)
  }

  func testSymlinkedImportDirectoryNeverChangesExternalFileProtection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let documents = directory.appendingPathComponent("Documents")
    let outside = directory.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let media = documents.appendingPathComponent("Media")
    try FileManager.default.createSymbolicLink(at: media, withDestinationURL: outside)
    XCTAssertFalse(IOSAudioRules.isImportedCopy(outside.appendingPathComponent("a.mp3"), mediaDirectory: media))
  }

}

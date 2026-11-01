import XCTest

@testable import Push2TalkCore

final class SingleInstanceLockTests: XCTestCase {
  func testOnlyOneInstanceCanHoldLockAndExitReleasesIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("instance.lock")
    var first: SingleInstanceLock? = SingleInstanceLock()
    let second = SingleInstanceLock()
    XCTAssertTrue(try first!.acquire(at: url))
    XCTAssertTrue(try first!.acquire(at: url))
    XCTAssertFalse(try second.acquire(at: url))
    first = nil
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(try second.acquire(at: url))
    XCTAssertFalse(try SingleInstanceLock().acquire(at: url))
  }

  func testInvalidPathReportsError() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("instance.lock")
    XCTAssertThrowsError(try SingleInstanceLock().acquire(at: url))
  }
}

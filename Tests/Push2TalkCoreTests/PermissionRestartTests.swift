import XCTest
@testable import Push2TalkCore

final class PermissionRestartTests: XCTestCase {
  private let denied = PermissionRestart.Permissions(accessibility: false, posting: false, listening: false)
  private let ready = PermissionRestart.Permissions(accessibility: true, posting: true, listening: false)

  func testAlreadyGrantedAtLaunchDoesNotRestart() {
    var state = PermissionRestart()
    XCTAssertEqual(state.update(ready, idle: true, at: 0), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 10), .none)
  }

  func testGrantShowsNoticeThenRestartsOnceWithoutSeparateListeningPermission() {
    var state = PermissionRestart()
    XCTAssertEqual(state.update(denied, idle: true, at: 0), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 1), .notice)
    XCTAssertEqual(state.update(ready, idle: true, at: 2), .notice)
    XCTAssertEqual(state.update(ready, idle: true, at: 3), .restart)
    XCTAssertEqual(state.update(denied, idle: true, at: 4), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 5), .none)
    // A new process establishes a fresh baseline instead of restarting again.
    var relaunched = PermissionRestart()
    XCTAssertEqual(relaunched.update(ready, idle: true, at: 0), .none)
    XCTAssertEqual(relaunched.update(ready, idle: true, at: 10), .none)
  }

  func testWaitsForRequiredPermissionsAndIdleSession() {
    var state = PermissionRestart()
    _ = state.update(denied, idle: true, at: 0)
    let partial = PermissionRestart.Permissions(accessibility: true, posting: false, listening: true)
    XCTAssertEqual(state.update(partial, idle: true, at: 1), .none)
    XCTAssertEqual(state.update(ready, idle: false, at: 10), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 20), .notice)
    XCTAssertEqual(state.update(ready, idle: false, at: 21), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 30), .notice)
    XCTAssertEqual(state.update(ready, idle: true, at: 32), .restart)
  }

  func testRevocationCancelsCountdown() {
    var state = PermissionRestart()
    _ = state.update(denied, idle: true, at: 0)
    _ = state.update(ready, idle: true, at: 1)
    XCTAssertEqual(state.update(denied, idle: true, at: 3), .none)
    XCTAssertEqual(state.update(ready, idle: true, at: 10), .notice)
    XCTAssertEqual(state.update(ready, idle: true, at: 12), .restart)
  }

  func testAdditionalGrantCoalescesIntoOneRestart() {
    var state = PermissionRestart()
    _ = state.update(denied, idle: true, at: 0)
    _ = state.update(ready, idle: true, at: 1)
    let all = PermissionRestart.Permissions(accessibility: true, posting: true, listening: true)
    XCTAssertEqual(state.update(all, idle: true, at: 2), .notice)
    XCTAssertEqual(state.update(all, idle: true, at: 3), .notice)
    XCTAssertEqual(state.update(all, idle: true, at: 4), .restart)
    XCTAssertEqual(state.update(all, idle: true, at: 10), .none)
  }
}

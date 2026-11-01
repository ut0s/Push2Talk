import XCTest

@testable import Push2TalkCore

final class HoldSessionTests: XCTestCase {
  func testHoldStartsStopsAndSubmitsOnce() {
    var session = HoldSession()
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.1), [])
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    XCTAssertEqual(session.tick(at: 0.3), [])
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 1), [.stop])
    XCTAssertEqual(session.tick(at: 1.7), [])
    XCTAssertEqual(session.tick(at: 1.81), [.enter])
    XCTAssertEqual(session.tick(at: 2), [])
  }

  func testTapDoesNothing() {
    var session = HoldSession()
    session.press(at: 0)
    session.release(at: 0.1)
    XCTAssertEqual(session.tick(at: 1), [])
    XCTAssertEqual(session.phase, .idle)
  }

  func testQuickReleaseAfterStartWaitsForStartup() {
    var session = HoldSession()
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 0.21)
    XCTAssertEqual(session.tick(at: 0.3), [])
    XCTAssertEqual(session.tick(at: 0.86), [.stop])
  }

  func testCancelDuringHoldStopsWithoutEnter() {
    var session = HoldSession()
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    XCTAssertEqual(session.cancel(), [.stop])
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 3), [])
  }

  func testFocusChangeDuringSettleCancelsEnter() {
    var session = HoldSession()
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    session.release(at: 1)
    _ = session.tick(at: 1)
    XCTAssertEqual(session.cancel(), [])
    XCTAssertEqual(session.tick(at: 3), [])
  }

  func testCancelDuringArmingDoesNotStopNativeDictation() {
    var session = HoldSession()
    session.press(at: 0)
    XCTAssertEqual(session.cancel(), [])
    XCTAssertEqual(session.tick(at: 1), [])
  }

  func testRepeatedPressAndReleaseDoNotDuplicateActions() {
    var session = HoldSession()
    session.press(at: 0)
    session.press(at: 0.1)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 1)
    session.release(at: 1.1)
    session.press(at: 1.2)
    XCTAssertEqual(session.tick(at: 1.2), [.stop])
    XCTAssertEqual(session.tick(at: 2.1), [.enter])
  }

  func testWatchdogStopsWithoutSubmitting() {
    var session = HoldSession()
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    XCTAssertEqual(session.tick(at: 61), [.stop])
    session.release(at: 62)
    XCTAssertEqual(session.tick(at: 63), [])
  }

  func testEnterCanBeDisabled() {
    var session = HoldSession()
    session.sendEnter = false
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 1), [.stop])
    XCTAssertEqual(session.tick(at: 2), [])
    XCTAssertEqual(session.phase, .idle)
  }
}

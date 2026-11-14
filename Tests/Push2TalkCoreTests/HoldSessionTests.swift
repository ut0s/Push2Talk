import XCTest

@testable import Push2TalkCore

final class HoldSessionTests: XCTestCase {
  func testLocalRecognitionWaitsForResultBeforeSendingEnter() {
    var session = HoldSession()
    session.waitsForRecognition = true
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 1, shiftHeld: true)
    XCTAssertEqual(session.tick(at: 2), [.stop])
    XCTAssertEqual(session.phase, .recognizing)
    XCTAssertEqual(session.tick(at: 10), [])
    session.finishRecognition(at: 10)
    XCTAssertEqual(session.tick(at: 10.7), [])
    XCTAssertEqual(session.tick(at: 11), [.enter])
  }

  func testCancelledLocalRecognitionCannotResumeSubmission() {
    var session = HoldSession()
    session.waitsForRecognition = true
    session.sendEnter = true
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 2), [.stop])
    _ = session.cancel()
    session.finishRecognition(at: 3)
    XCTAssertEqual(session.tick(at: 4), [])
    XCTAssertEqual(session.phase, .idle)
  }

  func testReleaseKeepsDictationRunningBeforeStopThenWaitsBeforeEnter() {
    var session = HoldSession()
    session.sendEnter = true
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 2)
    session.release(at: 2.4)
    XCTAssertEqual(session.tick(at: 2), [])
    XCTAssertEqual(session.tick(at: 2.79), [])
    XCTAssertEqual(session.tick(at: 2.81), [.stop])
    XCTAssertEqual(session.tick(at: 3.5), [])
    XCTAssertEqual(session.tick(at: 3.62), [.enter])
    XCTAssertEqual(session.tick(at: 4), [])
  }

  func testLongerReleaseDelayAndCancellationDuringGrace() {
    var session = HoldSession()
    session.releaseDelay = 2
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 1, shiftHeld: true)
    XCTAssertEqual(session.tick(at: 2.9), [])
    XCTAssertEqual(session.cancel(), [.stop])
    XCTAssertEqual(session.tick(at: 4), [])
    XCTAssertEqual(session.phase, .idle)
  }

  func testQuickReleaseAlsoGetsReleaseGrace() {
    var session = HoldSession()
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 0.21)
    XCTAssertEqual(session.tick(at: 0.86), [])
    XCTAssertEqual(session.tick(at: 1.02), [.stop])
  }

  func testShiftAtReleaseInvertsDefaultForOneSessionOnly() {
    for defaultEnter in [false, true] {
      var session = HoldSession()
      session.releaseDelay = 0
      session.sendEnter = defaultEnter
      session.press(at: 0)
      XCTAssertEqual(session.tick(at: 0.2), [.start])
      session.release(at: 1, shiftHeld: true)
      // Repeated release events cannot overwrite the captured choice.
      session.release(at: 1.1, shiftHeld: false)
      XCTAssertEqual(session.tick(at: 1.1), [.stop])
      XCTAssertEqual(session.tick(at: 2), defaultEnter ? [] : [.enter])
      XCTAssertEqual(session.tick(at: 2.1), [])
      XCTAssertEqual(session.sendEnter, defaultEnter)

      session.press(at: 3)
      XCTAssertEqual(session.tick(at: 3.2), [.start])
      session.release(at: 4)
      XCTAssertEqual(session.tick(at: 4), [.stop])
      XCTAssertEqual(session.tick(at: 5), defaultEnter ? [.enter] : [])
    }
  }

  func testShiftDoesNotSubmitAfterTapCancellationOrTimeout() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.press(at: 0)
    session.release(at: 0.1, shiftHeld: true)
    XCTAssertEqual(session.tick(at: 1), [])

    session.press(at: 2)
    XCTAssertEqual(session.tick(at: 2.2), [.start])
    session.release(at: 3, shiftHeld: true)
    XCTAssertEqual(session.tick(at: 3), [.stop])
    XCTAssertEqual(session.cancel(), [])
    XCTAssertEqual(session.tick(at: 4), [])

    session.press(at: 5)
    XCTAssertEqual(session.tick(at: 5.2), [.start])
    XCTAssertEqual(session.tick(at: 66), [.stop])
    session.release(at: 67, shiftHeld: true)
    XCTAssertEqual(session.tick(at: 68), [])
  }

  func testHoldStartsStopsAndSubmitsOnce() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.sendEnter = true
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
    session.releaseDelay = 0
    session.press(at: 0)
    session.release(at: 0.1)
    XCTAssertEqual(session.tick(at: 1), [])
    XCTAssertEqual(session.phase, .idle)
  }

  func testQuickReleaseAfterStartWaitsForStartup() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.press(at: 0)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    session.release(at: 0.21)
    XCTAssertEqual(session.tick(at: 0.3), [])
    XCTAssertEqual(session.tick(at: 0.86), [.stop])
  }

  func testCancelDuringHoldStopsWithoutEnter() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.sendEnter = true
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    XCTAssertEqual(session.cancel(), [.stop])
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 3), [])
  }

  func testFocusChangeDuringSettleCancelsEnter() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.sendEnter = true
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    session.release(at: 1)
    _ = session.tick(at: 1)
    XCTAssertEqual(session.cancel(), [])
    XCTAssertEqual(session.tick(at: 3), [])
  }

  func testCancelDuringArmingDoesNotStopNativeDictation() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.press(at: 0)
    XCTAssertEqual(session.cancel(), [])
    XCTAssertEqual(session.tick(at: 1), [])
  }

  func testRepeatedPressAndReleaseDoNotDuplicateActions() {
    var session = HoldSession()
    session.releaseDelay = 0
    session.sendEnter = true
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
    session.releaseDelay = 0
    session.sendEnter = true
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    XCTAssertEqual(session.tick(at: 61), [.stop])
    session.release(at: 62)
    XCTAssertEqual(session.tick(at: 63), [])
  }

  func testEnterIsDisabledByDefault() {
    var session = HoldSession()
    session.releaseDelay = 0
    XCTAssertFalse(session.sendEnter)
    session.press(at: 0)
    _ = session.tick(at: 0.2)
    session.release(at: 1)
    XCTAssertEqual(session.tick(at: 1), [.stop])
    XCTAssertEqual(session.tick(at: 2), [])
    XCTAssertEqual(session.phase, .idle)
  }
}

import XCTest
@testable import Push2TalkCore

final class RightOptionStateTests: XCTestCase {
  private let option: UInt64 = 1 << 19

  func testDeviceSpecificPressReleaseAndDuplicate() {
    var state = RightOptionState()
    XCTAssertEqual(state.update(keyCode: 61, flags: option | 0x40), true)
    XCTAssertNil(state.update(keyCode: 61, flags: option | 0x40))
    XCTAssertEqual(state.update(keyCode: 61, flags: 0), false)
    XCTAssertNil(state.update(keyCode: 61, flags: 0))
  }

  func testAggregateOnlyEventsStartAndRelease() {
    var state = RightOptionState()
    XCTAssertEqual(state.update(keyCode: 61, flags: option), true)
    XCTAssertTrue(state.isHeld)
    XCTAssertEqual(state.update(keyCode: 61, flags: 0), false)
  }

  func testLeftOptionDoesNotTriggerOrReleaseRightOption() {
    var state = RightOptionState()
    XCTAssertNil(state.update(keyCode: 58, flags: option | 0x20))
    XCTAssertEqual(state.update(keyCode: 61, flags: option | 0x60), true)
    XCTAssertNil(state.update(keyCode: 58, flags: option | 0x40))
    XCTAssertTrue(state.isHeld)
    XCTAssertEqual(state.update(keyCode: 61, flags: option | 0x20), false)
  }

  func testAggregateReleaseWhileLeftOptionRemainsHeld() {
    var state = RightOptionState()
    XCTAssertEqual(state.update(keyCode: 61, flags: option), true)
    XCTAssertEqual(state.update(keyCode: 61, flags: option), false)
  }

  func testResetAfterTapStopsAllowsNextPress() {
    var state = RightOptionState()
    _ = state.update(keyCode: 61, flags: option)
    state.reset()
    XCTAssertFalse(state.isHeld)
    XCTAssertEqual(state.update(keyCode: 61, flags: option), true)
  }
}

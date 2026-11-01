import CoreGraphics
import XCTest
@testable import Push2TalkInput

final class KeyboardBridgeTests: XCTestCase {
  private func event(key: CGKeyCode, flags: CGEventFlags = []) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
    event.flags = flags
    return event
  }

  @MainActor
  func testOrdinaryKeysReturnImmediatelyBeforeCancelCallbackRuns() async {
    let bridge = KeyboardBridge()
    var called = false
    bridge.onCancel = { _ in called = true }
    for key in CGKeyCode(0)...127 {
      for type in [CGEventType.keyDown, .keyUp] {
        let input = event(key: key)
        let output = bridge.handle(type, input)?.takeUnretainedValue()
        XCTAssertTrue(output === input)
        XCTAssertEqual(output?.flags, [])
        XCTAssertFalse(called, "No application callback may block the event tap")
      }
    }
    // Invalidate queued work so this test does not leave callbacks behind.
    bridge.stop()
    await Task.yield()
    XCTAssertFalse(called)
  }

  @MainActor
  func testHoldCallbacksAreDeferredAndKeepPressReleaseOrder() async {
    let bridge = KeyboardBridge()
    let delivered = expectation(description: "Press and release delivered")
    delivered.expectedFulfillmentCount = 2
    var transitions: [Bool] = []
    bridge.onHold = { down in
      XCTAssertTrue(Thread.isMainThread)
      transitions.append(down)
      delivered.fulfill()
    }
    XCTAssertNil(bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80040))))
    XCTAssertTrue(bridge.isRightOptionHeld)
    XCTAssertNil(bridge.handle(.flagsChanged, event(key: 61)))
    XCTAssertFalse(bridge.isRightOptionHeld)
    XCTAssertTrue(transitions.isEmpty)
    await fulfillment(of: [delivered], timeout: 1)
    XCTAssertEqual(transitions, [true, false])
  }

  @MainActor
  func testLeftOptionAndNormalTypingAreNeverSwallowed() async {
    let bridge = KeyboardBridge()
    let input = event(key: 58, flags: CGEventFlags(rawValue: 0x80020))
    XCTAssertTrue(bridge.handle(.flagsChanged, input)?.takeUnretainedValue() === input)
    XCTAssertFalse(bridge.isRightOptionHeld)
    XCTAssertTrue(bridge.optionEventStatus.contains("左Option"))
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80040)))
    let typing = event(key: 0, flags: CGEventFlags(rawValue: 0x80040))
    XCTAssertTrue(bridge.handle(.keyDown, typing)?.takeUnretainedValue() === typing)
    XCTAssertFalse(typing.flags.contains(.maskAlternate))
    bridge.stop()
  }

  @MainActor
  func testStoppedBridgeDiscardsPendingHoldAndCancelCallbacks() async {
    let bridge = KeyboardBridge()
    var called = false
    bridge.onHold = { _ in called = true }
    bridge.onCancel = { _ in called = true }
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80040)))
    _ = bridge.handle(.keyDown, event(key: 0))
    bridge.stop()
    let drained = expectation(description: "Main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    await fulfillment(of: [drained], timeout: 1)
    XCTAssertFalse(called)
    XCTAssertFalse(bridge.isRightOptionHeld)
  }

  @MainActor
  func testClickPassesThroughAndCancelsWithoutSendingEscape() async {
    let bridge = KeyboardBridge()
    let delivered = expectation(description: "Click cancellation delivered")
    var called = false
    bridge.onCancel = { suppressEscape in
      XCTAssertTrue(suppressEscape)
      called = true
      delivered.fulfill()
    }
    let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
    XCTAssertTrue(bridge.handle(.leftMouseDown, click)?.takeUnretainedValue() === click)
    XCTAssertFalse(called)
    await fulfillment(of: [delivered], timeout: 1)
  }

  @MainActor
  func testGeneratedEventsDoNotReenterHoldOrCancellation() {
    let bridge = KeyboardBridge()
    let input = event(key: 61, flags: CGEventFlags(rawValue: 0x80040))
    input.setIntegerValueField(.eventSourceUserData, value: KeyboardBridge.marker)
    XCTAssertTrue(bridge.handle(.flagsChanged, input)?.takeUnretainedValue() === input)
    XCTAssertFalse(bridge.isRightOptionHeld)
    XCTAssertTrue(bridge.optionEventStatus.contains("未確認"))
  }
}

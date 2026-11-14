import AppKit
import Carbon
import CoreGraphics
import Push2TalkCore
import XCTest
@testable import Push2TalkInput

final class KeyboardBridgeTests: XCTestCase {
  func testPasteEventsOnlySendCommandV() throws {
    let events = try XCTUnwrap(KeyboardBridge.pasteEvents())
    XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
    for event in events {
      XCTAssertEqual(event.flags, .maskCommand)
      XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_ANSI_V))
      XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), KeyboardBridge.marker)
    }
  }

  func testPasteboardSnapshotPreservesAllItemsAndRepresentations() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let first = NSPasteboardItem()
    first.setString("声😀", forType: .string)
    let customType = NSPasteboard.PasteboardType("com.ut0s.push2talk.test")
    first.setData(Data([2, 4, 8]), forType: customType)
    let second = NSPasteboardItem()
    second.setString("second item", forType: .string)
    XCTAssertTrue(pasteboard.writeObjects([first, second]))
    let snapshots = try XCTUnwrap(KeyboardBridge.copyPasteboardItems(pasteboard))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects(snapshots))
    XCTAssertEqual(pasteboard.pasteboardItems?.map { $0.string(forType: .string) }, ["声😀", "second item"])
    XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: customType), Data([2, 4, 8]))
  }

  @MainActor
  func testSystemPollingKeepsSessionRecordingWhenShortcutClearsOptionFlags() async {
    for physicalKey in [CGKeyCode(58), CGKeyCode(61)] {
      var keys: Set<CGKeyCode> = [physicalKey]
      var flags = CGEventFlags(rawValue: 0x80140)
      let bridge = KeyboardBridge(stateSource: KeyboardStateSource(
        keyState: { keys.contains($0) }, flagsState: { flags }))
      var session = HoldSession()
      let pressed = expectation(description: "Press delivered")
      let released = expectation(description: "Physical release delivered")
      var transitions: [Bool] = []
      bridge.onHold = { down, shiftHeld in
        transitions.append(down)
        if down {
          session.press(at: 0)
          pressed.fulfill()
        } else {
          session.release(at: 3.25, shiftHeld: shiftHeld)
          released.fulfill()
        }
      }
      _ = bridge.handle(.flagsChanged, event(key: 61, flags: flags))
      // Exercise the public polling entry point, including its OS-state adapter.
      bridge.reconcileHoldState()
      await fulfillment(of: [pressed], timeout: 1)
      XCTAssertEqual(session.tick(at: 0.2), [.start])
      for tick in 1...120 {
        // Recorded trace: posted Command presses/releases erase Option flags,
        // while the physical key remains held throughout the three seconds.
        flags = CGEventFlags(rawValue: tick % 2 == 0 ? 0x20000000 : 0x20100010)
        bridge.reconcileHoldState()
        XCTAssertTrue(bridge.isRightOptionHeld)
        XCTAssertEqual(session.tick(at: 0.2 + Double(tick) * 0.025), [])
      }
      XCTAssertEqual(transitions, [true])
      XCTAssertEqual(session.phase, .recording(0.2))
      // Recover a missing native release and preserve Shift's Enter override.
      keys.removeAll()
      flags = .maskShift
      bridge.reconcileHoldState()
      await fulfillment(of: [released], timeout: 1)
      XCTAssertEqual(transitions, [true, false])
      XCTAssertFalse(bridge.isRightOptionHeld)
      XCTAssertEqual(session.tick(at: 3.25), [])
      XCTAssertEqual(session.tick(at: 4.06), [.stop])
      XCTAssertEqual(session.tick(at: 4.87), [.enter])
      bridge.stop()
    }
  }

  @MainActor
  func testLostReleaseStopsSessionOnceAndPreservesShiftChoice() async {
    let bridge = KeyboardBridge()
    var session = HoldSession()
    let pressed = expectation(description: "Press delivered")
    let released = expectation(description: "Recovered release delivered")
    var transitions: [Bool] = []
    bridge.onHold = { down, shiftHeld in
      transitions.append(down)
      if down {
        session.press(at: 0)
        pressed.fulfill()
      } else {
        session.release(at: 1, shiftHeld: shiftHeld)
        released.fulfill()
      }
    }
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80040)))
    await fulfillment(of: [pressed], timeout: 1)
    XCTAssertEqual(session.tick(at: 0.2), [.start])
    bridge.reconcileHoldState(rightOptionDown: true, shiftHeld: false)
    XCTAssertTrue(bridge.isRightOptionHeld)
    // No flagsChanged release arrives; the physical key check recovers it.
    bridge.reconcileHoldState(rightOptionDown: false, shiftHeld: true)
    bridge.reconcileHoldState(rightOptionDown: false, shiftHeld: false)
    XCTAssertFalse(bridge.isRightOptionHeld)
    await fulfillment(of: [released], timeout: 1)
    XCTAssertEqual(transitions, [true, false])
    XCTAssertEqual(session.tick(at: 1), [])
    XCTAssertEqual(session.tick(at: 1.81), [.stop])
    XCTAssertEqual(session.tick(at: 2.62), [.enter])
    // A delayed native release must not deliver another transition.
    _ = bridge.handle(.flagsChanged, event(key: 61))
    let drained = expectation(description: "Late release processed")
    DispatchQueue.main.async { drained.fulfill() }
    await fulfillment(of: [drained], timeout: 1)
    XCTAssertEqual(transitions, [true, false])
    bridge.stop()
  }

  @MainActor
  func testReconciliationNeverSynthesizesAPressAndStopDiscardsRecovery() async {
    let bridge = KeyboardBridge()
    var called = false
    bridge.onHold = { _, _ in called = true }
    bridge.reconcileHoldState(rightOptionDown: true, shiftHeld: false)
    XCTAssertFalse(bridge.isRightOptionHeld)
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskAlternate))
    bridge.reconcileHoldState(rightOptionDown: true, shiftHeld: false)
    bridge.reconcileHoldState(rightOptionDown: false, shiftHeld: false)
    bridge.stop()
    let drained = expectation(description: "Main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    await fulfillment(of: [drained], timeout: 1)
    XCTAssertFalse(called)
  }

  @MainActor
  func testMappedLeftOptionSurvivesSyntheticShortcutAndRecoversMissingRelease() async {
    let bridge = KeyboardBridge()
    let pressed = expectation(description: "Mapped press delivered")
    let released = expectation(description: "Recovered release delivered")
    var transitions: [Bool] = []
    bridge.onHold = { down, _ in
      transitions.append(down)
      if down { pressed.fulfill() } else { released.fulfill() }
    }
    // Real-device trace: logical right Option, physical key 58, then HID flags
    // become 0x20000000 when the Dictation shortcut is posted.
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80140)))
    bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: true, shiftHeld: false)
    await fulfillment(of: [pressed], timeout: 1)
    let shortcut = event(key: 54, flags: CGEventFlags(rawValue: 0x20100010))
    shortcut.setIntegerValueField(.eventSourceUserData, value: KeyboardBridge.marker)
    _ = bridge.handle(.flagsChanged, shortcut)
    let shortcutRelease = event(key: 54, flags: CGEventFlags(rawValue: 0x20000000))
    shortcutRelease.setIntegerValueField(.eventSourceUserData, value: KeyboardBridge.marker)
    _ = bridge.handle(.flagsChanged, shortcutRelease)
    for _ in 0..<120 {
      bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: true, shiftHeld: false)
    }
    XCTAssertTrue(bridge.isRightOptionHeld)
    XCTAssertEqual(transitions, [true])
    bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: false, shiftHeld: false)
    XCTAssertFalse(bridge.isRightOptionHeld)
    await fulfillment(of: [released], timeout: 1)
    XCTAssertEqual(transitions, [true, false])
    bridge.stop()
  }

  @MainActor
  func testPhysicalRightReleaseIsRecoveredWhileLeftOptionRemainsDown() async {
    let bridge = KeyboardBridge()
    let released = expectation(description: "Right key release delivered")
    bridge.onHold = { down, _ in if !down { released.fulfill() } }
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: CGEventFlags(rawValue: 0x80040)))
    bridge.reconcileHoldState(rightOptionDown: true, leftOptionDown: false, shiftHeld: false)
    bridge.reconcileHoldState(rightOptionDown: true, leftOptionDown: true, shiftHeld: false)
    XCTAssertTrue(bridge.isRightOptionHeld)
    bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: true, shiftHeld: false)
    XCTAssertFalse(bridge.isRightOptionHeld)
    await fulfillment(of: [released], timeout: 1)
    bridge.stop()
  }

  @MainActor
  func testUnknownPhysicalMappingWaitsForNativeRelease() async {
    for bothDown in [false, true] {
      let bridge = KeyboardBridge()
      let released = expectation(description: "Native release delivered")
      bridge.onHold = { down, _ in if !down { released.fulfill() } }
      _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskAlternate))
      bridge.reconcileHoldState(rightOptionDown: bothDown, leftOptionDown: bothDown, shiftHeld: false)
      bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: false, shiftHeld: false)
      XCTAssertTrue(bridge.isRightOptionHeld)
      _ = bridge.handle(.flagsChanged, event(key: 61))
      await fulfillment(of: [released], timeout: 1)
      XCTAssertFalse(bridge.isRightOptionHeld)
      bridge.stop()
    }
  }

  @MainActor
  func testPhysicalMappingIsRecalibratedForEachPress() async {
    let bridge = KeyboardBridge()
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskAlternate))
    bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: true, shiftHeld: false)
    _ = bridge.handle(.flagsChanged, event(key: 61))
    _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskAlternate))
    bridge.reconcileHoldState(rightOptionDown: true, leftOptionDown: false, shiftHeld: false)
    bridge.reconcileHoldState(rightOptionDown: true, leftOptionDown: false, shiftHeld: false)
    XCTAssertTrue(bridge.isRightOptionHeld)
    bridge.reconcileHoldState(rightOptionDown: false, leftOptionDown: false, shiftHeld: false)
    XCTAssertFalse(bridge.isRightOptionHeld)
    bridge.stop()
  }

  @MainActor
  func testEitherShiftPassesThroughWithoutCancellingAndIsCapturedAtRelease() async {
    for shiftKey in [CGKeyCode(56), CGKeyCode(60)] {
      let bridge = KeyboardBridge()
      let delivered = expectation(description: "Hold transitions with Shift captured")
      delivered.expectedFulfillmentCount = 2
      var shifts: [Bool] = []
      var cancelled = false
      bridge.onCancel = { _ in cancelled = true }
      bridge.onHold = { _, shiftHeld in
        shifts.append(shiftHeld)
        delivered.fulfill()
      }
      _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskAlternate))
      let shiftDown = event(key: shiftKey, flags: [.maskShift, .maskAlternate])
      XCTAssertTrue(bridge.handle(.flagsChanged, shiftDown)?.takeUnretainedValue() === shiftDown)
      XCTAssertTrue(shiftDown.flags.contains(.maskShift))
      _ = bridge.handle(.flagsChanged, event(key: 61, flags: .maskShift))
      // Release Shift before the main queue processes the Option release.
      let shiftUp = event(key: shiftKey)
      XCTAssertTrue(bridge.handle(.flagsChanged, shiftUp)?.takeUnretainedValue() === shiftUp)
      await fulfillment(of: [delivered], timeout: 1)
      XCTAssertEqual(shifts, [false, true])
      XCTAssertFalse(cancelled)
      bridge.stop()
    }
  }

  @MainActor
  func testOtherModifiersStillCancel() async {
    let bridge = KeyboardBridge()
    let delivered = expectation(description: "Command cancels")
    bridge.onCancel = { _ in delivered.fulfill() }
    let command = event(key: 55, flags: .maskCommand)
    XCTAssertTrue(bridge.handle(.flagsChanged, command)?.takeUnretainedValue() === command)
    await fulfillment(of: [delivered], timeout: 1)
    bridge.stop()
  }

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
    bridge.onHold = { down, _ in
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
    XCTAssertTrue(bridge.optionEventStatus.contains(L10n.text("左Option")))
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
    bridge.onHold = { _, _ in called = true }
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
    XCTAssertEqual(bridge.optionEventStatus, L10n.text("Optionキーの受信: 未確認（右Optionを押して確認）"))
  }
}

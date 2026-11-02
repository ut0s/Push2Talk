import AppKit
import ApplicationServices
import Carbon
import Push2TalkCore

public final class KeyboardBridge {
  public init() {}
  static let marker: Int64 = 0x5032_5441_4C4B
  public var onHold: ((_ down: Bool, _ shiftHeld: Bool) -> Void)?
  public var onCancel: ((Bool) -> Void)?
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var optionState = RightOptionState()
  private var lastOptionEvent: (code: Int64, flags: UInt64)?
  private let stateLock = NSLock()
  private var eventThread: Thread?
  private var eventRunLoop: CFRunLoop?
  private var generation = 0
  private var nextPostTime = ProcessInfo.processInfo.systemUptime

  public var isRightOptionHeld: Bool { stateLock.withLock { optionState.isHeld } }
  public var optionEventStatus: String {
    guard let event = stateLock.withLock({ lastOptionEvent }) else {
      return L10n.text("Optionキーの受信: 未確認（右Optionを押して確認）")
    }
    let side = L10n.text(event.code == 61 ? "右Option" : "左Option")
    return L10n.format("直近の受信: %@ / flags=0x%@", side, String(event.flags, radix: 16))
  }
  public var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

  public func reconcileHoldState() {
    guard isRightOptionHeld else { return }
    let flags = CGEventSource.flagsState(.hidSystemState)
    let altHeld = flags.contains(.maskAlternate)
    let key61Down = CGEventSource.keyState(.hidSystemState, key: 61)
    let rightOptionDown = altHeld && (key61Down || (flags.rawValue & 0x40 != 0) || (flags.rawValue & 0x60 == 0))
    reconcileHoldState(
      rightOptionDown: rightOptionDown,
      shiftHeld: flags.contains(.maskShift))
  }

  func reconcileHoldState(rightOptionDown: Bool, shiftHeld: Bool) {
    // Recover a lost release without synthesizing presses or relying on the
    // aggregate Option flag, which may still be set by the left Option key.
    guard !rightOptionDown else { return }
    let released = stateLock.withLock {
      optionState.update(keyCode: 61, flags: 0) == false
    }
    if released { deliver { $0.onHold?(false, shiftHeld) } }
  }

  public var isRunning: Bool {
    guard let tap else { return false }
    return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
  }

  public func start() -> Bool {
    if isRunning { return true }
    if tap != nil { stop() }
    let mask =
      (1 << CGEventType.flagsChanged.rawValue)
      | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, pointer in
      guard let pointer else { return Unmanaged.passUnretained(event) }
      return Unmanaged<KeyboardBridge>.fromOpaque(pointer).takeUnretainedValue().handle(type, event)
    }
    guard
      let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(mask), callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else { return false }
    CGEvent.tapEnable(tap: newTap, enable: false)
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
      CFMachPortInvalidate(newTap)
      return false
    }
    tap = newTap
    runLoopSource = source
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread { [self] in
      let loop = CFRunLoopGetCurrent()
      stateLock.withLock { eventRunLoop = loop }
      CFRunLoopAddSource(loop, source, .commonModes)
      CGEvent.tapEnable(tap: newTap, enable: true)
      ready.signal()
      CFRunLoopRun()
      CFRunLoopRemoveSource(loop, source, .commonModes)
    }
    thread.name = "Push2Talk keyboard events"
    thread.qualityOfService = .userInteractive
    eventThread = thread
    thread.start()
    ready.wait()
    return isRunning
  }

  public func stop() {
    let loop = stateLock.withLock { () -> CFRunLoop? in
      generation += 1
      optionState.reset()
      let loop = eventRunLoop
      eventRunLoop = nil
      return loop
    }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let loop {
      CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
      CFRunLoopWakeUp(loop)
    }
    tap = nil
    runLoopSource = nil
    eventThread = nil
  }

  // This runs on the event thread. Never call AX, TCC, AppKit, or user callbacks here.
  func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      stateLock.withLock { optionState.reset() }
      deliver { bridge in
        bridge.onCancel?(false)
        if let tap = bridge.tap { CGEvent.tapEnable(tap: tap, enable: true) }
      }
      return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else {
      return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseDown || type == .rightMouseDown {
      // A click may change controls even when AX focus information is unavailable.
      // Pass it through and cancel submission without sending Escape into the new control.
      deliver { $0.onCancel?(true) }
      return Unmanaged.passUnretained(event)
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if type == .flagsChanged && (code == 58 || code == 61) {
      stateLock.withLock {
        lastOptionEvent = (code: code, flags: event.flags.rawValue)
      }
    }
    if type == .flagsChanged && code == 61 {
      if let down = stateLock.withLock({ optionState.update(keyCode: code, flags: event.flags.rawValue) }) {
        NSLog("Push2Talk: right Option event down=%@ flags=0x%llx", String(down), event.flags.rawValue)
        let shiftHeld = event.flags.contains(.maskShift)
        deliver { $0.onHold?(down, shiftHeld) }
      }
      return nil
    }
    let isShiftTransition = type == .flagsChanged && (code == 56 || code == 60)
    if type == .keyDown || (type == .flagsChanged && !isShiftTransition) {
      let nativeEscape = type == .keyDown && code == 53
      deliver { $0.onCancel?(nativeEscape) }
    }
    if isRightOptionHeld {
      // Do not leak the held Option into the target application's shortcuts or text.
      if event.flags.rawValue & 0x20 == 0 { event.flags.remove(.maskAlternate) }
    }
    return Unmanaged.passUnretained(event)
  }

  private func deliver(_ action: @escaping (KeyboardBridge) -> Void) {
    let expectedGeneration = stateLock.withLock { generation }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.stateLock.withLock({ self.generation == expectedGeneration }) else { return }
      action(self)
    }
  }

  public func startDictation(_ trigger: DictationTrigger, ifCurrent: @escaping () -> Bool) {
    let source = CGEventSource(stateID: .privateState)
    // Keep each sequence balanced and serialize cancellation behind an in-flight sequence.
    let base = max(nextPostTime, ProcessInfo.processInfo.systemUptime)
    for (offset, down) in [(0.0, true), (0.035, false), (0.09, true), (0.125, false)] {
      guard
        let event = CGEvent(keyboardEventSource: source, virtualKey: trigger.keyCode, keyDown: down)
      else { continue }
      event.type = .flagsChanged
      event.flags = down ? CGEventFlags(rawValue: trigger.flag.rawValue | trigger.deviceFlag) : []
      post(event, at: base + offset, condition: down ? ifCurrent : { true })
    }
    nextPostTime = base + 0.16
  }

  public func stopDictation(ifCurrent: @escaping () -> Bool) { sendKey(53, ifCurrent: ifCurrent) }
  public func sendEnter(ifCurrent: @escaping () -> Bool) { sendKey(36, ifCurrent: ifCurrent) }

  private func sendKey(_ key: CGKeyCode, ifCurrent: @escaping () -> Bool) {
    let source = CGEventSource(stateID: .privateState)
    let base = max(nextPostTime, ProcessInfo.processInfo.systemUptime)
    for (offset, down) in [(0.0, true), (0.025, false)] {
      guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
        continue
      }
      event.flags = []
      post(event, at: base + offset, condition: down ? ifCurrent : { true })
    }
    nextPostTime = base + 0.05
  }

  private func post(_ event: CGEvent, at time: Double, condition: @escaping () -> Bool) {
    event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
    DispatchQueue.main.asyncAfter(
      deadline: .now() + max(0, time - ProcessInfo.processInfo.systemUptime)
    ) {
      guard AXIsProcessTrusted(), CGPreflightPostEventAccess(), condition() else { return }
      event.post(tap: .cghidEventTap)
    }
  }
}

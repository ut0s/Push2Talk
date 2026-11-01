/// Tracks right Option transitions, including events without device-specific flags.
public struct RightOptionState {
  public private(set) var isHeld = false

  public init() {}

  @discardableResult
  public mutating func update(keyCode: Int64, flags: UInt64) -> Bool? {
    guard keyCode == 61 else { return nil }
    let down: Bool
    if flags & 0x60 != 0 {
      // Side-specific bits remain authoritative when both Option keys are used.
      down = flags & 0x40 != 0
    } else if flags & (1 << 19) == 0 {
      down = false
    } else {
      // The flagsChanged key code identifies the selected key's transition even
      // when a keyboard driver supplies only the aggregate Option flag.
      down = !isHeld
    }
    guard down != isHeld else { return nil }
    isHeld = down
    return down
  }

  public mutating func reset() { isHeld = false }
}

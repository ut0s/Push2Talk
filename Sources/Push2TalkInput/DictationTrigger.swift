import CoreGraphics

public enum DictationTrigger: String, CaseIterable {
  case rightCommand, control, option, command, fn
  public var title: String {
    switch self {
    case .rightCommand: return "右Commandを2回"
    case .control: return "Controlを2回"
    case .option: return "左Optionを2回"
    case .command: return "左Commandを2回"
    case .fn: return "Fn / 地球儀を2回（実験的）"
    }
  }
  public var keyCode: CGKeyCode {
    switch self {
    case .rightCommand: return 54
    case .control: return 59
    case .option: return 58
    case .command: return 55
    case .fn: return 63
    }
  }
  public var flag: CGEventFlags {
    switch self {
    case .control: return .maskControl
    case .option: return .maskAlternate
    case .rightCommand, .command: return .maskCommand
    case .fn: return .maskSecondaryFn
    }
  }
  public var deviceFlag: UInt64 {
    switch self {
    case .rightCommand: return 0x10
    case .control: return 0x1
    case .option: return 0x20
    case .command: return 0x8
    case .fn: return 0
    }
  }
}


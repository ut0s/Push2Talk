import CoreGraphics
import Foundation
import Push2TalkInput

final class Settings {
  private let defaults = UserDefaults.standard
  var menuBarIcon: MenuBarIcon {
    get { MenuBarIcon(rawValue: defaults.string(forKey: "menuBarIcon") ?? "") ?? .microphone }
    set { defaults.set(newValue.rawValue, forKey: "menuBarIcon") }
  }
  var trigger: DictationTrigger {
    get { DictationTrigger(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .rightCommand }
    set { defaults.set(newValue.rawValue, forKey: "trigger") }
  }
  var sendEnter: Bool {
    get { defaults.object(forKey: "sendEnter") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "sendEnter") }
  }
  var settleDelay: Double {
    get {
      let value = defaults.object(forKey: "settleDelay") as? Double ?? 0.8
      return value.isFinite ? min(3, max(0.3, value)) : 0.8
    }
    set { defaults.set(newValue, forKey: "settleDelay") }
  }
  var setupComplete: Bool {
    get { defaults.bool(forKey: "setupComplete") }
    set { defaults.set(newValue, forKey: "setupComplete") }
  }
}

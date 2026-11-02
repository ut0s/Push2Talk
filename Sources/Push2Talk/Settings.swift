import Push2TalkCore
import CoreGraphics
import Foundation
import Push2TalkInput

enum StatusDisplayMode: String, CaseIterable {
  case menuBar, popup, both

  var title: String {
    switch self {
    case .menuBar: return L10n.text("メニューバーのみ")
    case .popup: return L10n.text("ポップアップのみ")
    case .both: return L10n.text("両方")
    }
  }

  var showsMenuBarStatus: Bool { self != .popup }
  var showsPopup: Bool { self != .menuBar }
}

enum RecordingText: String, CaseIterable {
  case input, recording, uppercaseRec, none

  var text: String {
    switch self {
    case .input: return L10n.text("入力中")
    case .recording: return L10n.text("録音中")
    case .uppercaseRec: return "REC"
    case .none: return ""
    }
  }

  var title: String { self == .none ? L10n.text("テキストなし") : text }
  var menuBarTitle: String { text.isEmpty ? "" : " \(text)" }
}

enum SettingsPage: String, CaseIterable {
  case dictation, appearance, permissions, general
}

final class Settings {
  static let settleDelays = [0.3, 0.5, 0.8, 1.2, 2.0, 3.0]
  private let defaults = UserDefaults.standard
  var settingsPage: SettingsPage {
    get { SettingsPage(rawValue: defaults.string(forKey: "settingsPage") ?? "") ?? .dictation }
    set { defaults.set(newValue.rawValue, forKey: "settingsPage") }
  }
  var statusDisplayMode: StatusDisplayMode {
    get { StatusDisplayMode(rawValue: defaults.string(forKey: "statusDisplayMode") ?? "") ?? .menuBar }
    set { defaults.set(newValue.rawValue, forKey: "statusDisplayMode") }
  }
  var recordingText: RecordingText {
    get {
      let value = defaults.string(forKey: "recordingText") ?? ""
      return value == "rec" ? .uppercaseRec : RecordingText(rawValue: value) ?? .input
    }
    set { defaults.set(newValue.rawValue, forKey: "recordingText") }
  }
  var menuBarIcon: MenuBarIcon {
    get { MenuBarIcon(rawValue: defaults.string(forKey: "menuBarIcon") ?? "") ?? .microphone }
    set { defaults.set(newValue.rawValue, forKey: "menuBarIcon") }
  }
  var trigger: DictationTrigger {
    get { DictationTrigger(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .rightCommand }
    set { defaults.set(newValue.rawValue, forKey: "trigger") }
  }
  var sendEnter: Bool {
    get { defaults.object(forKey: "sendEnter") as? Bool ?? false }
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

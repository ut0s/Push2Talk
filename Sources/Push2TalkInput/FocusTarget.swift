import AppKit
import ApplicationServices

struct FocusMetadata {
  var isSecure: Bool
  var isEditable: Bool
}

struct FocusEnvironment {
  var ownPID: pid_t
  var frontmostPID: () -> pid_t?
  var bundleIdentifier: (pid_t) -> String? = { _ in nil }
  var focusedElement: (pid_t) -> AXUIElement?
  var metadata: (AXUIElement) -> FocusMetadata
  var text: (AXUIElement) -> String?

  static var system: FocusEnvironment {
    FocusEnvironment(
      ownPID: ProcessInfo.processInfo.processIdentifier,
      frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
      bundleIdentifier: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
      focusedElement: { pid in
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = value as! AXUIElement
        // Child elements have their own messaging timeout.
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
      },
      metadata: { element in
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        var writable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable)
        var selectionWritable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectionWritable)
        return FocusMetadata(
          isSecure: subrole as? String == "AXSecureTextField",
          isEditable: [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role as? String ?? "")
            || writable.boolValue || selectionWritable.boolValue)
      },
      text: { element in
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
      })
  }
}

public struct FocusTarget {
  private let pid: pid_t
  private let element: AXUIElement?
  private let initialText: String?
  public let isEditable: Bool
  private let environment: FocusEnvironment

  public var canSubmitAutomatically: Bool { element != nil && initialText != nil }

  public static func capture() -> FocusTarget? { capture(environment: .system) }

  static func capture(environment: FocusEnvironment) -> FocusTarget? {
    guard let pid = environment.frontmostPID(), pid != environment.ownPID else { return nil }
    let element = environment.focusedElement(pid)
    var initialText: String?
    var isEditable = false
    if let element {
      let metadata = environment.metadata(element)
      guard !metadata.isSecure else { return nil }
      // macOS decides whether native Dictation is available in custom editors.
      // Reading text is only needed to authorize automatic Enter afterward.
      isEditable = metadata.isEditable
      if isEditable { initialText = environment.text(element) }
    }
    return FocusTarget(pid: pid, element: element, initialText: initialText, isEditable: isEditable, environment: environment)
  }

  public var isCurrent: Bool {
    guard environment.frontmostPID() == pid else { return false }
    let current = environment.focusedElement(pid)
    if let current, environment.metadata(current).isSecure { return false }
    guard let element else { return true }
    guard let current else { return false }
    return CFEqual(element, current)
  }

  public func insertText(_ text: String, using keyboard: KeyboardBridge) -> Bool {
    guard let element, isEditable, isCurrent else { return false }
    // The ChatGPT desktop composer does not reflect the existing direct insertion methods.
    if environment.bundleIdentifier(pid) != "com.openai.codex",
      AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    {
      return true
    }
    return keyboard.pasteText(text, to: pid, ifCurrent: { isCurrent })
  }

  public var hasNewText: Bool {
    guard let element, let initialText, isCurrent,
      let current = environment.text(element)
    else { return false }
    return current != initialText
  }
}

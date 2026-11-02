import Push2TalkCore
import AppKit

enum MenuBarIcon: String, CaseIterable {
  case microphone, walkieTalkie

  var title: String {
    switch self {
    case .microphone: return L10n.text("マイク")
    case .walkieTalkie: return L10n.text("トランシーバー")
    }
  }

  func image(symbol: String = "mic", description: String) -> NSImage? {
    guard let base = baseImage(symbol: symbol, description: description) else { return nil }
    guard symbol == "mic.fill" else { return base }
    // Use a non-template red icon and a recording dot to make an active session unmistakable.
    let active = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { _ in
      let iconRect = NSRect(x: 0, y: 0, width: 18, height: 18)
      base.draw(in: iconRect)
      NSColor.systemRed.setFill()
      iconRect.fill(using: .sourceAtop)
      NSBezierPath(ovalIn: NSRect(x: 21, y: 6, width: 6, height: 6)).fill()
      return true
    }
    active.isTemplate = false
    active.accessibilityDescription = description
    return active
  }

  private func baseImage(symbol: String, description: String) -> NSImage? {
    if self == .microphone {
      return NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }
    // Draw a template image so macOS handles light, dark, and highlighted menu bars.
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let body = NSBezierPath(
        roundedRect: NSRect(x: 4, y: 1, width: 10, height: 12), xRadius: 2, yRadius: 2)
      body.lineWidth = 1.4
      body.stroke()
      func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: x1, y: y1))
        path.line(to: NSPoint(x: x2, y: y2))
        path.stroke()
      }
      line(11, 13, 11, 17)
      line(6, 13, 6, 14)
      line(2.5, 8, 2.5, 10)
      for y: CGFloat in [3.5, 5, 6.5] { line(6.5, y, 11.5, y) }
      let display = NSBezierPath(
        roundedRect: NSRect(x: 6, y: 8.5, width: 6, height: 2.5), xRadius: 0.5, yRadius: 0.5)
      display.lineWidth = 1
      if symbol == "mic.fill" { display.fill() } else { display.stroke() }
      if symbol == "mic.slash" { line(1, 1, 17, 17) }
      if symbol == "ellipsis.bubble" {
        for x: CGFloat in [7, 9, 11] {
          NSBezierPath(ovalIn: NSRect(x: x - 0.4, y: 9.3, width: 0.8, height: 0.8)).fill()
        }
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = description
    return image
  }
}

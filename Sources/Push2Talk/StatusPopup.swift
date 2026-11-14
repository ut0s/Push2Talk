import Push2TalkCore
import AppKit

/// A passive status display that never becomes the input target.
final class StatusPopup {
  enum State: Equatable {
    case recording, waveform, settling

    var symbol: String { self == .settling ? "ellipsis.bubble" : "mic.fill" }
    var title: String { self == .settling ? L10n.text("文字の確定待ち") : L10n.text("音声入力中") }
    var color: NSColor { self == .settling ? .secondaryLabelColor : .systemRed }
  }

  private let panel: NSPanel
  private let imageView = NSImageView()
  private let waveformView = RecordingWaveformView()
  private var state: State?
  private var settlingTimer: Timer?
  private var settlingDotCount = 1

  init() {
    panel = StatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 80, height: 72),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.animationBehavior = .none

    let background = NSVisualEffectView(frame: panel.contentView!.bounds)
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    // Mask the native backdrop and window shadow, not only the view's backing layer.
    background.maskImage = NSImage(size: background.bounds.size, flipped: false) { rect in
      NSColor.white.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
      return true
    }
    panel.contentView = background

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
    background.addSubview(imageView)
    waveformView.translatesAutoresizingMaskIntoConstraints = false
    waveformView.isHidden = true
    waveformView.setAccessibilityElement(true)
    waveformView.setAccessibilityRole(.image)
    background.addSubview(waveformView)
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: background.centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
      imageView.widthAnchor.constraint(equalToConstant: 36),
      imageView.heightAnchor.constraint(equalToConstant: 36),
      waveformView.centerXAnchor.constraint(equalTo: background.centerXAnchor),
      waveformView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
      waveformView.widthAnchor.constraint(equalToConstant: 50),
      waveformView.heightAnchor.constraint(equalToConstant: 34),
    ])
  }

  func update(_ newState: State?, recordingLevel: CGFloat? = nil) {
    guard let newState else {
      stopSettlingAnimation()
      state = nil
      waveformView.reset()
      panel.orderOut(nil)
      return
    }
    if state != newState {
      stopSettlingAnimation()
      waveformView.reset()
      waveformView.isHidden = newState != .waveform
      waveformView.setAccessibilityLabel(newState.title)
      imageView.isHidden = newState == .waveform
      imageView.image = NSImage(
        systemSymbolName: newState.symbol, accessibilityDescription: newState.title)
      imageView.contentTintColor = newState.color
      imageView.setAccessibilityLabel(newState.title)
      panel.title = newState.title
      state = newState
      if newState == .settling {
        settlingDotCount = 1
        updateSettlingImage()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
          guard let self else { return }
          self.settlingDotCount = self.settlingDotCount % 3 + 1
          self.updateSettlingImage()
        }
        settlingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
      }
    }
    if newState == .waveform, let recordingLevel {
      waveformView.append(recordingLevel)
    }
    guard !panel.isVisible else { return }
    // Pick the screen where the user starts the session, then keep the HUD stationary.
    let screen =
      NSScreen.screens.first {
        NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
      } ?? NSScreen.main
    guard let screen else { return }
    let area = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + 24))
    panel.orderFrontRegardless()
  }

  private func stopSettlingAnimation() {
    settlingTimer?.invalidate()
    settlingTimer = nil
  }

  private func updateSettlingImage() {
    let dotCount = settlingDotCount
    let image = NSImage(size: NSSize(width: 36, height: 36), flipped: false) { _ in
      NSColor.black.set()
      // Keep the bubble and dot positions fixed as dots appear from left to right.
      let bubble = NSBezierPath()
      bubble.move(to: NSPoint(x: 10, y: 9))
      bubble.line(to: NSPoint(x: 6, y: 5))
      bubble.line(to: NSPoint(x: 6, y: 10))
      bubble.curve(to: NSPoint(x: 3, y: 15),
        controlPoint1: NSPoint(x: 4, y: 10), controlPoint2: NSPoint(x: 3, y: 12))
      bubble.line(to: NSPoint(x: 3, y: 25))
      bubble.curve(to: NSPoint(x: 9, y: 31),
        controlPoint1: NSPoint(x: 3, y: 29), controlPoint2: NSPoint(x: 5, y: 31))
      bubble.line(to: NSPoint(x: 27, y: 31))
      bubble.curve(to: NSPoint(x: 33, y: 25),
        controlPoint1: NSPoint(x: 31, y: 31), controlPoint2: NSPoint(x: 33, y: 29))
      bubble.line(to: NSPoint(x: 33, y: 15))
      bubble.curve(to: NSPoint(x: 27, y: 9),
        controlPoint1: NSPoint(x: 33, y: 11), controlPoint2: NSPoint(x: 31, y: 9))
      bubble.close()
      bubble.lineWidth = 2
      bubble.lineJoinStyle = .round
      bubble.stroke()
      for index in 0..<dotCount {
        NSBezierPath(ovalIn: NSRect(x: 10 + CGFloat(index) * 6.5, y: 18.5,
          width: 3, height: 3)).fill()
      }
      return true
    }
    image.isTemplate = true
    imageView.image = image
  }

  deinit {
    settlingTimer?.invalidate()
  }
}

private final class RecordingWaveformView: NSView {
  private static let barCount = 13
  private var levels = Array(repeating: CGFloat.zero, count: barCount)

  func reset() {
    levels = Array(repeating: 0, count: Self.barCount)
    needsDisplay = true
  }

  func append(_ level: CGFloat) {
    levels.removeFirst()
    levels.append(level)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.systemRed.setFill()
    let spacing = bounds.width / CGFloat(Self.barCount)
    let barWidth: CGFloat = 2
    for (index, level) in levels.enumerated() {
      let height = barWidth + level * (bounds.height - barWidth)
      let rect = NSRect(x: (CGFloat(index) + 0.5) * spacing - barWidth / 2,
        y: bounds.midY - height / 2, width: barWidth, height: height)
      NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
  }
}

private final class StatusPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

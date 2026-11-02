import AppKit

final class SettingsLayout: NSView, NSTabViewDelegate {
  private let tabs = NSTabView()
  var onSelectionChange: ((SettingsPage) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    tabs.delegate = self
    tabs.translatesAutoresizingMaskIntoConstraints = false
    addSubview(tabs)
    NSLayoutConstraint.activate([
      tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      tabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      tabs.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      tabs.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
    ])
  }

  convenience init() { self.init(frame: .zero) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func selectCategory(_ page: SettingsPage) {
    tabs.selectTabViewItem(withIdentifier: page.rawValue)
  }

  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    guard let identifier = tabViewItem?.identifier as? String,
      let page = SettingsPage(rawValue: identifier)
    else { return }
    onSelectionChange?(page)
  }

  func category(_ title: String, subtitle: String, page: SettingsPage) -> NSStackView {
    let item = NSTabViewItem(identifier: page.rawValue)
    item.label = title
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    let document = SettingsDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = document
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(stack)
    NSLayoutConstraint.activate([
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
    ])
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 22, weight: .bold)
    stack.addArrangedSubview(heading)
    note(subtitle, in: stack)
    item.view = scroll
    tabs.addTabViewItem(item)
    return stack
  }

  func section(_ title: String, in parent: NSStackView) -> NSStackView {
    let box = NSBox()
    box.boxType = .custom
    box.titlePosition = .noTitle
    box.cornerRadius = 8
    box.borderWidth = 1
    box.borderColor = .separatorColor
    box.fillColor = .controlBackgroundColor
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    // Keep the heading in the content flow rather than NSBox's separate title area.
    box.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16),
    ])
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 13, weight: .semibold)
    heading.setContentCompressionResistancePriority(.required, for: .vertical)
    fullWidth(heading, in: stack)
    fullWidth(box, in: parent)
    return stack
  }

  func fullWidth(_ view: NSView, in parent: NSStackView) {
    parent.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
  }

  func note(_ text: String, in parent: NSStackView) {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    fullWidth(label, in: parent)
  }

  func row(_ title: String, control: NSControl, in parent: NSStackView) {
    control.setAccessibilityLabel(title)
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    let label = NSTextField(labelWithString: title)
    label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    fullWidth(row, in: parent)
  }
}

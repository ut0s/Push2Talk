import AppKit

final class PermissionStatusView: NSStackView {
  private let summary = NSTextField(wrappingLabelWithString: "確認中…")
  private let accessibility = PermissionRow(title: "アクセシビリティ", button: "設定を開く")
  private let listening = PermissionRow(title: "入力監視", button: "設定を開く")
  private let posting = PermissionRow(title: "キー送信", button: "許可を要求")
  private let monitoring = PermissionRow(title: "キー監視の動作", button: nil)
  private let checkedAt = NSTextField(labelWithString: "")
  private let optionEvent = NSTextField(wrappingLabelWithString: "")
  private let operation = NSTextField(wrappingLabelWithString: "")

  init(
    target: AnyObject, accessibilityAction: Selector, listeningAction: Selector,
    postingAction: Selector, refreshAction: Selector, restartAction: Selector,
    revealAppAction: Selector
  ) {
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .leading
    spacing = 10
    let heading = NSTextField(labelWithString: "権限と動作確認")
    heading.font = .boldSystemFont(ofSize: 15)
    addArrangedSubview(heading)
    addArrangedSubview(summary)
    summary.font = .systemFont(ofSize: 12, weight: .medium)
    summary.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    for (row, action) in [
      (accessibility, accessibilityAction), (listening, listeningAction),
      (posting, postingAction), (monitoring, nil as Selector?),
    ] {
      addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
      row.button?.target = target
      row.button?.action = action
    }
    let refresh = NSButton(title: "今すぐ再確認", target: target, action: refreshAction)
    let restart = NSButton(title: "アプリを再起動", target: target, action: restartAction)
    checkedAt.font = .systemFont(ofSize: 11)
    checkedAt.textColor = .secondaryLabelColor
    let footer = NSStackView(views: [refresh, restart])
    footer.orientation = .horizontal
    footer.spacing = 12
    addArrangedSubview(footer)
    addArrangedSubview(checkedAt)
    optionEvent.font = .systemFont(ofSize: 11)
    optionEvent.isSelectable = true
    addArrangedSubview(optionEvent)
    optionEvent.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    operation.font = .systemFont(ofSize: 12)
    operation.isSelectable = true
    addArrangedSubview(operation)
    operation.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    let note = NSTextField(
      wrappingLabelWithString:
        "設定を開いている間は自動更新します。OS設定で許可しても結果が変わらない場合は、まず「アプリを再起動」を試してください。更新前のアプリを許可していた場合は、現在のPush2Talk.appを登録し直してください。"
    )
    note.font = .systemFont(ofSize: 11)
    note.textColor = .secondaryLabelColor
    addArrangedSubview(note)
    note.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    let location = NSTextField(wrappingLabelWithString: "現在のアプリ: \(Bundle.main.bundleURL.path)")
    location.font = .systemFont(ofSize: 11)
    location.isSelectable = true
    addArrangedSubview(location)
    location.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    addArrangedSubview(NSButton(title: "現在のアプリをFinderで表示", target: target, action: revealAppAction))
    let registration = NSTextField(
      wrappingLabelWithString:
        "同名の古いビルドが許可されていても、現在のビルドには適用されないことがあります。OS設定の古いPush2Talkを「−」で削除し、「＋」から上の場所のアプリを登録してください。")
    registration.font = .systemFont(ofSize: 11)
    registration.textColor = .secondaryLabelColor
    addArrangedSubview(registration)
    registration.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateOperationStatus(_ message: String) { operation.stringValue = message }

  func refresh(
    accessibilityGranted: Bool, listeningGranted: Bool, postingGranted: Bool,
    monitoringRunning: Bool, paused: Bool, setupComplete: Bool,
    secureInputEnabled: Bool, optionEventStatus: String
  ) {
    optionEvent.stringValue = optionEventStatus
    accessibility.update(
      status: accessibilityGranted ? "許可済み" : "未許可", good: accessibilityGranted,
      detail: "入力欄の確認と、長押しキーの操作に必要です。")
    listening.update(
      status: listeningGranted ? "許可済み" : (monitoringRunning ? "監視可能" : "個別許可なし"),
      good: listeningGranted || monitoringRunning,
      detail: monitoringRunning && !listeningGranted
        ? "入力監視の個別許可なしで、アクセシビリティによるキー監視が動作しています。"
        : "キー監視を開始できない場合に設定してください。個別許可がなくても動作する場合があります。",
      neutral: !listeningGranted && !monitoringRunning)
    posting.update(
      status: postingGranted ? "許可済み" : "未許可", good: postingGranted,
      detail: postingGranted
        ? "音声入力の開始・終了とEnterを送信できる権限が確認できました。"
        : (accessibilityGranted
          ? "アクセシビリティは許可済みですが、キー送信は未許可です。「許可を要求」後、反映されなければアプリを再起動してください。"
          : "音声入力の開始・終了とEnter送信に必要です。アクセシビリティ設定と「許可を要求」で確認してください。"))
    let runtimeStatus: String
    let runtimeDetail: String
    if paused {
      runtimeStatus = "一時停止中"
      runtimeDetail = "メニューバーの「再開」でキー監視を再開できます。"
    } else if !accessibilityGranted {
      runtimeStatus = "権限待ち"
      runtimeDetail = "アクセシビリティを許可すると、キー監視を自動で再確認します。"
    } else if !setupComplete {
      runtimeStatus = "初期設定待ち"
      runtimeDetail = "音声入力のショートカットを合わせ、下の「初期設定を完了」を押してください。"
    } else if secureInputEnabled {
      runtimeStatus = "セキュア入力で受信停止中"
      runtimeDetail = "パスワード欄から移動してください。ターミナル等の「セキュアキーボード入力」が有効な場合は解除してください。"
    } else if monitoringRunning {
      runtimeStatus = "監視中"
      runtimeDetail = "設定したOptionキーの長押しを受け付けられる状態です。"
    } else {
      runtimeStatus = "開始失敗"
      runtimeDetail = "権限は許可されていますが、キー監視を開始できません。入力監視の設定と再起動を試してください。"
    }
    monitoring.update(
      status: runtimeStatus, good: monitoringRunning && !paused && !secureInputEnabled, detail: runtimeDetail,
      neutral: paused || (!setupComplete && accessibilityGranted && postingGranted))
    if !accessibilityGranted || !postingGranted {
      summary.stringValue =
        accessibilityGranted
        ? "アクセシビリティは許可済みです。キー送信の追加確認が必要です。"
        : "アクセシビリティの許可が必要です。下の「設定を開く」から許可してください。"
      summary.textColor = .systemOrange
    } else if paused || !setupComplete {
      summary.stringValue = "必要な権限は許可済みです。キー監視: \(runtimeStatus)"
      summary.textColor = .secondaryLabelColor
    } else if secureInputEnabled {
      summary.stringValue = "権限は許可済みですが、セキュア入力がキーの受信を止めています。"
      summary.textColor = .systemOrange
    } else if monitoringRunning {
      summary.stringValue = "必要な権限は許可済み・キー監視も動作中です。"
      summary.textColor = .systemGreen
    } else {
      summary.stringValue = "権限は許可済みですが、キー監視の開始に失敗しています。"
      summary.textColor = .systemOrange
    }
    checkedAt.stringValue =
      "最終確認: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
  }
}

private final class PermissionRow: NSView {
  let button: NSButton?
  private let icon = NSImageView()
  private let status = NSTextField(labelWithString: "確認中…")
  private let detail = NSTextField(wrappingLabelWithString: "")

  init(title: String, button buttonTitle: String?) {
    button = buttonTitle.map { NSButton(title: $0, target: nil, action: nil) }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
    status.font = .systemFont(ofSize: 12, weight: .semibold)
    let header = NSStackView(views: [titleLabel, status])
    header.orientation = .horizontal
    header.spacing = 10
    detail.font = .systemFont(ofSize: 11)
    detail.textColor = .secondaryLabelColor
    let text = NSStackView(views: [header, detail])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 4
    text.setContentHuggingPriority(.defaultLow, for: .horizontal)
    detail.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
    var views: [NSView] = [icon, text]
    if let button {
      button.controlSize = .small
      button.setContentHuggingPriority(.required, for: .horizontal)
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
      button.setAccessibilityLabel("\(title): \(buttonTitle ?? "")")
      views.append(button)
    }
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 18),
      icon.heightAnchor.constraint(equalToConstant: 18),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(status value: String, good: Bool, detail message: String, neutral: Bool = false) {
    status.stringValue = value
    let color: NSColor = good ? .systemGreen : (neutral ? .secondaryLabelColor : .systemOrange)
    status.textColor = color
    icon.image = NSImage(
      systemSymbolName: good
        ? "checkmark.circle.fill" : (neutral ? "pause.circle" : "exclamationmark.circle.fill"),
      accessibilityDescription: value)
    icon.contentTintColor = color
    detail.stringValue = message
  }
}

final class SettingsDocumentView: NSView {
  override var isFlipped: Bool { true }
}

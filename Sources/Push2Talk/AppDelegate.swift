import AppKit
import ApplicationServices
import Push2TalkCore
import Push2TalkInput
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = Settings()
  private let statusPopup = StatusPopup()
  private let keyboard = KeyboardBridge()
  private var session = HoldSession()
  private var target: FocusTarget?
  private var timer: Timer?
  private var permissionsTimer: Timer?
  private var permissionStatusView: PermissionStatusView?
  private var lastPermissionStatus: String?
  private var statusItem: NSStatusItem!
  private var statusLine: NSMenuItem!
  private var pauseItem: NSMenuItem!
  private var paused = false
  private var isRestarting = false
  private let updates = AppUpdates()
  private var settingsControls: [String: NSControl] = [:]
  private var settingsWindow: NSWindow?
  private var observers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: iconURL) {
      NSApp.applicationIconImage = icon
    }
    paused = CommandLine.arguments.contains("--paused")
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = settings.menuBarIcon.image(symbol: "mic.slash", description: "Push2Talk")
    updates.onCheckFinished = { [weak self] in self?.rebuildMenu() }
    rebuildMenu()

    keyboard.onHold = { [weak self] down, shiftHeld in self?.hold(down, shiftHeld: shiftHeld) }
    keyboard.onCancel = { [weak self] nativeEscape in self?.cancel(nativeEscape: nativeEscape) }
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.cancel()
        })
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
      self?.tick()
    }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    checkPermissions()
    permissionsTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
      self?.checkPermissions()
    }
    if let permissionsTimer { RunLoop.main.add(permissionsTimer, forMode: .common) }
    if !settings.setupComplete || CommandLine.arguments.contains("--settings") { showSettings() }
  }

  private func rebuildMenu() {
    let menu = NSMenu()
    statusLine = menu.addItem(withTitle: L10n.text("準備中…"), action: nil, keyEquivalent: "")
    menu.addItem(.separator())
    pauseItem = menu.addItem(withTitle: paused ? L10n.text("再開") : L10n.text("一時停止"), action: #selector(togglePause), keyEquivalent: "")
    menu.addItem(withTitle: L10n.text("設定・初期設定…"), action: #selector(showSettings), keyEquivalent: ",")
    let quick = NSMenu()
    addQuickToggle("終了後にEnterを送る", value: settings.sendEnter, to: quick) { [weak self] in
      guard let self else { return }
      self.cancel()
      self.settings.sendEnter.toggle()
    }
    addChoices("文字確定の待ち時間", values: Settings.settleDelays, selected: settings.settleDelay,
      title: { L10n.format("%@秒", String($0)) }, to: quick) { [weak self] in self?.settings.settleDelay = $0 }
    addChoices("開始ショートカット", values: DictationTrigger.allCases, selected: settings.trigger,
      title: { $0.title }, to: quick) { [weak self] in self?.cancel(); self?.settings.trigger = $0 }
    quick.addItem(.separator())
    addChoices("状態の表示方法", values: StatusDisplayMode.allCases, selected: settings.statusDisplayMode,
      title: { $0.title }, to: quick) { [weak self] in self?.settings.statusDisplayMode = $0 }
    addChoices("メニューバーアイコン", values: MenuBarIcon.allCases, selected: settings.menuBarIcon,
      title: { $0.title }, to: quick) { [weak self] in self?.settings.menuBarIcon = $0 }
    addChoices("録音中のテキスト", values: RecordingText.allCases, selected: settings.recordingText,
      title: { $0.title }, to: quick) { [weak self] in self?.settings.recordingText = $0 }
    quick.addItem(.separator())
    addChoices("表示言語", values: AppLanguage.allCases, selected: L10n.language,
      title: { $0.title }, to: quick) { [weak self] in self?.setLanguage($0) }
    addQuickToggle("ログイン時に起動", value: SMAppService.mainApp.status == .enabled, to: quick) { [weak self] in
      let button = NSButton()
      button.state = SMAppService.mainApp.status == .enabled ? .off : .on
      self?.changeLogin(button)
    }
    let quickItem = menu.addItem(withTitle: L10n.text("クイック設定"), action: nil, keyEquivalent: "")
    quickItem.submenu = quick
    menu.addItem(.separator())
    menu.addItem(withTitle: L10n.text("Push2Talkについて…"), action: #selector(showAbout), keyEquivalent: "")
    let updateItem = menu.addItem(withTitle: updates.checking ? L10n.text("アップデートを確認中…") : L10n.text("アップデートを確認…"), action: updates.checking ? nil : #selector(checkForUpdates), keyEquivalent: "")
    updateItem.isEnabled = !updates.checking
    menu.addItem(.separator())
    menu.addItem(withTitle: L10n.text("Push2Talkを終了"), action: #selector(quit), keyEquivalent: "q")
    for item in menu.items where item.action != nil { item.target = self }
    statusItem.menu = menu
    updateStatus()
  }

  private func addQuickToggle(_ title: String, value: Bool, to menu: NSMenu, action: @escaping () -> Void) {
    let item = ActionMenuItem(title: L10n.text(title)) { [weak self] in
      action()
      self?.refreshSettingsControls()
      self?.rebuildMenu()
    }
    item.state = value ? .on : .off
    menu.addItem(item)
  }

  private func addChoices<Value: Equatable>(
    _ title: String, values: [Value], selected: Value, title label: (Value) -> String,
    to menu: NSMenu, select: @escaping (Value) -> Void
  ) {
    let parent = menu.addItem(withTitle: L10n.text(title), action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    for value in values {
      let item = ActionMenuItem(title: label(value)) { [weak self] in
        select(value)
        self?.refreshSettingsControls()
        self?.rebuildMenu()
      }
      item.state = value == selected ? .on : .off
      submenu.addItem(item)
    }
    parent.submenu = submenu
  }

  private func refreshSettingsControls() {
    (settingsControls["enter"] as? NSButton)?.state = settings.sendEnter ? .on : .off
    (settingsControls["login"] as? NSButton)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    func select(_ key: String, _ index: Int?) {
      (settingsControls[key] as? NSPopUpButton)?.selectItem(at: index ?? 0)
    }
    select("trigger", DictationTrigger.allCases.firstIndex(of: settings.trigger))
    select("delay", Settings.settleDelays.firstIndex(of: settings.settleDelay))
    select("displayModePicker", StatusDisplayMode.allCases.firstIndex(of: settings.statusDisplayMode))
    select("iconPicker", MenuBarIcon.allCases.firstIndex(of: settings.menuBarIcon))
    select("recordingTextPicker", RecordingText.allCases.firstIndex(of: settings.recordingText))
    select("languagePicker", AppLanguage.allCases.firstIndex(of: L10n.language))
  }

  @objc private func showAbout() {
    cancel()
    NSApp.activate(ignoringOtherApps: true)
    var options: [NSApplication.AboutPanelOptionKey: Any] = [
      .applicationName: "Push2Talk",
      .applicationVersion: updates.version,
      .version: updates.build,
      .credits: NSAttributedString(string: L10n.text("キーを長押ししてmacOSの音声入力を使います。")),
    ]
    if let icon = NSApp.applicationIconImage {
      options[.applicationIcon] = icon
    }
    NSApp.orderFrontStandardAboutPanel(options: options)
  }

  @objc private func checkForUpdates() {
    cancel()
    updates.check()
    rebuildMenu()
  }

  func applicationWillTerminate(_ notification: Notification) {
    cancel()
    statusPopup.update(nil)
    keyboard.stop()
    timer?.invalidate()
    permissionsTimer?.invalidate()
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    cancel()
    // Allow a queued Escape and its key-up to finish before exiting.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  private var now: Double { ProcessInfo.processInfo.systemUptime }

  private func hold(_ down: Bool, shiftHeld: Bool) {
    // Update the hold indicator even when Dictation cannot start in the current context.
    updateStatus()
    defer { updateStatus() }
    guard !isRestarting, !paused else { reportOperation(L10n.text("開始できません: 一時停止中です")); return }
    guard keyboard.isRunning, settings.setupComplete else {
      reportOperation(L10n.text("開始できません: 初期設定とキー監視の状態を確認してください")); return
    }
    guard !keyboard.secureInputEnabled else {
      reportOperation(L10n.text("開始できません: セキュア入力中です")); return
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
      reportOperation(L10n.text("開始できません: アクセシビリティとキー送信の権限を確認してください")); return
    }
    if down {
      guard session.phase == .idle else { return }
      let flags = CGEventSource.flagsState(.hidSystemState)
      guard flags.intersection([.maskControl, .maskCommand, .maskSecondaryFn]).isEmpty,
        flags.rawValue & 0x20 == 0
      else { reportOperation(L10n.text("開始しません: ほかの修飾キーを離してから右Optionを押してください")); return }
      guard let focus = FocusTarget.capture() else {
        reportOperation(L10n.text("開始しません: 別アプリの入力欄を選んでください（パスワード欄は対象外です）")); return
      }
      target = focus
      session.settleDelay = settings.settleDelay
      session.sendEnter = settings.sendEnter
      session.press(at: now)
      reportOperation(focus.canSubmitAutomatically
        ? L10n.text("長押しを確認中です")
        : L10n.text("長押しを確認中です（入力欄情報を取得できないため、自動Enterは送りません）"))
    } else {
      session.release(at: now, shiftHeld: shiftHeld)
    }
  }

  private func tick() {
    if !AXIsProcessTrusted(), keyboard.isRunning {
      cancel()
      keyboard.stop()
      updateStatus()
    }
    guard session.phase != .idle else { return }
    guard !keyboard.secureInputEnabled, AXIsProcessTrusted(), CGPreflightPostEventAccess(), target?.isCurrent == true else {
      cancel()
      return
    }
    for action in session.tick(at: now) {
      guard let focus = target else { break }
      switch action {
      case .start:
        reportOperation(L10n.text("音声入力の開始ショートカットを送信します"))
        keyboard.startDictation(settings.trigger, ifCurrent: { focus.isCurrent })
      case .stop: keyboard.stopDictation(ifCurrent: { focus.isCurrent })
      case .enter:
        let flags = CGEventSource.flagsState(.hidSystemState)
        if focus.canSubmitAutomatically, target?.isCurrent == true, target?.hasNewText == true,
          flags.intersection([
            .maskControl, .maskCommand, .maskAlternate, .maskSecondaryFn,
          ]).isEmpty
        {
          keyboard.sendEnter(ifCurrent: { focus.isCurrent })
        }
      }
    }
    if session.phase == .idle { target = nil }
    updateStatus()
  }

  private func reportOperation(_ message: String) {
    // Diagnostic output contains control status only, never text or audio.
    if CommandLine.arguments.contains("--diagnostics"), let data = ("Push2Talk: \(message)\n").data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }

  private func cancel(nativeEscape: Bool = false) {
    // Ordinary typing while idle must not trigger AX/TCC queries or redraws.
    guard session.phase != .idle else { return }
    let actions = session.cancel()
    reportOperation(L10n.text("操作を中断しました。入力先の変更・クリック・ほかのキー入力を確認してください"))
    // Never send Escape into a different app/control; focus changes already end native Dictation.
    if !nativeEscape, actions.contains(.stop), let focus = target, focus.isCurrent,
      AXIsProcessTrusted()
    {
      keyboard.stopDictation(ifCurrent: { focus.isCurrent })
    }
    target = nil
    updateStatus()
  }

  @objc private func checkPermissions() {
    let accessibilityGranted = AXIsProcessTrusted()
    // Let the filtering tap initiate OS authorization even when posting preflight is false.
    if !accessibilityGranted {
      cancel()
      keyboard.stop()
    } else if !isRestarting && !paused && settings.setupComplete {
      _ = keyboard.start()
    }
    let postingGranted = CGPreflightPostEventAccess()
    let listeningGranted = CGPreflightListenEventAccess()
    let permissionStatus =
      "accessibility=\(accessibilityGranted) listening=\(listeningGranted) posting=\(postingGranted) monitoring=\(keyboard.isRunning)"
    if permissionStatus != lastPermissionStatus {
      NSLog("Push2Talk permissions: %@", permissionStatus)
      lastPermissionStatus = permissionStatus
    }
    updateStatus()
    permissionStatusView?.refresh(
      accessibilityGranted: accessibilityGranted,
      listeningGranted: listeningGranted, postingGranted: postingGranted,
      monitoringRunning: keyboard.isRunning, paused: paused, setupComplete: settings.setupComplete,
      secureInputEnabled: keyboard.secureInputEnabled, optionEventStatus: keyboard.optionEventStatus)
  }

  private func updateStatus() {
    guard statusLine != nil else { return }
    let title: String
    let symbol: String
    if !AXIsProcessTrusted() {
      title = L10n.text("アクセシビリティ権限が必要です")
      symbol = "mic.slash"
    } else if !CGPreflightPostEventAccess() {
      title = L10n.text("キー送信の権限が必要です")
      symbol = "mic.slash"
    } else if paused {
      title = L10n.text("一時停止中")
      symbol = "mic.slash"
    } else if !settings.setupComplete {
      title = L10n.text("初期設定を完了してください")
      symbol = "mic.slash"
    } else if keyboard.secureInputEnabled {
      title = L10n.text("セキュア入力中のためキーを受信できません")
      symbol = "mic.slash"
    } else if !keyboard.isRunning {
      title = L10n.text("キー監視を開始できません。権限を再確認してください")
      symbol = "mic.slash"
    } else {
      switch session.phase {
      case .idle:
        title = L10n.text("右Optionを長押しして話す")
        symbol = "mic"
      case .arming:
        title = L10n.text("長押しを確認中…")
        symbol = "mic"
      case .recording, .stopping:
        title = L10n.text("音声入力中 — 離すと終了")
        symbol = "mic.fill"
      case .settling:
        title = L10n.text("文字の確定を待っています…")
        symbol = "ellipsis.bubble"
      }
    }
    statusLine.title = title
    // Reflect the physical hold immediately, including while Dictation is stopping or settling.
    let heldSymbol = symbol == "mic.slash" ? "mic" : symbol
    let displaySymbol = settings.statusDisplayMode.showsMenuBarStatus
      ? (keyboard.isRightOptionHeld ? heldSymbol : "mic.slash") : "mic"
    statusItem.button?.image = settings.menuBarIcon.image(symbol: displaySymbol, description: title)
    statusItem.button?.attributedTitle = NSAttributedString(
      string: displaySymbol == "mic.fill" ? settings.recordingText.menuBarTitle : "",
      attributes: [.foregroundColor: NSColor.systemRed])
    statusItem.button?.toolTip = "Push2Talk: \(title)"
    let popupState: StatusPopup.State?
    if settings.statusDisplayMode.showsPopup && symbol != "mic.slash" {
      switch session.phase {
      case .recording, .stopping: popupState = .recording
      case .settling: popupState = .settling
      default: popupState = nil
      }
    } else {
      popupState = nil
    }
    statusPopup.update(popupState)
  }

  @objc private func togglePause() {
    cancel()
    paused.toggle()
    pauseItem.title = paused ? L10n.text("再開") : L10n.text("一時停止")
    if paused {
      keyboard.stop()
    }
    checkPermissions()
  }

  @objc private func showSettings() {
    cancel()
    if let settingsWindow {
      checkPermissions()
      settingsWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = L10n.text("Push2Talk 設定")
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 620, height: 480)
    let layout = SettingsLayout()
    window.contentView = layout

    let input = layout.category(L10n.text("音声入力"), subtitle: L10n.text("右Optionを長押し → 話す → 離して終了"), page: .dictation)
    let shortcut = layout.section(L10n.text("音声入力の準備"), in: input)
    layout.note(L10n.text("macOSの音声入力をオンにし、OSとPush2Talkで同じショートカットを選んでください。"), in: shortcut)
    let trigger = NSPopUpButton()
    settingsControls["trigger"] = trigger
    trigger.addItems(withTitles: DictationTrigger.allCases.map(\.title))
    trigger.selectItem(at: DictationTrigger.allCases.firstIndex(of: settings.trigger) ?? 0)
    trigger.target = self
    trigger.action = #selector(changeTrigger(_:))
    layout.row(L10n.text("開始ショートカット"), control: trigger, in: shortcut)
    shortcut.addArrangedSubview(NSButton(title: L10n.text("macOSのキーボード設定を開く"), target: self, action: #selector(openKeyboard)))
    shortcut.addArrangedSubview(NSButton(title: L10n.text("初期設定を完了・権限を再確認"), target: self, action: #selector(completeSetup)))

    let behavior = layout.section(L10n.text("入力終了後の動作"), in: input)
    let enter = NSButton(checkboxWithTitle: L10n.text("終了後にEnterを送る"), target: self, action: #selector(changeEnter(_:)))
    settingsControls["enter"] = enter
    enter.state = settings.sendEnter ? .on : .off
    behavior.addArrangedSubview(enter)
    layout.note(L10n.text("右Optionを離す瞬間に、左右どちらかのShiftを押していると、その回だけEnter送信のオン／オフを反転します。設定自体は変わりません。"), in: behavior)
    layout.note(L10n.text("例：上の設定がオフ（初期値）の場合\n・Shiftなしで右Optionを離す → 文字だけを入力\n・Shiftを押したまま右Optionを離す → 文字を入力してEnterを送信"), in: behavior)
    layout.note(L10n.text("例：上の設定がオンの場合\n・Shiftなしで右Optionを離す → 文字を入力してEnterを送信\n・Shiftを押したまま右Optionを離す → 文字だけを入力"), in: behavior)
    layout.note(L10n.text("Shiftは左右どちらでも、両方でも使えます。右Optionを離す前にShiftを押し、そのまま右Optionだけを離してください。右Optionを離した後でShiftを押したり離したりしても、その回の判定は変わりません。"), in: behavior)
    let delay = NSPopUpButton()
    settingsControls["delay"] = delay
    let delays = Settings.settleDelays
    for value in delays {
      delay.addItem(withTitle: L10n.format("%@秒", String(value)))
      delay.lastItem?.representedObject = value
    }
    delay.selectItem(at: delays.firstIndex(of: settings.settleDelay) ?? 2)
    delay.target = self
    delay.action = #selector(changeDelay(_:))
    layout.row(L10n.text("文字確定の待ち時間"), control: delay, in: behavior)
    layout.note(L10n.text("Enterは同じ入力欄に新しい文字がある場合のみ送信します。Shiftを押したままでも、送信するのは修飾キーなしのEnterです。短いタップは無視し、Escapeで中断できます。"), in: behavior)

    let appearance = layout.category(L10n.text("表示"), subtitle: L10n.text("入力状態の表示をカスタマイズ"), page: .appearance)
    let display = layout.section(L10n.text("状態の表示"), in: appearance)
    let displayModePicker = NSPopUpButton()
    settingsControls["displayModePicker"] = displayModePicker
    displayModePicker.addItems(withTitles: StatusDisplayMode.allCases.map(\.title))
    displayModePicker.selectItem(at: StatusDisplayMode.allCases.firstIndex(of: settings.statusDisplayMode) ?? 0)
    displayModePicker.target = self
    displayModePicker.action = #selector(changeStatusDisplayMode(_:))
    layout.row(L10n.text("状態の表示方法"), control: displayModePicker, in: display)
    layout.note(L10n.text("ポップアップは画面下部に静止アイコンで表示します。「ポップアップのみ」でも設定を開くメニューバーアイコンは残ります。"), in: display)
    let menuBar = layout.section(L10n.text("メニューバー"), in: appearance)
    let iconPicker = NSPopUpButton()
    settingsControls["iconPicker"] = iconPicker
    for icon in MenuBarIcon.allCases {
      iconPicker.addItem(withTitle: icon.title)
      iconPicker.lastItem?.image = icon.image(description: icon.title)
    }
    iconPicker.selectItem(at: MenuBarIcon.allCases.firstIndex(of: settings.menuBarIcon) ?? 0)
    iconPicker.target = self
    iconPicker.action = #selector(changeIcon(_:))
    layout.row(L10n.text("メニューバーアイコン"), control: iconPicker, in: menuBar)
    let recordingTextPicker = NSPopUpButton()
    settingsControls["recordingTextPicker"] = recordingTextPicker
    recordingTextPicker.addItems(withTitles: RecordingText.allCases.map(\.title))
    recordingTextPicker.selectItem(at: RecordingText.allCases.firstIndex(of: settings.recordingText) ?? 0)
    recordingTextPicker.target = self
    recordingTextPicker.action = #selector(changeRecordingText(_:))
    layout.row(L10n.text("録音中のテキスト"), control: recordingTextPicker, in: menuBar)

    let permissionsPage = layout.category(L10n.text("権限"), subtitle: L10n.text("macOSの許可とキー監視の状態"), page: .permissions)
    let permissions = PermissionStatusView(
      target: self, accessibilityAction: #selector(requestPermission),
      listeningAction: #selector(requestInputMonitoring), postingAction: #selector(requestPostingPermission),
      recheckAction: #selector(recheckPermissions),
      revealAppAction: #selector(revealCurrentApp))
    permissionStatusView = permissions
    layout.fullWidth(permissions, in: permissionsPage)
    layout.note(L10n.text("マイク・音声認識の許可はmacOS標準音声入力が管理します。Push2Talk自体には不要です。"), in: permissionsPage)

    let general = layout.category(L10n.text("一般"), subtitle: L10n.text("起動とアプリの管理"), page: .general)
    let languageSection = layout.section(L10n.text("言語"), in: general)
    let languagePicker = NSPopUpButton()
    settingsControls["languagePicker"] = languagePicker
    languagePicker.addItems(withTitles: AppLanguage.allCases.map(\.title))
    languagePicker.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
    languagePicker.target = self
    languagePicker.action = #selector(changeLanguage(_:))
    layout.row(L10n.text("表示言語"), control: languagePicker, in: languageSection)
    layout.note(L10n.text("言語を変更すると表示をすぐに更新します。音声入力の認識言語はmacOSで設定してください。"), in: languageSection)
    let startup = layout.section(L10n.text("起動"), in: general)
    let login = NSButton(checkboxWithTitle: L10n.text("ログイン時に起動"), target: self, action: #selector(changeLogin(_:)))
    settingsControls["login"] = login
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    startup.addArrangedSubview(login)
    layout.note(L10n.text("設定の変更は自動で保存されます。"), in: general)
    // Restore after all tabs exist and before observing changes, so construction cannot overwrite it.
    layout.selectCategory(settings.settingsPage)
    layout.onSelectionChange = { [weak self] page in self?.settings.settingsPage = page }
    settingsWindow = window
    checkPermissions()
    let availableHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 100
    window.setContentSize(NSSize(width: 680, height: min(720, availableHeight)))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func changeLanguage(_ sender: NSPopUpButton) {
    cancel()
    setLanguage(AppLanguage.allCases[sender.indexOfSelectedItem])
  }

  private func setLanguage(_ language: AppLanguage) {
    cancel()
    L10n.language = language
    let wasVisible = settingsWindow?.isVisible == true
    let frame = settingsWindow?.frame
    settingsWindow?.close()
    settingsWindow = nil
    settingsControls.removeAll()
    permissionStatusView = nil
    rebuildMenu()
    if wasVisible {
      showSettings()
      if let frame { settingsWindow?.setFrame(frame, display: true) }
    }
  }

  @objc private func changeTrigger(_ sender: NSPopUpButton) {
    cancel()
    settings.trigger = DictationTrigger.allCases[sender.indexOfSelectedItem]
    rebuildMenu()
  }
  @objc private func changeIcon(_ sender: NSPopUpButton) {
    settings.menuBarIcon = MenuBarIcon.allCases[sender.indexOfSelectedItem]
    rebuildMenu()
  }
  @objc private func changeStatusDisplayMode(_ sender: NSPopUpButton) {
    settings.statusDisplayMode = StatusDisplayMode.allCases[sender.indexOfSelectedItem]
    rebuildMenu()
  }
  @objc private func changeEnter(_ sender: NSButton) {
    settings.sendEnter = sender.state == .on
    rebuildMenu()
  }
  @objc private func changeRecordingText(_ sender: NSPopUpButton) {
    settings.recordingText = RecordingText.allCases[sender.indexOfSelectedItem]
    rebuildMenu()
  }
  @objc private func changeDelay(_ sender: NSPopUpButton) {
    settings.settleDelay = sender.selectedItem?.representedObject as? Double ?? 0.8
    rebuildMenu()
  }
  @objc private func completeSetup() {
    settings.setupComplete = true
    checkPermissions()
  }
  @objc private func openKeyboard() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
  }
  @objc private func requestPermission() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    checkPermissions()
  }
  @objc private func requestInputMonitoring() {
    _ = CGRequestListenEventAccess()
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    checkPermissions()
  }
  @objc private func requestPostingPermission() {
    _ = CGRequestPostEventAccess()
    checkPermissions()
    if !CGPreflightPostEventAccess() {
      NSWorkspace.shared.open(
        URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
  }
  @objc private func revealCurrentApp() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }
  @objc private func recheckPermissions() {
    guard !isRestarting else { return }
    isRestarting = true
    cancel()
    keyboard.stop()
    // Use a new process identity so MenuBarAgent does not retain an invalid scene after exec.
    // Wait for termination to release the single-instance lock before opening the app.
    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
    relaunch.arguments = [
      "-c",
      "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$2\" --args --settings",
      "Push2Talk-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
    ]
    do {
      try relaunch.run()
      NSApp.terminate(nil)
    } catch {
      isRestarting = false
      checkPermissions()
      let alert = NSAlert()
      alert.messageText = L10n.text("権限を再確認できませんでした")
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
  }
  @objc private func changeLogin(_ sender: NSButton) {
    do {
      if sender.state == .on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      let alert = NSAlert()
      alert.messageText = L10n.text("ログイン時の起動を変更できませんでした")
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
    sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    rebuildMenu()
  }
  @objc private func quit() { NSApp.terminate(nil) }
}

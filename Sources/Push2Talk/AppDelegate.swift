import AppKit
import ApplicationServices
import AVFoundation
import Push2TalkCore
import Push2TalkInput
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let settings = Settings()
  private let statusPopup = StatusPopup()
  private let keyboard = KeyboardBridge()
  private var session = HoldSession()
  private var localSpeech: LocalSpeech?
  private var modelOperations: Set<SpeechModel> = []
  private var modelStatus: [SpeechModel: String] = [:]
  private var modelButtons: [SpeechModel: NSButton] = [:]
  private var modelLabels: [SpeechModel: NSTextField] = [:]
  private var legacyQwenModelRow: NSStackView?
  private var speechRuntimeStatus: NSTextField?
  private var systemShortcutSection: NSView?
  private var microphoneButton: NSButton?
  private var microphoneRequestPending = false
  private var localError: String?
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
  private var permissionRestart = PermissionRestart()
  private var restartNotice: NSPanel?
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
    if !settings.speechEngine.supported { settings.speechEngine = .system }
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
    addChoices("キーを離してから終了まで", values: Settings.releaseDelays, selected: settings.releaseDelay,
      title: { L10n.format("%@秒", String($0)) }, to: quick) { [weak self] in self?.settings.releaseDelay = $0 }
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
    menu.addItem(withTitle: L10n.text("Push2Talkを再起動"), action: #selector(restart), keyEquivalent: "")
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
    select("engine", SpeechEngine.allCases.firstIndex(of: settings.speechEngine))
    select("whisperModel", settings.whisperModel == .small ? 1 : 0)
    select("trigger", DictationTrigger.allCases.firstIndex(of: settings.trigger))
    select("releaseDelay", Settings.releaseDelays.firstIndex(of: settings.releaseDelay))
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
    restartNotice?.orderOut(nil)
    cancel()
    statusPopup.update(nil)
    keyboard.restorePasteboard()
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
    NSLog("Push2Talk: hold down=%@ phase=%@", String(down), String(describing: session.phase))
    // Update the hold indicator even when Dictation cannot start in the current context.
    updateStatus()
    defer { updateStatus() }
    // Releasing an existing session must not depend on permission/setup checks
    // used to authorize a new session. The tick still guards event posting.
    if !down {
      session.release(at: now, shiftHeld: shiftHeld)
      if session.phase == .idle {
        cancelLocalSpeech()
        target = nil
      }
      return
    }
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
    guard session.phase == .idle else { return }
    localError = nil
    let flags = CGEventSource.flagsState(.hidSystemState)
    let leftOptionOnly = (flags.rawValue & 0x60) == 0x20
    guard flags.intersection([.maskControl, .maskCommand, .maskSecondaryFn]).isEmpty,
      !leftOptionOnly
    else { reportOperation(L10n.text("開始しません: ほかの修飾キーを離してから右Optionを押してください")); return }
    guard let focus = FocusTarget.capture() else {
      reportOperation(L10n.text("開始しません: 別アプリの入力欄を選んでください（パスワード欄は対象外です）")); return
    }
    let engine = settings.speechEngine
    if engine != .system {
      guard focus.isEditable else {
        showLocalError("書き込み可能な入力欄を選んでください")
        return
      }
      let model = engine == .whisper ? settings.whisperModel : settings.qwenModel
      guard engine.supported, let executable = model.executable, model.installed,
        !modelOperations.contains(model)
      else {
        showLocalError("音声入力の設定でランタイムとモデルを確認してください")
        return
      }
      guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        showLocalError("音声入力の設定でマイクを許可してください")
        return
      }
      do {
        localSpeech = try LocalSpeech(model: model, executable: executable)
      } catch {
        showLocalError("録音を開始できませんでした")
        return
      }
    }
    target = focus
    session.waitsForRecognition = localSpeech != nil
    session.startupGrace = localSpeech == nil ? 0.65 : 0
    session.releaseDelay = settings.releaseDelay
    session.settleDelay = settings.settleDelay
    session.sendEnter = settings.sendEnter
    session.press(at: now)
    reportOperation(focus.canSubmitAutomatically
      ? L10n.text("長押しを確認中です")
      : L10n.text("長押しを確認中です（入力欄情報を取得できないため、自動Enterは送りません）"))
  }

  private func tick() {
    keyboard.reconcileHoldState()
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
        if let localSpeech {
          do {
            try localSpeech.start()
            reportOperation(L10n.text("ローカル録音を開始しました"))
          } catch {
            cancel()
            showLocalError("録音を開始できませんでした")
          }
        } else {
          reportOperation(L10n.text("音声入力の開始ショートカットを送信します"))
          keyboard.startDictation(settings.trigger, ifCurrent: { focus.isCurrent })
        }
      case .stop:
        if let localSpeech {
          if session.phase == .recognizing {
            finishLocalSpeech(localSpeech, in: focus)
          } else {
            cancelLocalSpeech()
          }
        } else {
          keyboard.stopDictation(ifCurrent: { focus.isCurrent })
        }
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
    if session.phase == .idle {
      cancelLocalSpeech()
      target = nil
    }
    updateStatus()
  }

  private func finishLocalSpeech(_ speech: LocalSpeech, in focus: FocusTarget) {
    do {
      try speech.transcribe { [weak self, weak speech] result in
        guard let self, let speech, self.localSpeech === speech, self.session.phase == .recognizing else { return }
        guard !self.keyboard.secureInputEnabled, AXIsProcessTrusted(),
          CGPreflightPostEventAccess(), focus.isCurrent
        else {
          self.cancel()
          return
        }
        switch result {
        case .success(let text) where !text.isEmpty:
          if focus.insertText(text, using: self.keyboard) {
            self.session.finishRecognition(at: self.now)
            self.reportOperation(L10n.text("文字起こし結果を入力欄に渡しました"))
          } else {
            self.cancel()
            self.showLocalError("入力欄に認識結果を書き込めませんでした")
          }
        case .success:
          self.cancel()
          self.showLocalError("音声を認識できませんでした")
        case .failure:
          self.cancel()
          self.showLocalError("ローカル文字起こしに失敗しました")
        }
      }
      reportOperation(L10n.text("録音を終了し、ローカル文字起こしを開始しました"))
    } catch {
      cancel()
      showLocalError("ローカル文字起こしに失敗しました")
    }
  }

  private func cancelLocalSpeech() {
    localSpeech?.cancel()
    localSpeech = nil
  }

  private func showLocalError(_ message: String) {
    localError = L10n.text(message)
    reportOperation(L10n.text(message))
    updateStatus()
  }

  private func reportOperation(_ message: String) {
    NSLog("Push2Talk: %@", message)
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
    if localSpeech != nil {
      cancelLocalSpeech()
    } else if !nativeEscape, actions.contains(.stop), let focus = target, focus.isCurrent,
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
    refreshModelControls()
    permissionStatusView?.refresh(
      accessibilityGranted: accessibilityGranted,
      listeningGranted: listeningGranted, postingGranted: postingGranted,
      monitoringRunning: keyboard.isRunning, paused: paused, setupComplete: settings.setupComplete,
      secureInputEnabled: keyboard.secureInputEnabled, optionEventStatus: keyboard.optionEventStatus)
    checkAutomaticPermissionRestart(accessibility: accessibilityGranted, posting: postingGranted,
      listening: listeningGranted)
  }

  private func checkAutomaticPermissionRestart(accessibility: Bool, posting: Bool, listening: Bool) {
    guard !isRestarting else { return }
    let quiet = [CGEventType.keyDown, .keyUp, .flagsChanged].allSatisfy {
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) >= 2
    }
    let idle = session.phase == .idle && !keyboard.isRightOptionHeld
      && !keyboard.secureInputEnabled && quiet
    switch permissionRestart.update(.init(accessibility: accessibility, posting: posting,
      listening: listening), idle: idle, at: now) {
    case .none:
      restartNotice?.orderOut(nil)
    case .notice:
      if restartNotice == nil {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 76),
          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let label = NSTextField(wrappingLabelWithString:
          L10n.text("権限を反映するためPush2Talkを再起動します。設定画面に戻ります。"))
        label.frame = NSRect(x: 20, y: 16, width: 380, height: 44)
        panel.contentView?.addSubview(label)
        restartNotice = panel
      }
      if let panel = restartNotice, !panel.isVisible {
        panel.center()
        panel.orderFrontRegardless()
      }
    case .restart:
      recheckPermissions()
    }
  }

  private func updateStatus() {
    guard statusLine != nil else { return }
    let title: String
    let symbol: String
    if paused {
      title = L10n.text("一時停止中")
      symbol = "pause.fill"
    } else if !AXIsProcessTrusted() {
      title = L10n.text("アクセシビリティ権限が必要です")
      symbol = "mic.slash"
    } else if !CGPreflightPostEventAccess() {
      title = L10n.text("キー送信の権限が必要です")
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
        title = localError ?? L10n.text("右Optionを長押しして話す")
        symbol = "mic"
      case .arming:
        title = L10n.text("長押しを確認中…")
        symbol = "mic"
      case .recording, .stopping:
        title = L10n.text("音声入力中 — 離すと終了")
        symbol = "mic.fill"
      case .recognizing, .settling:
        title = L10n.text("文字の確定を待っています…")
        symbol = "ellipsis.bubble"
      }
    }
    statusLine.title = title
    // Reflect the physical hold immediately, including while Dictation is stopping or settling.
    let heldSymbol = symbol == "mic.slash" ? "mic" : symbol
    let displaySymbol = paused ? "pause.fill" : (settings.statusDisplayMode.showsMenuBarStatus
      ? (keyboard.isRightOptionHeld ? heldSymbol : "mic.slash") : "mic")
    statusItem.button?.image = settings.menuBarIcon.image(symbol: displaySymbol, description: title)
    statusItem.button?.attributedTitle = NSAttributedString(
      string: displaySymbol == "mic.fill" ? settings.recordingText.menuBarTitle : "",
      attributes: [.foregroundColor: NSColor.systemRed])
    statusItem.button?.toolTip = "Push2Talk: \(title)"
    let popupState: StatusPopup.State?
    var recordingLevel: CGFloat?
    if !paused && settings.statusDisplayMode.showsPopup && symbol != "mic.slash" {
      switch session.phase {
      case .recording, .stopping:
        recordingLevel = localSpeech?.recordingLevel()
        if localSpeech == nil {
          popupState = .recording
        } else {
          popupState = recordingLevel == nil ? nil : .waveform
        }
      case .recognizing, .settling: popupState = .settling
      default: popupState = nil
      }
    } else {
      popupState = nil
    }
    statusPopup.update(popupState, recordingLevel: recordingLevel)
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
    window.delegate = self
    window.contentMinSize = NSSize(width: 620, height: 480)
    let layout = SettingsLayout()
    window.contentView = layout

    let input = layout.category(L10n.text("音声入力"), subtitle: L10n.text("右Optionを長押し → 話す → 離して終了"), page: .dictation)
    addSpeechEngineSettings(to: input, layout: layout)
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
    systemShortcutSection = shortcut.superview
    systemShortcutSection?.isHidden = settings.speechEngine != .system
    input.addArrangedSubview(NSButton(title: L10n.text("初期設定を完了・権限を再確認"), target: self, action: #selector(completeSetup)))

    let behavior = layout.section(L10n.text("入力終了後の動作"), in: input)
    let releaseDelay = NSPopUpButton()
    settingsControls["releaseDelay"] = releaseDelay
    for value in Settings.releaseDelays {
      releaseDelay.addItem(withTitle: L10n.format("%@秒", String(value)))
      releaseDelay.lastItem?.representedObject = value
    }
    releaseDelay.selectItem(at: Settings.releaseDelays.firstIndex(of: settings.releaseDelay) ?? 2)
    releaseDelay.target = self
    releaseDelay.action = #selector(changeReleaseDelay(_:))
    layout.row(L10n.text("キーを離してから終了まで"), control: releaseDelay, in: behavior)
    layout.note(L10n.text("語尾が欠けないよう、キーを離した後も少し音声入力を続けます。変換が間に合わない場合は、この時間を延ばしてください。"), in: behavior)
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
    layout.note(L10n.text("ローカルエンジンを使う場合は、音声入力タブで Push2Talk のマイク利用を許可してください。"), in: permissionsPage)

    let general = layout.category(L10n.text("一般"), subtitle: L10n.text("起動とアプリの管理"), page: .general)
    let languageSection = layout.section(L10n.text("言語"), in: general)
    let languagePicker = NSPopUpButton()
    settingsControls["languagePicker"] = languagePicker
    languagePicker.addItems(withTitles: AppLanguage.allCases.map(\.title))
    languagePicker.selectItem(at: AppLanguage.allCases.firstIndex(of: L10n.language) ?? 0)
    languagePicker.target = self
    languagePicker.action = #selector(changeLanguage(_:))
    layout.row(L10n.text("表示言語"), control: languagePicker, in: languageSection)
    layout.note(L10n.text("言語を変更すると表示をすぐに更新します。認識言語は音声入力のエンジン設定に従います。"), in: languageSection)
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

  private func addSpeechEngineSettings(to page: NSStackView, layout: SettingsLayout) {
    let section = layout.section(L10n.text("認識エンジン"), in: page)
    let picker = NSPopUpButton()
    settingsControls["engine"] = picker
    picker.autoenablesItems = false
    for engine in SpeechEngine.allCases {
      picker.addItem(withTitle: engine.title)
      picker.lastItem?.isEnabled = engine.supported
    }
    picker.selectItem(at: SpeechEngine.allCases.firstIndex(of: settings.speechEngine) ?? 0)
    picker.target = self
    picker.action = #selector(changeSpeechEngine(_:))
    layout.row(L10n.text("認識エンジン"), control: picker, in: section)

    let status = NSTextField(wrappingLabelWithString: "")
    status.textColor = .secondaryLabelColor
    layout.fullWidth(status, in: section)
    speechRuntimeStatus = status

    let microphone = NSButton(title: L10n.text("マイクを許可"), target: self, action: #selector(requestMicrophone))
    section.addArrangedSubview(microphone)
    microphoneButton = microphone

    let modelPicker = NSPopUpButton()
    settingsControls["whisperModel"] = modelPicker
    modelPicker.addItems(withTitles: ["base", "small"])
    modelPicker.selectItem(at: settings.whisperModel == .small ? 1 : 0)
    modelPicker.target = self
    modelPicker.action = #selector(changeWhisperModel(_:))
    layout.row(L10n.text("Whisper モデル"), control: modelPicker, in: section)

    let qwenPicker = NSPopUpButton()
    settingsControls["qwenModel"] = qwenPicker
    for (model, title): (SpeechModel, String) in [
      (.qwen06, "0.6B (MLX)"), (.qwen17MLX, "1.7B (MLX, 4-bit)"),
    ] {
      qwenPicker.addItem(withTitle: title)
      qwenPicker.lastItem?.representedObject = model.rawValue
    }
    qwenPicker.selectItem(at: qwenPicker.indexOfItem(withRepresentedObject: settings.qwenModel.rawValue))
    qwenPicker.target = self
    qwenPicker.action = #selector(changeQwenModel(_:))
    layout.row(L10n.text("Qwen3-ASR モデル"), control: qwenPicker, in: section)

    let models = layout.section(L10n.text("モデルデータ"), in: page)
    for model in SpeechModel.allCases {
      let label = NSTextField(labelWithString: model.title)
      label.setContentHuggingPriority(.defaultLow, for: .horizontal)
      modelLabels[model] = label
      let button = NSButton(title: "", target: self, action: #selector(manageSpeechModel(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(model.rawValue)
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
      modelButtons[model] = button
      let row = NSStackView(views: [label, button])
      row.alignment = .centerY
      row.spacing = 16
      layout.fullWidth(row, in: models)
      if model == .qwen17HF { legacyQwenModelRow = row }
    }
    refreshModelControls()
  }

  private func refreshModelControls() {
    guard let speechRuntimeStatus else { return }
    let engine = settings.speechEngine
    systemShortcutSection?.isHidden = engine != .system
    settingsControls["whisperModel"]?.isEnabled = engine == .whisper
    settingsControls["qwenModel"]?.isEnabled = engine == .qwen
    switch engine {
    case .system:
      speechRuntimeStatus.stringValue = SpeechEngine.whisper.supported
        ? L10n.text("macOS の音声入力設定を使用します。")
        : L10n.text("ローカルエンジンは Apple Silicon と macOS 14 以降が必要です。")
    case .whisper:
      speechRuntimeStatus.stringValue = engine.executable == nil
        ? L10n.text("必要なランタイム: uv tool install --python 3.12 mlx-whisper==0.4.3 / brew install ffmpeg")
        : L10n.text("ローカルで文字起こしします。認識言語は発話ごとに自動判定します。")
    case .qwen:
      speechRuntimeStatus.stringValue = settings.qwenModel.executable == nil
        ? L10n.text("必要なランタイム: uv tool install --python 3.12 mlx-qwen3-asr==0.4.4")
        : L10n.text("ローカルで文字起こしします。認識言語は発話ごとに自動判定します。")
    }
    let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    microphoneButton?.isHidden = engine == .system || microphoneStatus == .authorized
    microphoneButton?.isEnabled = !microphoneRequestPending
    microphoneButton?.title = microphoneStatus == .notDetermined
      ? L10n.text("マイクを許可") : L10n.text("マイクのシステム設定を開く")

    for model in SpeechModel.allCases {
      let working = modelOperations.contains(model)
      let exists = FileManager.default.fileExists(atPath: model.directory.path)
      if model == .qwen17HF { legacyQwenModelRow?.isHidden = !exists }
      let status = modelStatus[model] ?? (model.installed ? L10n.text("ダウンロード済み") : L10n.text("未ダウンロード"))
      modelLabels[model]?.stringValue = "\(model.title) — \(status)"
      let button = modelButtons[model]
      button?.title = exists ? L10n.text("削除…") : L10n.text("ダウンロード")
      button?.isEnabled = !working && (exists || (model.isSelectable && model.engine.supported))
    }
  }

  @objc private func changeSpeechEngine(_ sender: NSPopUpButton) {
    guard SpeechEngine.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
    let engine = SpeechEngine.allCases[sender.indexOfSelectedItem]
    guard engine.supported else { return }
    cancel()
    localError = nil
    settings.speechEngine = engine
    refreshModelControls()
    updateStatus()
  }

  @objc private func changeWhisperModel(_ sender: NSPopUpButton) {
    cancel()
    localError = nil
    settings.whisperModel = sender.indexOfSelectedItem == 1 ? .small : .base
    updateStatus()
  }

  @objc private func changeQwenModel(_ sender: NSPopUpButton) {
    guard let value = sender.selectedItem?.representedObject as? String,
      let model = SpeechModel(rawValue: value), model.engine == .qwen, model.isSelectable
    else { return }
    cancel()
    localError = nil
    settings.qwenModel = model
    refreshModelControls()
    updateStatus()
  }

  @objc private func requestMicrophone() {
    guard !microphoneRequestPending else { return }
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
      microphoneRequestPending = true
      refreshModelControls()
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          self?.microphoneRequestPending = false
          if granted { self?.localError = nil }
          self?.refreshModelControls()
          self?.updateStatus()
        }
      }
    } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func manageSpeechModel(_ sender: NSButton) {
    guard let identifier = sender.identifier?.rawValue, let model = SpeechModel(rawValue: identifier),
      !modelOperations.contains(model)
    else { return }
    if FileManager.default.fileExists(atPath: model.directory.path) {
      guard let settingsWindow else { return }
      modelOperations.insert(model)
      refreshModelControls()
      let confirmation = NSAlert()
      confirmation.messageText = L10n.format("%@ を削除しますか？", model.title)
      if model.isSelectable {
        confirmation.informativeText = L10n.text("モデルは後からダウンロードできます。")
      }
      confirmation.addButton(withTitle: L10n.text("キャンセル"))
      confirmation.addButton(withTitle: L10n.text("削除"))
      confirmation.beginSheetModal(for: settingsWindow) { [weak self] response in
        guard let self else { return }
        defer {
          self.modelOperations.remove(model)
          self.refreshModelControls()
        }
        guard response == .alertSecondButtonReturn else { return }
        self.cancel()
        do {
          try FileManager.default.removeItem(at: model.directory)
          self.modelStatus[model] = nil
          self.localError = nil
          self.updateStatus()
        } catch {
          self.modelStatus[model] = L10n.text("削除に失敗しました")
        }
      }
    } else if model.isSelectable && model.engine.supported {
      modelOperations.insert(model)
      modelStatus[model] = L10n.text("ダウンロード中…")
      refreshModelControls()
      Task { @MainActor [weak self] in
        do {
          try await SpeechModelStore.download(model)
          self?.modelStatus[model] = nil
          self?.localError = nil
          self?.updateStatus()
        } catch {
          self?.modelStatus[model] = L10n.text("ダウンロードに失敗しました")
        }
        self?.modelOperations.remove(model)
        self?.refreshModelControls()
      }
    }
  }

  @objc private func changeLanguage(_ sender: NSPopUpButton) {
    cancel()
    setLanguage(AppLanguage.allCases[sender.indexOfSelectedItem])
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
    // Do not retain a closed settings window or any of its controls.
    settingsWindow = nil
    settingsControls.removeAll()
    modelButtons.removeAll()
    modelLabels.removeAll()
    legacyQwenModelRow = nil
    speechRuntimeStatus = nil
    systemShortcutSection = nil
    microphoneButton = nil
    permissionStatusView = nil
    // Relinquish activation so macOS returns focus to the previous application.
    NSApp.hide(nil)
  }

  private func setLanguage(_ language: AppLanguage) {
    cancel()
    L10n.language = language
    let wasVisible = settingsWindow?.isVisible == true
    let frame = settingsWindow?.frame
    settingsWindow?.close()
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
  @objc private func changeReleaseDelay(_ sender: NSPopUpButton) {
    settings.releaseDelay = sender.selectedItem?.representedObject as? Double ?? 0.8
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
    relaunch(showSettings: true, failureMessage: L10n.text("権限を再確認できませんでした"))
  }

  @objc private func restart() {
    relaunch(showSettings: false, failureMessage: L10n.text("Push2Talkを再起動できませんでした"))
  }

  private func relaunch(showSettings: Bool, failureMessage: String) {
    guard !isRestarting else { return }
    isRestarting = true
    restartNotice?.orderOut(nil)
    cancel()
    keyboard.stop()
    // Use a new process identity so MenuBarAgent does not retain an invalid scene after exec.
    // Wait for termination to release the single-instance lock before opening the app.
    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
    relaunch.arguments = [
      "-c",
      "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; app=\"$2\"; shift 2; /usr/bin/open -n \"$app\" --args \"$@\"",
      "Push2Talk-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
    ] + (showSettings ? ["--settings"] : []) + (paused ? ["--paused"] : [])
    do {
      try relaunch.run()
      NSApp.terminate(nil)
    } catch {
      isRestarting = false
      checkPermissions()
      let alert = NSAlert()
      alert.messageText = failureMessage
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

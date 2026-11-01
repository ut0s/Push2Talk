import AppKit
import ApplicationServices
import Push2TalkCore
import Push2TalkInput
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = Settings()
  private let keyboard = KeyboardBridge()
  private var session = HoldSession()
  private var target: FocusTarget?
  private var timer: Timer?
  private var permissionsTimer: Timer?
  private var permissionStatusView: PermissionStatusView?
  private var lastPermissionStatus: String?
  private var operationStatus = "動作確認: 右Optionの長押しを待っています"
  private var statusItem: NSStatusItem!
  private var statusLine: NSMenuItem!
  private var pauseItem: NSMenuItem!
  private var paused = false
  private var isRestarting = false
  private var settingsWindow: NSWindow?
  private var observers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    paused = CommandLine.arguments.contains("--paused")
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = settings.menuBarIcon.image(symbol: "mic.slash", description: "Push2Talk")
    let menu = NSMenu()
    statusLine = menu.addItem(withTitle: "準備中…", action: nil, keyEquivalent: "")
    menu.addItem(.separator())
    pauseItem = menu.addItem(withTitle: paused ? "再開" : "一時停止", action: #selector(togglePause), keyEquivalent: "")
    menu.addItem(withTitle: "設定・初期設定…", action: #selector(showSettings), keyEquivalent: ",")
    menu.addItem(withTitle: "権限を再確認", action: #selector(checkPermissions), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Push2Talkを終了", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items where item.action != nil { item.target = self }
    statusItem.menu = menu

    keyboard.onHold = { [weak self] down in self?.hold(down) }
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

  func applicationWillTerminate(_ notification: Notification) {
    cancel()
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

  private func hold(_ down: Bool) {
    // Update the hold indicator even when Dictation cannot start in the current context.
    updateStatus()
    defer { updateStatus() }
    guard !isRestarting, !paused else { reportOperation("開始できません: 一時停止中です"); return }
    guard keyboard.isRunning, settings.setupComplete else {
      reportOperation("開始できません: 初期設定とキー監視の状態を確認してください"); return
    }
    guard !keyboard.secureInputEnabled else {
      reportOperation("開始できません: セキュア入力中です"); return
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
      reportOperation("開始できません: アクセシビリティとキー送信の権限を確認してください"); return
    }
    if down {
      guard session.phase == .idle else { return }
      let flags = CGEventSource.flagsState(.hidSystemState)
      guard flags.intersection([.maskControl, .maskCommand, .maskShift, .maskSecondaryFn]).isEmpty,
        flags.rawValue & 0x20 == 0
      else { reportOperation("開始しません: ほかの修飾キーを離してから右Optionを押してください"); return }
      guard let focus = FocusTarget.capture() else {
        reportOperation("開始しません: 別アプリの入力欄を選んでください（パスワード欄は対象外です）"); return
      }
      target = focus
      session.settleDelay = settings.settleDelay
      session.sendEnter = settings.sendEnter && focus.canSubmitAutomatically
      session.press(at: now)
      reportOperation(focus.canSubmitAutomatically
        ? "長押しを確認中です"
        : "長押しを確認中です（入力欄情報を取得できないため、自動Enterは送りません）")
    } else {
      session.release(at: now)
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
        reportOperation("音声入力の開始ショートカットを送信します")
        keyboard.startDictation(settings.trigger, ifCurrent: { focus.isCurrent })
      case .stop: keyboard.stopDictation(ifCurrent: { focus.isCurrent })
      case .enter:
        let flags = CGEventSource.flagsState(.hidSystemState)
        if target?.isCurrent == true, target?.hasNewText == true,
          flags.intersection([
            .maskControl, .maskCommand, .maskShift, .maskAlternate, .maskSecondaryFn,
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
    operationStatus = message
    permissionStatusView?.updateOperationStatus(message)
    // Diagnostic output contains control status only, never text or audio.
    if CommandLine.arguments.contains("--diagnostics"), let data = ("Push2Talk: \(message)\n").data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }

  private func cancel(nativeEscape: Bool = false) {
    // Ordinary typing while idle must not trigger AX/TCC queries or redraws.
    guard session.phase != .idle else { return }
    let actions = session.cancel()
    reportOperation("操作を中断しました。入力先の変更・クリック・ほかのキー入力を確認してください")
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
    permissionStatusView?.updateOperationStatus(operationStatus)
  }

  private func updateStatus() {
    guard statusLine != nil else { return }
    let title: String
    let symbol: String
    if !AXIsProcessTrusted() {
      title = "アクセシビリティ権限が必要です"
      symbol = "mic.slash"
    } else if !CGPreflightPostEventAccess() {
      title = "キー送信の権限が必要です"
      symbol = "mic.slash"
    } else if paused {
      title = "一時停止中"
      symbol = "mic.slash"
    } else if !settings.setupComplete {
      title = "初期設定を完了してください"
      symbol = "mic.slash"
    } else if keyboard.secureInputEnabled {
      title = "セキュア入力中のためキーを受信できません"
      symbol = "mic.slash"
    } else if !keyboard.isRunning {
      title = "キー監視を開始できません。権限を再確認してください"
      symbol = "mic.slash"
    } else {
      switch session.phase {
      case .idle:
        title = "右Optionを長押しして話す"
        symbol = "mic"
      case .arming:
        title = "長押しを確認中…"
        symbol = "mic"
      case .recording, .stopping:
        title = "音声入力中 — 離すと終了"
        symbol = "mic.fill"
      case .settling:
        title = "文字の確定を待っています…"
        symbol = "ellipsis.bubble"
      }
    }
    statusLine.title = title
    // Reflect the physical hold immediately, including while Dictation is stopping or settling.
    let heldSymbol = symbol == "mic.slash" ? "mic" : symbol
    let displaySymbol = keyboard.isRightOptionHeld ? heldSymbol : "mic.slash"
    statusItem.button?.image = settings.menuBarIcon.image(symbol: displaySymbol, description: title)
    statusItem.button?.title = displaySymbol == "mic.fill" ? " 入力中" : ""
    statusItem.button?.toolTip = "Push2Talk: \(title)"
  }

  @objc private func togglePause() {
    cancel()
    paused.toggle()
    pauseItem.title = paused ? "再開" : "一時停止"
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
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Push2Talk 設定"
    window.isReleasedWhenClosed = false
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    window.contentView?.addSubview(scroll)
    let document = SettingsDocumentView()
    document.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = document
    document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
    ])
    func label(_ text: String) {
      let view = NSTextField(wrappingLabelWithString: text)
      view.preferredMaxLayoutWidth = 512
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    let permissions = PermissionStatusView(
      target: self,
      accessibilityAction: #selector(requestPermission),
      listeningAction: #selector(requestInputMonitoring),
      postingAction: #selector(requestPostingPermission),
      refreshAction: #selector(checkPermissions),
      restartAction: #selector(restart), revealAppAction: #selector(revealCurrentApp)
    )
    permissionStatusView = permissions
    stack.addArrangedSubview(permissions)
    permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    label("マイク・音声認識の許可はmacOS標準音声入力が管理します。Push2Talk自体には不要です。音声入力の有効化とショートカットは、キーボード設定で確認してください。")
    label("右Optionを長押し → 話す → 離す → 音声入力を終了してEnter")
    let iconPicker = NSPopUpButton()
    for icon in MenuBarIcon.allCases {
      iconPicker.addItem(withTitle: icon.title)
      iconPicker.lastItem?.image = icon.image(description: icon.title)
    }
    iconPicker.selectItem(at: MenuBarIcon.allCases.firstIndex(of: settings.menuBarIcon) ?? 0)
    iconPicker.setAccessibilityLabel("メニューバーアイコン")
    iconPicker.target = self
    iconPicker.action = #selector(changeIcon(_:))
    let iconRow = NSStackView(views: [NSTextField(labelWithString: "メニューバーアイコン"), iconPicker])
    iconRow.orientation = .horizontal
    iconRow.spacing = 12
    stack.addArrangedSubview(iconRow)
    label("1. macOSの「キーボード」設定で音声入力をオンにし、下で選んだショートカットに合わせてください。")
    let trigger = NSPopUpButton()
    trigger.addItems(withTitles: DictationTrigger.allCases.map(\.title))
    trigger.selectItem(at: DictationTrigger.allCases.firstIndex(of: settings.trigger) ?? 0)
    trigger.target = self
    trigger.action = #selector(changeTrigger(_:))
    stack.addArrangedSubview(trigger)
    stack.addArrangedSubview(
      NSButton(title: "macOSのキーボード設定を開く", target: self, action: #selector(openKeyboard)))
    let enter = NSButton(
      checkboxWithTitle: "終了後にEnterを送る", target: self, action: #selector(changeEnter(_:)))
    enter.state = settings.sendEnter ? .on : .off
    stack.addArrangedSubview(enter)
    let delay = NSPopUpButton()
    let delays = [0.3, 0.5, 0.8, 1.2, 2.0, 3.0]
    for value in delays {
      delay.addItem(withTitle: "文字確定の待ち時間: \(value)秒")
      delay.lastItem?.representedObject = value
    }
    delay.selectItem(at: delays.firstIndex(of: settings.settleDelay) ?? 2)
    delay.target = self
    delay.action = #selector(changeDelay(_:))
    stack.addArrangedSubview(delay)
    let login = NSButton(
      checkboxWithTitle: "ログイン時に起動", target: self, action: #selector(changeLogin(_:)))
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    stack.addArrangedSubview(login)
    label("Enterは同じ入力欄の文字が変わった場合だけ送信します。短いタップは無視します。Escapeで中断できます。")
    stack.addArrangedSubview(
      NSButton(title: "初期設定を完了・権限を再確認", target: self, action: #selector(completeSetup)))
    settingsWindow = window
    checkPermissions()
    let availableHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 100
    window.setContentSize(NSSize(width: 560, height: min(780, availableHeight)))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func changeTrigger(_ sender: NSPopUpButton) {
    cancel()
    settings.trigger = DictationTrigger.allCases[sender.indexOfSelectedItem]
  }
  @objc private func changeIcon(_ sender: NSPopUpButton) {
    settings.menuBarIcon = MenuBarIcon.allCases[sender.indexOfSelectedItem]
    updateStatus()
  }
  @objc private func changeEnter(_ sender: NSButton) { settings.sendEnter = sender.state == .on }
  @objc private func changeDelay(_ sender: NSPopUpButton) {
    settings.settleDelay = sender.selectedItem?.representedObject as? Double ?? 0.8
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
  @objc private func restart() {
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
      alert.messageText = "再起動できませんでした"
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
      alert.messageText = "ログイン時の起動を変更できませんでした"
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
    sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }
  @objc private func quit() { NSApp.terminate(nil) }
}

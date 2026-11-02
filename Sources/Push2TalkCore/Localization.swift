import Foundation

public enum AppLanguage: String, CaseIterable {
  case system, english = "en", japanese = "ja"

  public var title: String {
    switch self {
    case .system: return L10n.text("システムに合わせる")
    case .english: return "English"
    case .japanese: return "日本語"
    }
  }
}

public enum L10n {
  public static var language: AppLanguage {
    get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage") }
  }

  public static func resolvedLanguage(
    _ language: AppLanguage, preferredLanguages: [String]
  ) -> AppLanguage {
    guard language == .system else { return language }
    for identifier in preferredLanguages {
      let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
      if code == "ja" { return .japanese }
      if code == "en" { return .english }
    }
    return .english
  }

  public static func text(_ key: String) -> String {
    text(key, language: language, preferredLanguages: Locale.preferredLanguages)
  }

  public static func text(
    _ key: String, language: AppLanguage, preferredLanguages: [String] = []
  ) -> String {
    resolvedLanguage(language, preferredLanguages: preferredLanguages) == .japanese
      ? key : english[key] ?? key
  }

  public static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: text(key), arguments: arguments)
  }

  // Japanese source strings are the stable lookup keys and the Japanese translations.
  static let english: [String: String] = [
    "クイック設定": "Quick Settings",
    "Push2Talkについて…": "About Push2Talk…",
    "アップデートを確認…": "Check for Updates…",
    "右Optionを長押ししてmacOSの音声入力を使います。": "Hold Right Option to use macOS Dictation.",
    "開発ビルド": "Development build",
    "開発ビルドです": "This is a development build",
    "配布版のバージョン情報がありません。公開済みのリリースを確認できます。": "This build has no release version metadata. You can view published releases.",
    "通信エラー": "Connection error",
    "配布版が見つかりません": "No release found",
    "公開リリースがまだないか、配布先を利用できません。": "There are no published releases yet, or the distribution repository is unavailable.",
    "配布先から有効なバージョン情報を取得できませんでした。": "The distribution server did not return valid version information.",
    "新しいバージョン %@ があります": "Version %@ is available",
    "現在のバージョン: %@": "Current version: %@",
    "リリースページからZIPをダウンロードし、終了後にアプリを置き換えてください。Homebrewでインストールした場合は、ターミナルで次を実行してください。": "Download the ZIP from the release page, quit the app, and replace it. If you installed with Homebrew, run the following in Terminal.",
    "最新バージョンです": "You are up to date",
    "アップデートを確認できませんでした": "Unable to check for updates",
    "リリースページを開く": "Open Release Page",
    "閉じる": "Close",
    "アップデートを確認中…": "Checking for Updates…",

    "システムに合わせる": "Follow System",
    "言語": "Language",
    "表示言語": "Display Language",
    "言語を変更すると表示をすぐに更新します。音声入力の認識言語はmacOSで設定してください。": "The display updates immediately when you change language. Set the speech recognition language in macOS.",
    "Enterの受信: %@回": "Enter received: %@",
    "%@秒": "%@ seconds",
    "現在のアプリ: %@": "Current app: %@",
    "必要な権限は許可済みです。キー監視: %@": "Required permissions are granted. Keyboard monitoring: %@",
    "最終確認: %@": "Last checked: %@",
    "直近の受信: %@ / flags=0x%@": "Last event: %@ / flags=0x%@",
    "Optionキーの受信: 未確認（右Optionを押して確認）": "Option key events: Not checked (press Right Option to test)",
    "右Option": "Right Option",
    "左Option": "Left Option",
    "右Commandを2回": "Press Right Command twice",
    "Controlを2回": "Press Control twice",
    "左Optionを2回": "Press Left Option twice",
    "左Commandを2回": "Press Left Command twice",
    "Fn / 地球儀を2回（実験的）": "Press Fn / Globe twice (experimental)",
    "確認中…": "Checking…",
    "アクセシビリティ": "Accessibility",
    "設定を開く": "Open Settings",
    "入力監視": "Input Monitoring",
    "キー送信": "Send Key Events",
    "許可を要求": "Request Permission",
    "キー監視の動作": "Keyboard Monitoring",
    "権限とキー監視": "Permissions and Keyboard Monitoring",
    "設定を開いている間は自動更新します。OS設定で許可しても結果が変わらない場合は、「権限を再確認」を押してください。更新前のアプリを許可していた場合は、現在のPush2Talk.appを登録し直してください。": "Updates automatically while settings are open. If permissions do not update after you grant them in System Settings, click Check Permissions. If you authorized an older build, register the current Push2Talk.app again.",
    "現在のアプリをFinderで表示": "Show Current App in Finder",
    "同名の古いビルドが許可されていても、現在のビルドには適用されないことがあります。OS設定の古いPush2Talkを「−」で削除し、「＋」から上の場所のアプリを登録してください。": "Permission for an older build with the same name may not apply to this build. Remove the old Push2Talk entry with “−” in System Settings, then use “+” to add the app at the location above.",
    "許可済み": "Granted",
    "未許可": "Not Granted",
    "入力欄の確認と、長押しキーの操作に必要です。": "Required to check input fields and handle the hold key.",
    "監視可能": "Monitoring Available",
    "個別許可なし": "No Separate Permission",
    "入力監視の個別許可なしで、アクセシビリティによるキー監視が動作しています。": "Keyboard monitoring is working through Accessibility without separate Input Monitoring permission.",
    "キー監視を開始できない場合に設定してください。個別許可がなくても動作する場合があります。": "Check this setting if keyboard monitoring cannot start. It may work without separate permission.",
    "音声入力の開始・終了とEnterを送信できる権限が確認できました。": "Permission to start and stop Dictation and send Enter is confirmed.",
    "アクセシビリティは許可済みですが、キー送信は未許可です。「許可を要求」後、反映されなければ「権限を再確認」を押してください。": "Accessibility is granted, but sending key events is not. Click Request Permission, then click Check Permissions if the status does not update.",
    "音声入力の開始・終了とEnter送信に必要です。アクセシビリティ設定と「許可を要求」で確認してください。": "Required to start and stop Dictation and send Enter. Check Accessibility settings and Request Permission.",
    "一時停止中": "Paused",
    "メニューバーの「再開」でキー監視を再開できます。": "Choose Resume from the menu bar to resume keyboard monitoring.",
    "権限待ち": "Waiting for Permission",
    "アクセシビリティを許可すると、キー監視を自動で再確認します。": "Keyboard monitoring will be retried automatically when Accessibility is granted.",
    "初期設定待ち": "Waiting for Setup",
    "音声入力のショートカットを合わせ、「音声入力」タブの「初期設定を完了」を押してください。": "Match the Dictation shortcuts, then click Complete Setup in the Dictation tab.",
    "セキュア入力で受信停止中": "Blocked by Secure Input",
    "パスワード欄から移動してください。ターミナル等の「セキュアキーボード入力」が有効な場合は解除してください。": "Leave the password field. If Secure Keyboard Entry is enabled in Terminal or another app, turn it off.",
    "監視中": "Monitoring",
    "設定したOptionキーの長押しを受け付けられる状態です。": "Ready to detect a long press of the Option key.",
    "開始失敗": "Failed to Start",
    "権限は許可されていますが、キー監視を開始できません。入力監視の設定を確認し、「権限を再確認」を押してください。": "Permissions are granted, but keyboard monitoring could not start. Check Input Monitoring and click Check Permissions.",
    "アクセシビリティは許可済みです。キー送信の追加確認が必要です。": "Accessibility is granted. Sending key events needs an additional check.",
    "アクセシビリティの許可が必要です。下の「設定を開く」から許可してください。": "Accessibility permission is required. Use Open Settings below to grant it.",
    "権限は許可済みですが、セキュア入力がキーの受信を止めています。": "Permissions are granted, but Secure Input is blocking key events.",
    "必要な権限は許可済み・キー監視も動作中です。": "Required permissions are granted and keyboard monitoring is running.",
    "権限は許可済みですが、キー監視の開始に失敗しています。": "Permissions are granted, but keyboard monitoring failed to start.",
    "マイク": "Microphone",
    "トランシーバー": "Walkie-talkie",
    "メニューバーのみ": "Menu Bar Only",
    "ポップアップのみ": "Popup Only",
    "両方": "Both",
    "入力中": "Dictating",
    "録音中": "Recording",
    "テキストなし": "No Text",
    "⌥ 右Option · 離しています": "⌥ Right Option · Released",
    "待機中": "Idle",
    "右Optionの長押しを待っています": "Waiting for a long press of Right Option",
    "Enterの受信: 0回": "Enter received: 0",
    "ボタン・入力状態": "Key and Input Status",
    "右Optionの押下状態": "Right Option key state",
    "右Optionの物理的な押下とPush2Talkの処理状態を表示します。OSのマイク稼働状態を示すものではありません。": "Shows the physical Right Option key state and Push2Talk’s processing state. This does not indicate whether the macOS microphone is active.",
    "テキスト入力テスト": "Text Input Test",
    "下の欄をクリックして右Optionを長押しし、話してから離してください。手入力もできます。Enterを受信すると改行とカウントが増えます。": "Click the field below, hold Right Option, speak, then release. You can also type. Each Enter adds a newline and increments the count.",
    "音声入力の動作確認テキスト": "Dictation test text",
    "テキストとカウントをクリア": "Clear Text and Count",
    "この欄の内容をPush2Talkが保存することはありません。音声認識はmacOSの音声入力設定に従います。初期設定と権限が必要です。": "Push2Talk does not save this field’s contents. Speech recognition follows macOS Dictation settings. Setup and permissions are required.",
    "⌥ 右Option · 押しています": "⌥ Right Option · Pressed",
    "長押しを確認中…": "Detecting hold…",
    "音声入力中": "Dictating",
    "音声入力を終了中…": "Stopping Dictation…",
    "文字の確定待ち…": "Waiting for text…",
    "動作確認: 右Optionの長押しを待っています": "Input test: Waiting for a long press of Right Option",
    "準備中…": "Preparing…",
    "再開": "Resume",
    "一時停止": "Pause",
    "設定・初期設定…": "Settings & Setup…",
    "権限を再確認": "Check Permissions",
    "Push2Talkを終了": "Quit Push2Talk",
    "開始できません: 一時停止中です": "Cannot start: Paused",
    "開始できません: 初期設定とキー監視の状態を確認してください": "Cannot start: Check setup and keyboard monitoring",
    "開始できません: セキュア入力中です": "Cannot start: Secure Input is active",
    "開始できません: アクセシビリティとキー送信の権限を確認してください": "Cannot start: Check Accessibility and key event permissions",
    "開始しません: ほかの修飾キーを離してから右Optionを押してください": "Not starting: Release other modifiers before pressing Right Option",
    "開始しません: 別アプリの入力欄を選んでください（パスワード欄は対象外です）": "Not starting: Select an input field in another app (password fields are excluded)",
    "長押しを確認中です": "Detecting a long press",
    "長押しを確認中です（入力欄情報を取得できないため、自動Enterは送りません）": "Detecting a long press (input field details are unavailable; automatic Enter is disabled)",
    "音声入力の開始ショートカットを送信します": "Sending the Dictation start shortcut",
    "操作を中断しました。入力先の変更・クリック・ほかのキー入力を確認してください": "Cancelled. Check for a changed input target, click, or other key press.",
    "アクセシビリティ権限が必要です": "Accessibility permission is required",
    "キー送信の権限が必要です": "Permission to send key events is required",
    "初期設定を完了してください": "Complete setup to continue",
    "セキュア入力中のためキーを受信できません": "Secure Input is blocking key events",
    "キー監視を開始できません。権限を再確認してください": "Keyboard monitoring could not start. Check permissions.",
    "右Optionを長押しして話す": "Hold Right Option to speak",
    "音声入力中 — 離すと終了": "Dictating — release to finish",
    "文字の確定を待っています…": "Waiting for text to finalize…",
    "Push2Talk 設定": "Push2Talk Settings",
    "音声入力": "Dictation",
    "右Optionを長押し → 話す → 離して終了": "Hold Right Option → Speak → Release to finish",
    "音声入力の準備": "Dictation Setup",
    "macOSの音声入力をオンにし、OSとPush2Talkで同じショートカットを選んでください。": "Enable macOS Dictation and select the same shortcut in macOS and Push2Talk.",
    "開始ショートカット": "Start Shortcut",
    "macOSのキーボード設定を開く": "Open macOS Keyboard Settings",
    "初期設定を完了・権限を再確認": "Complete Setup & Check Permissions",
    "入力終了後の動作": "After Dictation",
    "通常は終了後にEnterを送る": "Send Enter after dictation by default",
    "右Optionを離す瞬間に、左右どちらかのShiftを押していると、その回だけEnter送信のオン／オフを反転します。設定自体は変わりません。": "Holding either Shift key when you release Right Option reverses the Enter setting for that session only. The saved setting does not change.",
    "例：上の設定がオフ（初期値）の場合\n・Shiftなしで右Optionを離す → 文字だけを入力\n・Shiftを押したまま右Optionを離す → 文字を入力してEnterを送信": "Example with the setting off (default):\n• Release Right Option without Shift → Insert text only\n• Release Right Option while holding Shift → Insert text and send Enter",
    "例：上の設定がオンの場合\n・Shiftなしで右Optionを離す → 文字を入力してEnterを送信\n・Shiftを押したまま右Optionを離す → 文字だけを入力": "Example with the setting on:\n• Release Right Option without Shift → Insert text and send Enter\n• Release Right Option while holding Shift → Insert text only",
    "Shiftは左右どちらでも、両方でも使えます。右Optionを離す前にShiftを押し、そのまま右Optionだけを離してください。右Optionを離した後でShiftを押したり離したりしても、その回の判定は変わりません。": "Use either or both Shift keys. Press Shift before releasing Right Option, then release only Right Option. Changing Shift after releasing Right Option does not affect that session.",
    "文字確定の待ち時間": "Text Finalization Delay",
    "Enterは同じ入力欄に新しい文字がある場合のみ送信します。Shiftを押したままでも、送信するのは修飾キーなしのEnterです。短いタップは無視し、Escapeで中断できます。": "Enter is sent only when the same input field has new text. Enter has no modifiers even if Shift is still held. Short taps are ignored; Escape cancels.",
    "表示": "Appearance",
    "入力状態の表示をカスタマイズ": "Customize the input status display",
    "状態の表示": "Status Display",
    "状態の表示方法": "Show Status In",
    "ポップアップは画面下部に静止アイコンで表示します。「ポップアップのみ」でも設定を開くメニューバーアイコンは残ります。": "The popup shows a static icon at the bottom of the screen. Popup Only keeps the menu bar icon for opening settings.",
    "メニューバー": "Menu Bar",
    "メニューバーアイコン": "Menu Bar Icon",
    "録音中のテキスト": "Recording Text",
    "動作確認": "Input Test",
    "キーの押下と音声入力を、この画面で確認": "Test key presses and Dictation in this window",
    "権限": "Permissions",
    "macOSの許可とキー監視の状態": "macOS permissions and keyboard monitoring status",
    "マイク・音声認識の許可はmacOS標準音声入力が管理します。Push2Talk自体には不要です。": "macOS Dictation manages microphone and speech recognition permissions. Push2Talk itself does not need them.",
    "一般": "General",
    "起動とアプリの管理": "Startup and app management",
    "起動": "Startup",
    "ログイン時に起動": "Launch at Login",
    "設定の変更は自動で保存されます。": "Settings are saved automatically.",
    "権限を再確認できませんでした": "Could Not Check Permissions",
    "ログイン時の起動を変更できませんでした": "Could Not Change Launch at Login",
    "文字の確定待ち": "Waiting for text",
  ]
}

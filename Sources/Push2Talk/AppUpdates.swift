import AppKit
import Push2TalkCore

final class AppUpdates {
  private(set) var checking = false
  var onCheckFinished: (() -> Void)?
  private let bundle: Bundle

  init(bundle: Bundle = .main) { self.bundle = bundle }

  var version: String { bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("開発ビルド") }
  var build: String { bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
  private var releasesURL: URL { URL(string: "https://github.com/ut0s/homebrew-push2talk/releases")! }

  func check() {
    guard !checking else { return }
    guard let current = ReleaseVersion(version) else {
      show(message: L10n.text("開発ビルドです"), detail: L10n.text("配布版のバージョン情報がありません。公開済みのリリースを確認できます。"), releases: true)
      return
    }
    checking = true
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/ut0s/homebrew-push2talk/releases/latest")!)
    request.timeoutInterval = 20
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Push2Talk/\(version)", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.checking = false
        self.onCheckFinished?()
        guard error == nil, let response = response as? HTTPURLResponse else {
          self.failed(error?.localizedDescription ?? L10n.text("通信エラー"))
          return
        }
        if response.statusCode == 404 {
          self.show(message: L10n.text("配布版が見つかりません"), detail: L10n.text("公開リリースがまだないか、配布先を利用できません。"), releases: true)
          return
        }
        guard response.statusCode == 200, let data,
          let release = try? JSONDecoder().decode(Release.self, from: data),
          !release.draft, !release.prerelease, let latest = ReleaseVersion(release.tag_name)
        else {
          self.failed(L10n.text("配布先から有効なバージョン情報を取得できませんでした。"))
          return
        }
        if latest > current {
          self.show(message: L10n.format("新しいバージョン %@ があります", release.tag_name),
            detail: L10n.format("現在のバージョン: %@", self.version) + "\n\n" + L10n.text("リリースページからZIPをダウンロードし、終了後にアプリを置き換えてください。Homebrewでインストールした場合は、ターミナルで次を実行してください。") + "\n\nbrew update && brew upgrade --cask push2talk",
            releases: true)
        } else {
          self.show(message: L10n.text("最新バージョンです"), detail: "Push2Talk \(self.version)", releases: false)
        }
      }
    }.resume()
  }

  private struct Release: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
  }

  private func failed(_ detail: String) {
    show(message: L10n.text("アップデートを確認できませんでした"), detail: detail, releases: true)
  }

  private func show(message: String, detail: String, releases: Bool) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    if releases { alert.addButton(withTitle: L10n.text("リリースページを開く")) }
    alert.addButton(withTitle: L10n.text("閉じる"))
    if alert.runModal() == .alertFirstButtonReturn && releases {
      NSWorkspace.shared.open(releasesURL)
    }
  }
}

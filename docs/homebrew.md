# Homebrew配布

Listo・AltTabAltと同じく、作業用リポジトリを公開せず、専用の公開tapで配布します。
Push2TalkはmacOSアプリなのでFormulaではなくCaskを使います。

| 項目 | Push2Talk |
| --- | --- |
| 公開配布リポジトリ | `ut0s/homebrew-push2talk`（既定値） |
| 通常ファイル | `README.md`、`Casks/push2talk.rb` |
| Releaseタグ | `vX.Y.Z` |
| Release asset | `Push2Talk-X.Y.Z.zip` |
| ZIPの中身 | `Push2Talk.app`のみ（Apple Silicon / Intel） |
| バージョンの管理元 | `packaging/Info.plist`の`CFBundleShortVersionString` |
| 対応OS | macOS 13以降 |

## 準備

XcodeまたはCommand Line Tools、Swift、Git、Ruby、GitHub CLI、Miseが必要です。
GitHub CLIの既定パスは`/opt/homebrew/bin/gh`です。

```sh
mise trust
/opt/homebrew/bin/gh auth status
mise run prepare-release
```

準備モードは未コミットの変更があっても利用でき、GitHubの変更は行いません。
テスト、Universalビルド、アプリ署名の検証、ZIP作成、SHA-256計算、Cask生成、
Ruby構文確認を実行します。既存ZIPからCaskとREADMEだけを再生成する場合は
`mise run prepare-homebrew OWNER/homebrew-NAME X.Y.Z`を使います。`dist/`はGit管理対象外です。

公開前に`dist/Push2Talk.app`を実機で起動し、音声入力・終了・Enter送信・権限を確認します。
自動テストではmacOSの音声認識や他アプリへの実入力は確認できません。

## 公開

バージョンを確認し、作業用リポジトリの変更をコミットします。
公開モードは未コミットの変更がある場合に停止します。
初回は次を実行します。

```sh
P2T_CREATE_PUBLIC_REPO=1 mise run release
```

Miseタスクは公開リポジトリの可視性を確認し、一時ディレクトリにcloneします。
空の配布リポジトリにはREADMEだけの初期コミットを作り、公開ブランチを用意します。
その後、GitHub ReleaseにZIPをアップロードし、実際のZIPのSHA-256を含むCaskとREADMEを
コミット・pushします。ソースコードとそのGit履歴を配布リポジトリにコピーしません。
公開リポジトリのコミットメッセージは英語のConventional Commit形式です。

次回以降は`mise run bump:patch`、`mise run bump:minor`、`mise run bump:major`でplistのバージョンを上げてコミットし、実行します。
ビルド時に`CFBundleVersion`も同じ値に設定します。

```sh
mise run release
```

別の配布先は`P2T_PUBLIC_REPO=OWNER/homebrew-NAME`、
ブランチは`P2T_PUBLIC_BRANCH`で指定できます。
バージョンは`packaging/Info.plist`だけで管理します。環境変数による上書きは禁止し、`P2T_VERSION`が設定されている場合はエラーで停止します。
`mise run prepare-release --skip-checks`または`mise run release --skip-checks`はSwiftテストだけを省略し、ビルドと署名検証は必ず実行します。

同じバージョンで再実行すると、既存のZIPをダウンロードし、そのSHA-256でCaskを生成します。
既存assetは上書きしません。途中失敗した公開の再開に利用できます。
修正の配信には必ず新しいバージョンを使ってください。
再実行で既存assetを使用した場合、ローカルの`.app`は今回のビルド、ZIPは既存公開物になるため、
公開物の確認にはZIPを展開して使います。

## 署名と初回起動

既定はAltTabAltと同様のアドホック署名で、公証は行いません。
生成する公開READMEとCaskに、信頼できる配布元のコピーについて署名を検証してから
アプリ単位で隔離属性を解除する手順を含めています。
署名検証は破損の確認であり、開発者の身元を証明するものではありません。

Developer ID証明書とnotarytoolのプロファイルがある場合:

```sh
P2T_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
P2T_NOTARY_PROFILE='push2talk-notary' \
mise run prepare-release
```

公開時も同じ環境変数を指定します。Miseタスクは署名、公証、staple、ZIP再作成を行います。
署名方式を変更した配布物には新しいバージョンを使用してください。
更新後にアクセシビリティ権限が反映されない場合は再登録とアプリ再起動を行います。

## 利用者向けコマンド

```sh
brew install --cask ut0s/push2talk/push2talk
open -a Push2Talk
brew update
brew upgrade --cask push2talk
```

公開後の確認:

```sh
brew info --cask ut0s/push2talk/push2talk
brew audit --cask --online ut0s/push2talk/push2talk
```

参照: [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)、
[GitHub CLI release create](https://cli.github.com/manual/gh_release_create)。

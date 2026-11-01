#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# != 2 ]]; then
  echo 'Usage: scripts/prepare-homebrew.sh OWNER/homebrew-push2talk VERSION' >&2
  exit 1
fi
distribution_repo="$1"
version="$2"
[[ "$distribution_repo" =~ ^[A-Za-z0-9_-]+/homebrew-[A-Za-z0-9_-]+$ ]] || { echo 'Expected OWNER/homebrew-NAME' >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected x.y.z version' >&2; exit 1; }
archive="$PWD/dist/Push2Talk-$version.zip"
[[ -f "$archive" ]] || { echo "Build $archive first" >&2; exit 1; }
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
tap_dir="$PWD/dist/homebrew-push2talk"
mkdir -p "$tap_dir/Casks"
cat > "$tap_dir/Casks/push2talk.rb" <<EOF
cask "push2talk" do
  version "$version"
  sha256 "$checksum"

  url "https://github.com/$distribution_repo/releases/download/v#{version}/Push2Talk-#{version}.zip"
  name "Push2Talk"
  desc "Hold right Option to use macOS Dictation, release to finish and press Enter"
  homepage "https://github.com/$distribution_repo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"
  app "Push2Talk.app"

  zap trash: "~/Library/Preferences/com.ut0s.Push2Talk.plist"

  caveats do
    puts <<~EOS
      Enable macOS Dictation and set its shortcut to right Command twice.
      Grant Push2Talk Accessibility permission and complete setup in the menu bar.
      Ad-hoc builds are not notarized; macOS may block the first launch.
      For a trusted copy, verify the signature before removing quarantine:
        codesign --verify --deep --strict --verbose=2 /Applications/Push2Talk.app
      If verification succeeds:
        xattr -dr com.apple.quarantine /Applications/Push2Talk.app
        open -a Push2Talk
    EOS
  end
end
EOF
owner="${distribution_repo%%/*}"
tap="${distribution_repo#*/homebrew-}"
cat > "$tap_dir/README.md" <<EOF
# Push2Talk

macOS 13 or later. Hold right Option to start macOS Dictation; release to finish and send Enter.

\`\`\`sh
brew tap $owner/$tap
brew install --cask push2talk
open -a Push2Talk
\`\`\`

Enable Dictation in System Settings → Keyboard and set its shortcut to right Command twice.
Grant Push2Talk Accessibility permission and complete setup in the menu bar.
The app settings support other double-press Dictation shortcuts.

## First launch

Ad-hoc builds are not notarized by Apple and macOS may block downloaded copies.
For a copy from a source you trust, verify its signature first:

\`\`\`sh
codesign --verify --deep --strict --verbose=2 /Applications/Push2Talk.app
\`\`\`

Only after verification succeeds, remove quarantine from this app and launch it:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/Push2Talk.app
open -a Push2Talk
\`\`\`

If verification fails, obtain a fresh copy before proceeding.
Developer ID signed and notarized builds do not normally need this step.

## Update

\`\`\`sh
brew update
brew upgrade --cask push2talk
\`\`\`

If Accessibility permission stops working after an update, re-register Push2Talk
in System Settings and restart the app.
EOF
ruby -c "$tap_dir/Casks/push2talk.rb"
echo "Prepared $tap_dir"
echo "Release asset: $archive"
echo "Install after publication: brew install --cask $owner/$tap/push2talk"

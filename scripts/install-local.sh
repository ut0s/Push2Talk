#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source_app="$PWD/dist/Push2Talk.app"
target_app="/Applications/Push2Talk.app"
launch_app=1
if [[ $# == 1 && "$1" == '--no-launch' ]]; then
  launch_app=0
elif [[ $# != 0 ]]; then
  echo 'Usage: scripts/install-local.sh [--no-launch]' >&2
  exit 1
fi
[[ -x "$source_app/Contents/MacOS/Push2Talk" ]] || { echo 'Build dist/Push2Talk.app first.' >&2; exit 1; }
codesign --verify --strict "$source_app"
if [[ -e "$target_app" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
  [[ "$identifier" == 'com.ut0s.Push2Talk' ]] || { echo 'Destination belongs to another app.' >&2; exit 1; }
fi
if pgrep -x Push2Talk >/dev/null; then
  osascript -e 'tell application id "com.ut0s.Push2Talk" to quit'
  for ((attempt = 0; attempt < 30; attempt++)); do
    if ! pgrep -x Push2Talk >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x Push2Talk >/dev/null; then
    echo 'Push2Talk is still running. Quit it before installing.' >&2
    exit 1
  fi
fi
ditto "$source_app" "$target_app"
codesign --verify --strict "$target_app"
if [[ "$launch_app" == 1 ]]; then
  open "$target_app" --args --settings
fi
echo "Installed $target_app"
echo 'Register this installed copy in System Settings. Rebuilding dist does not replace it.'

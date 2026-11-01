#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${P2T_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'P2T_VERSION must be x.y.z' >&2; exit 1; }
app="$PWD/dist/Push2Talk.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp packaging/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"

if [[ "${P2T_UNIVERSAL:-0}" == 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64 --scratch-path .build --cache-path .build/cache
  binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path --scratch-path .build --cache-path .build/cache)"
else
  swift build -c release --scratch-path .build --cache-path .build/cache
  binary_dir="$(swift build -c release --show-bin-path --scratch-path .build --cache-path .build/cache)"
fi
cp "$binary_dir/Push2Talk" "$app/Contents/MacOS/Push2Talk"

identity="${P2T_SIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
archive="$PWD/dist/Push2Talk-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${P2T_NOTARY_PROFILE:-}" ]]; then
  [[ "$identity" != '-' ]] || { echo 'Notarization requires a Developer ID signing identity.' >&2; exit 1; }
  xcrun notarytool submit "$archive" --keychain-profile "$P2T_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
shasum -a 256 "$archive" > "$archive.sha256"
echo "Built $app"
echo "Archive: $archive"

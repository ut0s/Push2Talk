#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: scripts/release-homebrew.sh [--prepare] [--skip-checks]
       mise run release [--prepare] [--skip-checks]

Default: build, publish a GitHub release, and update the dedicated public Cask.
--prepare: build and generate dist/homebrew-push2talk without publishing.
--skip-checks: skip Swift tests (the app is always rebuilt).

Environment:
  P2T_PUBLIC_REPO=ut0s/homebrew-push2talk
  P2T_PUBLIC_BRANCH=main
  P2T_CREATE_PUBLIC_REPO=1       Create the public repository if missing.
  P2T_SIGN_IDENTITY=...          Optional Developer ID Application identity.
  P2T_NOTARY_PROFILE=...         Optional notarytool keychain profile.
  GH_BIN=/opt/homebrew/bin/gh
  MISE_BIN=/opt/homebrew/bin/mise

Existing release assets are reused and their downloaded SHA-256 is used.
Use a new version to ship changes; existing assets are never overwritten.
HELP
}
die() { echo "Error: $*" >&2; exit 1; }
prepare=0
skip_checks=0
for arg in "$@"; do
  case "$arg" in
    --prepare) prepare=1 ;;
    --skip-checks) skip_checks=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
MISE_BIN="${MISE_BIN:-/opt/homebrew/bin/mise}"
command -v "$MISE_BIN" >/dev/null || die 'Mise is required. Set MISE_BIN to its executable path.'

public_repo="${P2T_PUBLIC_REPO:-ut0s/homebrew-push2talk}"
public_branch="${P2T_PUBLIC_BRANCH:-main}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
[[ "$public_repo" =~ ^[A-Za-z0-9_-]+/homebrew-[A-Za-z0-9_-]+$ ]] || die 'Expected OWNER/homebrew-NAME.'
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Expected x.y.z version.'
git check-ref-format --branch "$public_branch" >/dev/null
GH_BIN="${GH_BIN:-/opt/homebrew/bin/gh}"

create_public_repo=0
if [[ "$prepare" == 0 ]]; then
  [[ -z "$(git status --porcelain)" ]] || die 'Commit or stash changes before publishing; use --prepare for a local preview.'
  git rev-parse --verify HEAD >/dev/null
  command -v "$GH_BIN" >/dev/null || die 'GitHub CLI is required.'
  "$GH_BIN" auth status >/dev/null 2>&1 || die 'Log in with gh auth login first.'
  visibility="$("$GH_BIN" repo view "$public_repo" --json visibility -q '.visibility' 2>/dev/null || true)"
  if [[ -z "$visibility" ]]; then
    [[ "${P2T_CREATE_PUBLIC_REPO:-0}" == 1 ]] || die 'Public repository unavailable. Create it or set P2T_CREATE_PUBLIC_REPO=1.'
    create_public_repo=1
  elif [[ "$visibility" != PUBLIC ]]; then
    die 'The dedicated distribution repository must be public.'
  fi
fi
if [[ "$skip_checks" == 0 ]]; then
  "$MISE_BIN" run test
fi
P2T_UNIVERSAL=1 "$MISE_BIN" run bundle
"$MISE_BIN" run prepare-homebrew "$public_repo" "$version"
if [[ "$prepare" == 1 ]]; then
  echo 'Prepared locally. No GitHub repository or release was changed.'
  exit 0
fi

if [[ "$create_public_repo" == 1 ]]; then
  "$GH_BIN" repo create "$public_repo" --public --description 'Homebrew distribution for Push2Talk'
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
public_dir="$work_dir/tap"
# Use an isolated checkout; never copy source code or its Git history.
"$GH_BIN" repo clone "$public_repo" "$public_dir"
if git -C "$public_dir" show-ref --verify --quiet "refs/remotes/origin/$public_branch"; then
  git -C "$public_dir" checkout -B "$public_branch" "origin/$public_branch"
else
  git -C "$public_dir" checkout -B "$public_branch"
fi
if ! git -C "$public_dir" config user.name >/dev/null || ! git -C "$public_dir" config user.email >/dev/null; then
  login="$("$GH_BIN" api user -q '.login')"
  user_id="$("$GH_BIN" api user -q '.id')"
  git -C "$public_dir" config user.name "$login"
  git -C "$public_dir" config user.email "$user_id+$login@users.noreply.github.com"
fi
if ! git -C "$public_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
  cp dist/homebrew-push2talk/README.md "$public_dir/README.md"
  git -C "$public_dir" add README.md
  git -C "$public_dir" commit -m 'chore: initialize Push2Talk Homebrew distribution'
  git -C "$public_dir" push -u origin "$public_branch"
fi

tag="v$version"
asset_name="Push2Talk-$version.zip"
archive="$PWD/dist/$asset_name"
# An existing asset is authoritative: rebuilding a ZIP changes its checksum.
if "$GH_BIN" release view "$tag" --repo "$public_repo" >/dev/null 2>&1; then
  mkdir -p "$work_dir/download"
  assets="$("$GH_BIN" release view "$tag" --repo "$public_repo" --json assets -q '.assets[].name')"
  if printf '%s\n' "$assets" | /usr/bin/grep -Fxq "$asset_name"; then
    "$GH_BIN" release download "$tag" --repo "$public_repo" --pattern "$asset_name" --dir "$work_dir/download"
    cp "$work_dir/download/$asset_name" "$archive"
  else
    "$GH_BIN" release upload "$tag" "$archive" --repo "$public_repo"
  fi
else
  cat > "$work_dir/notes.md" <<NOTES
Hold right Option to use macOS Dictation; release to finish. Automatic Enter submission is optional and off by default.
Universal macOS app (Apple Silicon / Intel), macOS 13 or later.
See the distribution README for Dictation setup, Accessibility permissions, and first launch instructions.
NOTES
  "$GH_BIN" release create "$tag" "$archive" --repo "$public_repo" --target "$public_branch" \
    --title "Push2Talk $version" --notes-file "$work_dir/notes.md"
fi
shasum -a 256 "$archive" > "$archive.sha256"
"$MISE_BIN" run prepare-homebrew "$public_repo" "$version"
mkdir -p "$public_dir/Casks"
cp dist/homebrew-push2talk/Casks/push2talk.rb "$public_dir/Casks/push2talk.rb"
cp dist/homebrew-push2talk/README.md "$public_dir/README.md"
git -C "$public_dir" add Casks/push2talk.rb README.md
if ! git -C "$public_dir" diff --cached --quiet; then
  git -C "$public_dir" commit -m "chore(release): publish Push2Talk $version"
  git -C "$public_dir" push origin "$public_branch"
fi
owner="${public_repo%%/*}"
tap="${public_repo#*/homebrew-}"
echo "Published https://github.com/$public_repo/releases/tag/$tag"
echo "Install: brew install --cask $owner/$tap/push2talk"

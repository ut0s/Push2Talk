#!/bin/bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo 'Use mise run bump:patch:commit, bump:minor:commit, or bump:major:commit without arguments.' >&2
  exit 1
fi
part="$1"
case "$part" in
  patch|minor|major) ;;
  *) echo 'Expected patch, minor, or major.' >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."
plist='packaging/Info.plist'
git ls-files --error-unmatch "$plist" >/dev/null
status="$(git status --porcelain --untracked-files=all)"
if [[ -n "$status" ]]; then
  echo 'Error: Uncommitted changes exist. Commit or stash all changes before bumping the version.' >&2
  exit 1
fi

current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
# Ruby integers avoid overflow when incrementing version components.
next="$(/usr/bin/ruby -e '
  version, part = ARGV
  abort "CFBundleShortVersionString must be x.y.z without leading zeros" unless /\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/.match(version)
  components = version.split(".").map(&:to_i)
  index = {"major" => 0, "minor" => 1, "patch" => 2}.fetch(part)
  components[index] += 1
  ((index + 1)...3).each { |i| components[i] = 0 }
  puts components.join(".")
' "$current" "$part")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $next" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$plist"
git commit --only -m "chore(release): bump version to $next" -- "$plist"
echo "Version: $current -> $next"

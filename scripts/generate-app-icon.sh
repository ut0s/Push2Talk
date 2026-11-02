#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo 'Usage: generate-app-icon.sh SOURCE.png OUTPUT.icns' >&2
  exit 1
fi

source_png="$1"
output_icns="$2"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$output_icns"

#!/bin/zsh
# 用 Icon Composer 自带的 ictool 渲染 AppIcon.icon 的 6 种外观 × 2 代设计，拼成一张对照图
# 用法：Scripts/render-icon.sh <输出目录>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?输出目录}
ICT="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p "$OUT"
for gen in 26 27; do
  for r in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    "$ICT" Sources/AppIcon.icon --export-image --output-file "$OUT/$gen-$r.png" --platform macOS \
      --rendition $r --width 256 --height 256 --scale 1 --design-generation $gen >/dev/null
  done
done
swift Scripts/contact-sheet.swift "$OUT"

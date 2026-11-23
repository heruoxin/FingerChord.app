#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
# Chrome renders the SVG blur filters exactly; a 2x capture downsamples to clean edges.
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
icons=Resources/AppIcon.xcassets/AppIcon.appiconset
capture=$(mktemp -d)
trap 'rm -rf "$capture"' EXIT
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1024,1024 \
    --screenshot="$capture/icon.png" "file://$PWD/Resources/AppIcon.svg" >/dev/null 2>&1
for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$capture/icon.png" --out "$icons/icon-$size.png" >/dev/null
done

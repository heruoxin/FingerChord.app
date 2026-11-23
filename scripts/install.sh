#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
destination="/Applications/FingerChord.app"
if pgrep -x FingerChord >/dev/null; then
    print -u2 '请先在指间设置中点“退出指间”，再运行安装脚本。'
    exit 1
fi
./scripts/build.sh
# Move, not copy: a second bundle left in dist shows up in Spotlight as another app.
staged="$destination.new"
rm -rf "$staged"
mv dist/FingerChord.app "$staged"
codesign --verify --strict "$staged"
rm -rf "$destination"
mv "$staged" "$destination"
open "$destination" --args --settings
print "已安装：$destination"

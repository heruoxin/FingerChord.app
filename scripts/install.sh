#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
destination="/Applications/FingerChord.app"
if pgrep -x FingerChord >/dev/null; then
    print -u2 '请先在指间设置中点“退出指间”，再运行安装脚本。'
    exit 1
fi
# Replace the whole bundle: merging into it would keep files a newer build no longer ships.
staged="$destination.new"
rm -rf "$staged"
ditto dist/FingerChord.app "$staged"
codesign --verify --strict "$staged"
rm -rf "$destination"
mv "$staged" "$destination"
open "$destination" --args --settings
print "已安装：$destination"

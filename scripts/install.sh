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
ditto dist/FingerChord.app "$destination"
codesign --verify --strict "$destination"
open "$destination" --args --settings
print "已安装：$destination"

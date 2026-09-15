#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app_path="$PWD/dist/FingerChord.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/FingerChord" "$app_path/Contents/MacOS/FingerChord"
cp Resources/Info.plist "$app_path/Contents/Info.plist"

# Use a persistent local identity so subsequent builds keep the same TCC identity.
# Override with FINGERCHORD_SIGN_IDENTITY if the preferred certificate changes.
sign_identity=${FINGERCHORD_SIGN_IDENTITY:-}
if [[ -z "$sign_identity" ]]; then
    sign_identity=$(security find-identity -v -p codesigning | sed -nE '/Developer ID Application:/s/.*\) ([A-F0-9]+) .*/\1/p' | head -1)
fi
if [[ -z "$sign_identity" ]]; then
    sign_identity=$(security find-identity -v -p codesigning | sed -nE '/Apple Development:/s/.*\) ([A-F0-9]+) .*/\1/p' | head -1)
fi
if [[ -z "$sign_identity" ]]; then
    print -u2 '未找到本机代码签名证书。请设置 FINGERCHORD_SIGN_IDENTITY。'
    exit 1
fi
codesign --force --sign "$sign_identity" --options runtime --timestamp=none "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
print "已构建：$app_path"

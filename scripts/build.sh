#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
mkdir -p dist
staging=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app_path="$staging/FingerChord.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/FingerChord" "$app_path/Contents/MacOS/FingerChord"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/Icon/FingerChord.icns LICENSE ACKNOWLEDGMENTS.md "$app_path/Contents/Resources/"
# L10n resolves this packaged resource bundle before falling back to SwiftPM paths.
cp -R "$binary_dir/FingerChord_FingerChord.bundle" "$app_path/Contents/Resources/"
for language in en zh-Hans zh-Hant; do
    mkdir -p "$app_path/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$app_path/Contents/Resources/$language.lproj/"
done

# A stable certificate keeps Accessibility/Input Monitoring grants across local builds.
# Without a certificate, ad-hoc signing supports local builds but may need reauthorization.
sign_identity=${FINGERCHORD_SIGN_IDENTITY:-}
if [[ -z "$sign_identity" ]]; then
    identities=$(security find-identity -v -p codesigning)
    sign_identity=$(print -r -- "$identities" | sed -nE '/Developer ID Application:/s/.*\) ([A-F0-9]+) .*/\1/p' | head -1)
    if [[ -z "$sign_identity" ]]; then
        sign_identity=$(print -r -- "$identities" | sed -nE '/Apple Development:/s/.*\) ([A-F0-9]+) .*/\1/p' | head -1)
    fi
fi
sign_identity=${sign_identity:--}
codesign --force --sign "$sign_identity" --options runtime --timestamp=none "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
# Replace only the generated bundle after a successful build and signature check.
rm -rf "$PWD/dist/FingerChord.app"
mv "$app_path" "$PWD/dist/FingerChord.app"
print "Built: $PWD/dist/FingerChord.app"

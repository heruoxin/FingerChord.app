#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh --release
# Finder records the working image's path in .DS_Store, so keep it out of the home folder.
staging=$(mktemp -d /tmp/fingerchord.XXXXXX)
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/content"
mv dist/FingerChord.app "$staging/content/"
rm -f dist/FingerChord.dmg dist/FingerChord.dmg.sha256
create-dmg --volname FingerChord --volicon "$staging/content/FingerChord.app/Contents/Resources/AppIcon.icns" \
    --background Resources/DMGBackground.png --window-pos 200 120 --window-size 600 400 --icon-size 100 \
    --icon FingerChord.app 150 155 --hide-extension FingerChord.app --app-drop-link 450 155 \
    --codesign "${FINGERCHORD_SIGN_IDENTITY:-Developer ID Application}" \
    --notarize "${FINGERCHORD_NOTARY_PROFILE:-FingerChord}" "$staging/FingerChord.dmg" "$staging/content"
mv "$staging/FingerChord.dmg" dist/
(cd dist && shasum -a 256 FingerChord.dmg > FingerChord.dmg.sha256)
print "Packaged: $PWD/dist/FingerChord.dmg"

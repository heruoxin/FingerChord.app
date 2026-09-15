#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
architecture=$(uname -m)
archive="FingerChord-$version-macos-$architecture.zip"
rm -f "dist/$archive"
ditto -c -k --sequesterRsrc --keepParent dist/FingerChord.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
print "Packaged: $PWD/dist/$archive"

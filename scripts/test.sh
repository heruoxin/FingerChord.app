#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift test

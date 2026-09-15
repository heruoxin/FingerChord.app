#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "${0:A:h:h}"
swift test

#!/bin/bash
# One command to get the latest and open it in Xcode:
#   ./scripts/dev.sh
set -euo pipefail
cd "$(dirname "$0")/.."

git pull --ff-only
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
open PocketBrains.xcodeproj

echo ""
echo "If models changed since your last run, delete the app from the"
echo "simulator once (long-press → Remove App) before building."

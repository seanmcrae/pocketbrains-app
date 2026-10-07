#!/usr/bin/env bash
# Pre-publication guard: fails if the tracked tree contains machine-specific
# paths, credential-shaped strings, or unexpectedly large files.
# Runs in CI on Linux and locally on macOS:  ./scripts/check-hygiene.sh
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
files=$(git ls-files | grep -v '^scripts/check-hygiene.sh$')

check() {
  local label="$1" pattern="$2"
  local hits
  hits=$(echo "$files" | xargs -d '\n' grep -nIE "$pattern" -- 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "::error::$label"
    echo "$hits"
    status=1
  fi
}

check "Absolute home-directory path" '/Users/[A-Za-z0-9._-]+|/home/[a-z][a-z0-9_-]+/'
check "Private key material" '-----BEGIN [A-Z ]*PRIVATE KEY'
check "Cloud or API credential" 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}'
check "Hard-coded signing team" 'DEVELOPMENT_TEAM: *"?[A-Z0-9]{10}"?'

# Anything over 2 MB needs a deliberate decision (the app icon is ~1 MB).
while IFS= read -r f; do
  size=$(wc -c < "$f")
  if [ "$size" -gt 2097152 ]; then
    echo "::error::Large file ($size bytes): $f"
    status=1
  fi
done <<< "$files"

[ "$status" -eq 0 ] && echo "Hygiene check passed: $(echo "$files" | wc -l | tr -d ' ') tracked files scanned."
exit "$status"

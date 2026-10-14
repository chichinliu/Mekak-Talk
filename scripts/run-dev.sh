#!/bin/bash
# Builds and opens "Hyday Talk Dev". Both builds listen for fn, so the release build is quit first.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
for name in "Hyday Talk" "Hyday Talk Dev"; do osascript -e "quit app \"$name\"" >/dev/null 2>&1 || true; done
sleep 1
VARIANT=dev bash scripts/build-app.sh
open "dist/Hyday Talk Dev.app"

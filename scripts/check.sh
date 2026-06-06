#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

bash -n scripts/*.sh
./scripts/check-docs.sh
./macos/BGMManager/build.sh >/dev/null
codesign --verify --deep --strict "dist/BGM Manager.app"

echo "All checks passed."

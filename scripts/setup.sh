#!/usr/bin/env bash
# Generates the standard Flutter project skeleton (Gradle wrapper, Xcode
# project, generated plugin registrant, etc - all the boilerplate that
# isn't hand-written) and then overlays the custom source in custom/.
#
# Requires: Flutter SDK installed and on PATH. Run from the repo root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found on PATH. Install it first: https://flutter.dev/docs/get-started/install"
  exit 1
fi

echo "==> Generating base Flutter project (app/)"
flutter create --org com.example -i swift -a kotlin app

echo "==> Copying Dart source"
rm -rf app/lib
cp -r

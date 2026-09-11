#!/usr/bin/env bash
set -euo pipefail
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter stable and rerun this script." >&2
  exit 1
fi
flutter create . --platforms=android,ios --project-name=livestar --org=com.livestar.app
flutter pub get
printf '\nPlatform folders generated. Review Android/iOS identifiers and signing before release.\n'

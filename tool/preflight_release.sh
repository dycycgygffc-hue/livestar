#!/usr/bin/env bash
set -euo pipefail
command -v flutter >/dev/null || { echo 'FAIL: Flutter not found'; exit 1; }
flutter --version
flutter pub get
flutter analyze
if [[ "${API_URL:-}" == "" ]]; then echo 'WARN: API_URL is not set; release build must use --dart-define=API_URL=...'; fi
if [[ "${API_URL:-}" == http://* ]]; then echo 'FAIL: API_URL must use HTTPS in release'; exit 1; fi
if [[ -f android/key.properties ]]; then echo 'Android signing properties detected locally (not committed).'; else echo 'INFO: android/key.properties not present; signing will need to be configured.'; fi
printf '\nPreflight complete.\n'

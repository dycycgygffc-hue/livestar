#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $1" >&2; exit 1; }
[[ -f "$ROOT/pubspec.yaml" ]] || fail "pubspec.yaml missing"
[[ -f "$ROOT/backend/src/server.js" ]] || fail "backend missing"
node --check "$ROOT/backend/src/server.js"
python3 - <<'PY' "$ROOT/backend/docker-compose.yml"
import sys,yaml
with open(sys.argv[1]) as f: d=yaml.safe_load(f)
assert 'services' in d and 'postgres' in d['services'] and 'livekit' in d['services']
assert 'volumes' in d and 'livestar_pg' in d['volumes']
assert '--dev' not in str(d)
print('docker-compose structure OK')
PY
if grep -R "devkey\|devsecret\|ws://localhost:7880" -n "$ROOT/backend/src"; then fail "development LiveKit fallback remains"; fi
if grep -R "10.0.2.2" -n "$ROOT/lib" "$ROOT/android" "$ROOT/ios" 2>/dev/null; then fail "emulator API address remains in source"; fi
if grep -R "devCode" -n "$ROOT/lib"; then fail "OTP devCode exposed by Flutter source"; fi
echo "Production validation passed."

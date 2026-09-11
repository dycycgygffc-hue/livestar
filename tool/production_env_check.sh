#!/usr/bin/env bash
set -euo pipefail
required=(DATABASE_URL JWT_SECRET CORS_ORIGINS LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET)
for key in "${required[@]}"; do [[ -n "${!key:-}" ]] || { echo "FAIL: $key is required"; exit 1; }; done
[[ "${LIVEKIT_URL}" == wss://* ]] || { echo 'FAIL: LIVEKIT_URL must use wss://'; exit 1; }
(( ${#JWT_SECRET} >= 32 )) || { echo 'FAIL: JWT_SECRET must be >=32 chars'; exit 1; }
[[ "${CORS_ORIGINS}" != '*' ]] || { echo 'FAIL: wildcard CORS is not allowed'; exit 1; }
[[ "${OTP_DEV_MODE:-false}" != 'true' ]] || { echo 'FAIL: OTP_DEV_MODE=true'; exit 1; }
[[ "${ALLOW_TEST_BILLING:-false}" != 'true' ]] || { echo 'FAIL: ALLOW_TEST_BILLING=true'; exit 1; }
echo 'Production environment checks passed.'

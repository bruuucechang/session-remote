#!/usr/bin/env bash
# 假資料後端：UI 測試用，不碰真的 iTerm2、不送字進任何 session（backend/app/repositories/fake.py）。
#   tools/fake-backend.sh            前景跑在 0.0.0.0:${FAKE_PORT:-5390}，通行碼 uitest
# 5390 是 proj 配給這個專案的 WEB_PORT（本專案沒有網頁前端，空著），手機走 Tailscale 連得到。
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$DIR/backend/tests/fixtures/uitest"
# tools/uitest.sh 會傳 SR_FAKE_TMP 進來並在結束時清掉；直接跑時自己開一個暫存目錄
TMP="${SR_FAKE_TMP:-$(mktemp -d "${TMPDIR:-/tmp}/sr-uitest.XXXXXX")}"
mkdir -p "$TMP/data" "$TMP/context" "$TMP/Projects"/{hello,ledger,atlas,notes}
export SR_FAKE="$FIX/scenario.json" SESSION_REMOTE_DATA="$TMP/data" SESSION_REMOTE_TOKEN=uitest \
  ACCOUNTS_FILE="$FIX/accounts.json" QUOTA_FILE="$TMP/quota.json" CONTEXT_DIR="$TMP/context" \
  PROJECTS_ROOT="$TMP/Projects" APNS_KEY_PATH= APNS_KEY_ID=
cd "$DIR/backend"
.venv/bin/python -c 'import json; from app import config; from app.repositories import fake, store; store.save("sessions", fake.records())'
echo "假資料後端：資料在 $TMP" >&2
exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "${FAKE_PORT:-5390}" --timeout-graceful-shutdown 2

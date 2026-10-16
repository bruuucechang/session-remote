#!/usr/bin/env bash
# 在無頭模擬器跑 iOS app 並截圖（不開 Simulator 視窗、不搶畫面）。
#   tools/sim-shot.sh <輸出.png> [要打開的 iTerm2 分頁 id]
# 要先有 build：cd ios && xcodebuild ... -derivedDataPath build/dd build
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV="${SIM_DEVICE:-iPhone 17 Pro}"
UDID=$(xcrun simctl list devices available | grep -m1 "    $DEV (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$DIR/ios/build/dd/Build/Products/Debug-iphonesimulator/SessionRemote.app"
xcrun simctl terminate "$UDID" com.bruuucechang.sessionremote 2>/dev/null || true
TOKEN=$(grep ^SESSION_REMOTE_TOKEN "$DIR/.env" | cut -d= -f2)
SIMCTL_CHILD_SR_URL="http://127.0.0.1:${API_PORT:-5391}" SIMCTL_CHILD_SR_TOKEN="$TOKEN" SIMCTL_CHILD_SR_OPEN="${2:-}" \
  xcrun simctl launch "$UDID" com.bruuucechang.sessionremote >/dev/null
sleep "${WAIT:-5}"
xcrun simctl io "$UDID" screenshot "$1" >/dev/null 2>&1
echo "$1"

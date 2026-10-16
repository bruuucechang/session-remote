#!/usr/bin/env bash
# 編譯（開發簽章）並裝到 iPhone。
#   tools/install-ios.sh          裝一次，手機不在就失敗
#   tools/install-ios.sh --wait   每分鐘試一次，直到手機回到同一個網路／接上線為止（最多 12 小時）
# 手機要：同一個 Wi-Fi 或用線接著、開著開發者模式、解鎖過一次。
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICE="${IOS_DEVICE:-1509AA83-4924-55CD-A644-B333A3C59204}"   # 「PlayStation 6」iPhone 17 Pro
APP="$DIR/ios/build/dd/Build/Products/Debug-iphoneos/SessionRemote.app"

(cd "$DIR/ios" && xcodegen generate -q && xcodebuild -project SessionRemote.xcodeproj -scheme SessionRemote \
  -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/dd -allowProvisioningUpdates \
  -quiet build) || { echo "✗ 編譯失敗"; exit 1; }

try() { xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1; }
deadline=$(( $(date +%s) + 12*3600 ))
while :; do
  out=$(try) && { echo "✓ 已裝到 iPhone"; xcrun devicectl device process launch --device "$DEVICE" com.bruuucechang.sessionremote >/dev/null 2>&1; exit 0; }
  if [ "${1:-}" != "--wait" ] || [ "$(date +%s)" -gt "$deadline" ]; then
    echo "✗ 安裝失敗："; echo "$out" | tail -3; exit 1
  fi
  sleep 60
done

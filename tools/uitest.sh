#!/usr/bin/env bash
# 自動化 UI 測試：起假資料後端 → 在 iPhone（預設）或模擬器跑 XCUITest → 匯出截圖 → 收掉後端。
#   tools/uitest.sh                    接著的 iPhone（手機要解鎖；跑的期間畫面被佔住）
#   tools/uitest.sh --sim              無頭模擬器
#   tools/uitest.sh [--sim] -only-testing:SessionRemoteUITests/SmokeTests   其餘參數原樣交給 xcodebuild
# 截圖與結果在 ios/build/uitest/<時間>/（shots/*.png、result.xcresult）。
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICE="${IOS_DEVICE:-1509AA83-4924-55CD-A644-B333A3C59204}"   # 「PlayStation 6」iPhone 17 Pro
PORT="${FAKE_PORT:-5390}"
SIM=0; [ "${1:-}" = "--sim" ] && { SIM=1; shift; }

if [ $SIM = 1 ]; then
  UDID=$(xcrun simctl list devices available | grep -m1 "    ${SIM_DEVICE:-iPhone 17 Pro} (" | grep -oE '[0-9A-F-]{36}')
  [ -n "$UDID" ] || { echo "✗ 找不到模擬器「${SIM_DEVICE:-iPhone 17 Pro}」"; exit 1; }
  DEST="id=$UDID"; URL="http://127.0.0.1:$PORT"
  # 重開一次：simctl boot 會把當下的 SIMCTL_CHILD_* 留在模擬器的系統環境裡，之後每次啟動 app 都帶著（例如 SR_NEW=1）
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1
  env -u SIMCTL_CHILD_SR_NEW $(env | grep -o '^SIMCTL_CHILD_[A-Z_]*' | sed 's/^/-u /') xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b >/dev/null
else
  DEST="id=$DEVICE"; URL="http://$(tailscale ip -4 | head -1):$PORT"
fi

OUT="$DIR/ios/build/uitest/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT/shots"
# 埠上已經有人（例如上次沒收掉的假後端）就停：不然健康檢查會打中舊的，測試跑在舊程式上
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null && { echo "✗ 埠 $PORT 已被佔用：lsof -nP -iTCP:$PORT -sTCP:LISTEN"; exit 1; }
SR_FAKE_TMP="$OUT/fake-data" FAKE_PORT=$PORT "$DIR/tools/fake-backend.sh" >"$OUT/backend.log" 2>&1 &
BE=$!
# 跑的期間有別的程序也綁上這個埠（例如別的 session 跑 uvicorn --port 5390，綁 127.0.0.1 會搶走本機的請求），
# 記下來最後警告：症狀是 app 拿到「Not Found」、假後端卻沒收到請求（2026-10-25 模擬器撞過）
( while kill -0 $BE 2>/dev/null; do
    for p in $(lsof -tnP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -vx "$BE"); do
      ps -o pid=,command= -p "$p" >>"$OUT/foreign.txt"
    done
    sleep 2
  done ) &
WATCH=$!
trap 'kill $BE $WATCH 2>/dev/null; wait $BE 2>/dev/null; rm -rf "$OUT/fake-data"' EXIT
for _ in $(seq 40); do kill -0 $BE 2>/dev/null || break; curl -sf "localhost:$PORT/health" >/dev/null && break; sleep 0.25; done
kill -0 $BE 2>/dev/null && curl -sf "localhost:$PORT/health" >/dev/null || { echo "✗ 假資料後端起不來："; tail -5 "$OUT/backend.log"; exit 1; }

(cd "$DIR/ios" && xcodegen generate -q)
# TEST_RUNNER_ 開頭的「環境變數」才會傳進測試程式（寫成 xcodebuild 參數是 build setting，傳不進去）
TEST_RUNNER_SR_TEST_URL="$URL" xcodebuild -project "$DIR/ios/SessionRemote.xcodeproj" -scheme SessionRemote \
  -destination "$DEST" -derivedDataPath "$DIR/ios/build/dd" -allowProvisioningUpdates \
  -resultBundlePath "$OUT/result.xcresult" test "$@" >"$OUT/xcodebuild.log" 2>&1
RC=$?
grep -E "Test Case .*(passed|failed)|error:|XCTAssert|Executed [0-9]+ test" "$OUT/xcodebuild.log" | tail -40
xcrun xcresulttool export attachments --path "$OUT/result.xcresult" --output-path "$OUT/shots" >/dev/null 2>&1 || true
# 匯出的檔名是 UUID，照 manifest 改成「測試名-截圖名.png」
python3 - "$OUT/shots" <<'PY'
import json, os, sys
d = sys.argv[1]
try:
    m = json.load(open(os.path.join(d, "manifest.json")))
except FileNotFoundError:
    sys.exit()
for t in m:
    name = t.get("testIdentifier", "test").split("/")[-1].rstrip("()")
    for a in t.get("attachments", []):
        src = os.path.join(d, a["exportedFileName"])
        human = a.get("suggestedHumanReadableName", a["exportedFileName"]).split("_")[0]
        ext = os.path.splitext(a["exportedFileName"])[1]
        if os.path.exists(src):
            os.rename(src, os.path.join(d, f"{name}-{human}{ext}"))
PY
[ -s "$OUT/foreign.txt" ] && { echo "⚠ 跑的期間有別的程序在聽 $PORT（結果可能被它搶走）："; sort -u "$OUT/foreign.txt"; }
echo "截圖：$OUT/shots"
[ $RC = 0 ] && echo "✓ UI 測試全過" || echo "✗ UI 測試失敗（$OUT/xcodebuild.log）"
exit $RC

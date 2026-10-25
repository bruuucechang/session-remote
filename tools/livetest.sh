#!/usr/bin/env bash
# B5 實測：在 ~/Projects/.uitest-sandbox/run-<時間> 開一個真的 Claude session，用接著的 iPhone 從 app 把每種互動做一次
# （ios/UITests/LiveTests.swift）。連的是正式服務（5391），但測試每一步都核對畫面上的 session 是這個資料夾的才動手。
#   tools/livetest.sh        手機要解鎖；會在 iTerm2 多開一個分頁，跑完測試自己關掉
# 測試資料夾的 .claude/settings.json：模型用 haiku 省額度、權限模式 default、touch 一定要問（逼出權限提示）。
# 每次都是新資料夾，所以一定會先問「信任這個資料夾嗎」。
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOKEN=$(grep ^SESSION_REMOTE_TOKEN "$DIR/.env" | cut -d= -f2)
PORT=$(grep -E '^(PORT|API_PORT)=' "$DIR/.env" | head -1 | cut -d= -f2); PORT=${PORT:-5391}
curl -sf "localhost:$PORT/health" >/dev/null || { echo "✗ 正式服務（${PORT}）沒在跑：tools/install-agent.sh"; exit 1; }
SANDBOX="$HOME/Projects/.uitest-sandbox/run-$(date +%m%d-%H%M%S)"
mkdir -p "$SANDBOX/.claude"
cat >"$SANDBOX/.claude/settings.json" <<'JSON'
{"model": "haiku", "permissions": {"defaultMode": "default", "ask": ["Bash(touch:*)"]}}
JSON
echo "測試資料夾：$SANDBOX"
export TEST_RUNNER_SR_LIVE_URL="http://$(tailscale ip -4 | head -1):$PORT" TEST_RUNNER_SR_LIVE_TOKEN="$TOKEN" TEST_RUNNER_SR_LIVE_DIR="$SANDBOX"
"$DIR/tools/uitest.sh" -only-testing:SessionRemoteUITests/LiveTests "$@"
RC=$?
# 筆電這邊再核對一次：權限提示按了允許，檔案就該真的建出來
[ -f "$SANDBOX/uitest-ok.txt" ] && echo "✓ 筆電上有 uitest-ok.txt（權限提示的允許真的生效）" || { echo "✗ 筆電上沒有 uitest-ok.txt"; RC=1; }
exit $RC

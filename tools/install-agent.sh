#!/usr/bin/env bash
# 安裝／重裝 launchd 常駐服務。重跑安全（先 bootout 再 bootstrap）。
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HOME/Library/LaunchAgents/com.bruce.session-remote.plist"
plutil -lint "$DIR/launchd/com.bruce.session-remote.plist" >/dev/null
cp "$DIR/launchd/com.bruce.session-remote.plist" "$DST"
launchctl bootout "gui/$(id -u)/com.bruce.session-remote" 2>/dev/null || true
# bootout 是非同步的：還沒卸載完就 bootstrap 會「Bootstrap failed: 5」、服務整個停掉（2026-10-26 撞過）
for _ in $(seq 20); do launchctl print "gui/$(id -u)/com.bruce.session-remote" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$DST"
for i in $(seq 30); do
  curl -sf "http://127.0.0.1:${API_PORT:-5391}/health" >/dev/null && { echo "✓ 服務起來了"; exit 0; }
  sleep 1
done
echo "✗ 30 秒內沒起來，看 /tmp/session-remote.log" >&2; exit 1

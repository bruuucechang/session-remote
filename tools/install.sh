#!/usr/bin/env bash
# 公開版的 Mac 端安裝：一個指令裝好。重跑安全。
#
#   tools/install.sh            實際安裝
#   tools/install.sh --dry-run  只印會做什麼，不改任何東西
#
# 做的事：檢查 iTerm2／node／python3／Tailscale → 建 .env（產通行碼）→ 建 venv →
# 把 hook 掛進 ~/.claude/settings.json（先備份）→ 裝 launchd 常駐服務 → 印配對 QR code。
# 作者自己那台用的是 tools/install-agent.sh（hook 掛在 skills repo），這支不碰它。
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
LABEL="com.sessionremote.server"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$HOME/Library/Logs/session-remote.log"

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "  （試跑）$*"; else "$@"; fi; }

# --- 檢查 ---
missing=0
[ -d /Applications/iTerm.app ] || { say "✗ 沒有 iTerm2（https://iterm2.com）；只有 iTerm2 裡的 Claude Code 會出現在手機上"; missing=1; }
command -v node >/dev/null || { say "✗ 沒有 node（Claude Code 的 hook 要用）"; missing=1; }
# 後端要 Python 3.10 以上（型別寫法與 requirements 的版本）；Apple 內建的 python3 是 3.9，挑一個夠新的
PY=""
for c in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  "$p" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { PY="$p"; break; }
done
[ -n "$PY" ] || { say "✗ 沒有 Python 3.10 以上（Apple 內建的是 3.9）；用 brew install python 或 python.org 裝一個"; missing=1; }
TS=""
if command -v tailscale >/dev/null; then TS="tailscale"
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
else say "✗ 沒有 Tailscale（https://tailscale.com，Mac 和 iPhone 都要裝、登入同一個帳號）"; missing=1; fi
[ "$missing" = 0 ] || exit 1
say "✓ iTerm2、node、Python（${PY}）、Tailscale 都在"

# --- .env 與通行碼 ---
if [ ! -f "$DIR/.env" ]; then run cp "$DIR/.env.example" "$DIR/.env"; fi
if [ "$DRY" = 0 ] && ! grep -qE '^SESSION_REMOTE_TOKEN=.+' "$DIR/.env"; then
  TOKEN="$("$PY" -c 'import secrets;print(secrets.token_urlsafe(24))')"
  "$PY" - "$DIR/.env" "$TOKEN" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
line = f"SESSION_REMOTE_TOKEN={sys.argv[2]}"
t = re.sub(r"(?m)^SESSION_REMOTE_TOKEN=.*$", line, t) if re.search(r"(?m)^SESSION_REMOTE_TOKEN=", t) else t + f"\n{line}\n"
p.write_text(t)
PY
  say "✓ 產生了通行碼（寫在 .env）"
fi

# --- venv ---
VENV="$DIR/backend/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  say "▶ 建立 Python 環境…"
  run "$PY" -m venv "$VENV"
fi
# 每次都同步相依：更新 repo 後重跑、或上次裝到一半失敗，重跑就補齊
say "▶ 同步 Python 相依…"
run "$VENV/bin/pip" install -q --upgrade pip
run "$VENV/bin/pip" install -q -r "$DIR/backend/requirements.txt"

# --- hook ---
PORT="$( (grep -E '^API_PORT=' "$DIR/.env" 2>/dev/null || grep -E '^API_PORT=' "$DIR/.env.example") | cut -d= -f2)"; PORT="${PORT:-5391}"
if [ "$DRY" = 1 ]; then "$PY" "$DIR/tools/install_hooks.py" --dry-run --port "$PORT"; else "$PY" "$DIR/tools/install_hooks.py" --port "$PORT"; fi

# --- launchd ---
if [ "$DRY" = 1 ]; then
  say "  （試跑）寫入 $PLIST 並用 launchctl 啟動 ${LABEL}"
else
  if ! launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    say "✗ 埠 ${PORT} 已經有別的程式在用（可能是另一份 session-remote）。改 .env 的 API_PORT 或先停掉它。"; exit 1
  fi
  mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
  # 用 plistlib 產生：路徑可能含 & 之類要跳脫的字元；給 bash -lc 的路徑另外用 shlex 加引號
  "$PY" - "$PLIST" "$LABEL" "$DIR" "$LOG" <<'PY'
import plistlib, shlex, sys
plist, label, d, log = sys.argv[1:]
with open(plist, "wb") as f:
    plistlib.dump({
        "Label": label,
        "ProgramArguments": ["/bin/bash", "-lc", "exec " + shlex.quote(d + "/run.sh")],
        "EnvironmentVariables": {"RELOAD": ""},  # 正式跑不要 --reload：會等 SSE 長連線關掉才重載
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10,
        "StandardOutPath": log, "StandardErrorPath": log,
    }, f)
PY
  plutil -lint "$PLIST" >/dev/null
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  # bootout 是非同步的：還沒卸載完就 bootstrap 會「Bootstrap failed: 5」
  for _ in $(seq 20); do launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || break; sleep 0.5; done
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  ok=0
  for _ in $(seq 30); do curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null && { ok=1; break; }; sleep 1; done
  [ "$ok" = 1 ] || { say "✗ 服務 30 秒內沒起來，看 $LOG"; exit 1; }
  say "✓ 服務起來了（開機會自己啟動；log：${LOG}）"
fi

# --- 配對 ---
say ""
say "第一次從手機操作時，macOS 會跳「想要控制 iTerm」的權限框，按允許。"
say "已經開著的 Claude Code 要重開才會吃到新的 hook。"
if [ "$DRY" = 1 ]; then say "  （試跑）印配對 QR code"; else TAILSCALE="$TS" "$VENV/bin/python" "$DIR/tools/pair.py"; fi

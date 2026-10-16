#!/usr/bin/env bash
# 一鍵啟動後端與前端，Ctrl-C 一起結束。
#
# 埠位與資料庫位址從 .env 讀，不要寫死在這裡——寫死的後果是換埠要改三個
# 地方，而且一定會漏掉一個。
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env 不進版控，所以新 clone 下來沒有。直接從範本補一份。
[ -f "$DIR/.env" ] || cp "$DIR/.env.example" "$DIR/.env"
set -a; . "$DIR/.env"; set +a

# 後端：首次執行自動建 venv 並安裝相依
VENV="$DIR/backend/.venv"
NEW_VENV=0
if [ ! -d "$VENV" ]; then
  echo "▶ 建立後端 venv 並安裝相依…"
  python3 -m venv "$VENV"
  NEW_VENV=1
fi

# venv 放執行檔的目錄兩個平台不一樣：POSIX 是 bin/，Windows 是 Scripts/。
# 用 if/else 不用 `[ -d ] && VBIN=`——後者在條件不成立時整句回傳 1，
# 配上 set -e 會直接把腳本結束掉。
if [ -d "$VENV/Scripts" ]; then VBIN="$VENV/Scripts"; else VBIN="$VENV/bin"; fi

if [ "$NEW_VENV" = 1 ]; then
  "$VBIN/pip" install -q --upgrade pip
  "$VBIN/pip" install -q -r "$DIR/backend/requirements.txt"
fi

if [ -d "$DIR/frontend" ] && [ ! -d "$DIR/frontend/node_modules" ]; then
  echo "▶ 安裝前端相依…"
  (cd "$DIR/frontend" && npm install)
fi

echo "▶ 後端 http://localhost:$API_PORT   前端 http://localhost:$WEB_PORT"
trap 'kill 0' EXIT

(cd "$DIR/backend" && "$VBIN/uvicorn" app.main:app ${RELOAD---reload} --host "${HOST:-127.0.0.1}" --port "$API_PORT" --timeout-graceful-shutdown 2) &

# --strictPort 是刻意的：vite 預設埠被佔住時會自己換一個，然後你看到的
# 網址跟 projects.json 登記的不一樣，proj status 會說這個專案沒在跑。
[ -d "$DIR/frontend" ] && \
  (cd "$DIR/frontend" && npm run dev -- --port "$WEB_PORT" --strictPort) &

wait

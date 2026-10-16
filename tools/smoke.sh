#!/usr/bin/env bash
# 每一支工具還跑不跑得起來？（最小工作量，不驗結果只驗「不會炸」）
#
# 存在的理由：工具壞掉是安靜的。它不在測試裡、平常也沒人跑，所以可以壞很久
# 而沒有任何人知道——實際發生過十三天。這支把「安靜」變成「紅燈」。
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0; n=0

check() { n=$((n+1)); if eval "$1" >/dev/null 2>&1; then printf '  ✓ %s\n' "$2"; else printf '  ✗ %s\n' "$2"; fail=$((fail+1)); fi; }

echo "冒煙測試"
check "[ -x run.sh ]"                              "run.sh 可執行"
check "python3 tools/doc-audit.py"                 "tools/doc-audit.py"
check "python3 -c 'import json;json.load(open(\"project-map.json\"))'" "project-map.json 是合法 JSON"
check "node --check hooks/report.mjs"              "hooks/report.mjs 語法正確"
check "zsh -n tools/quad-iterm"                    "tools/quad-iterm 語法正確"
check "bash -n tools/install-ios.sh && bash -n tools/install-agent.sh && bash -n tools/sim-shot.sh" "安裝／截圖腳本語法正確"
check "tools/quad-iterm --dry"                     "quad-iterm --dry 算得出座標"
check "backend/.venv/bin/python tools/ccmove.py"   "ccmove 列得出清單"
check "plutil -lint launchd/com.bruce.session-remote.plist" "launchd plist 合法"
check "python3 -c 'import ast,sys;[ast.parse(open(p).read()) for p in __import__(\"glob\").glob(\"backend/app/**/*.py\",recursive=True)]'" "backend 全部 .py 語法正確"

# 沉默不等於成功
if [ "$n" -lt 3 ]; then
  echo "✗ 只跑了 $n 項檢查——這支腳本八成壞了"; exit 2
fi
echo
if [ "$fail" -gt 0 ]; then echo "$n 項裡 $fail 項失敗。"; exit 1; fi
echo "$n 項全過。"

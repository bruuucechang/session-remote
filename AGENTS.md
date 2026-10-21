# AGENTS.md

## Overview

用 iPhone 看這台 Air 上**每個 iTerm2 分頁裡的 Claude Code session**，兩個帳號（`~/.claude`、`~/.claude-rakucamp`）
合在同一個列表，並能從手機回答選項題／權限提示、打字回覆、按 Esc 中斷、開新 session；
session 變成「等你回答」或「做完」時推播。規格與「明確不做」見 `SPEC.md`。

## Tech Stack

| 部分 | 做法 | 為什麼 |
|---|---|---|
| 筆電服務 | FastAPI（`backend/`），launchd 常駐，聽 0.0.0.0:5391 只放行本機＋tailnet，帶通行碼 | 手機走 Tailscale 直連，不經第三方 |
| 狀態來源 | `hooks/report.mjs`（掛在 skills repo 共用的 settings.json，兩個帳號都吃到）→ `POST /hook` | hook 是唯一知道「正在問你什麼」的來源 |
| 對話內容 | 讀 `<設定目錄>/projects/*/<session>.jsonl` | 不用另存一份 |
| 送字 | iTerm2 AppleScript `write text`（`backend/app/repositories/iterm.py`） | 能送進背景分頁、不搶畫面；Terminal.app 做不到 |
| 手機 | 原生 SwiftUI（`ios/`，XcodeGen 產 .xcodeproj），開發簽章裝到 iPhone | 使用者有付費開發者帳號 |
| 推播 | 筆電直接打 APNs（sandbox），金鑰在 `.env` | 沒設金鑰就整段略過 |

**沒有資料庫、沒有網頁前端**（scaffold 跑的是 `--no-db --no-frontend`）。「前端」是 `ios/`，
`ios/Sources/API.swift` 是 app 裡唯一打網路的地方（等同網頁專案的前端 API client）。
持久化只有 `backend/data/*.json`（不進版控）。

## Build & Run

```bash
tools/install-agent.sh            # 常駐服務（launchd：com.bruce.session-remote，log 在 /tmp/session-remote.log）
cd backend && .venv/bin/pytest    # 後端單元測試
tools/install-ios.sh [--wait]     # 編譯並裝到 iPhone（--wait：等手機回到網路再裝）
tools/sim-shot.sh out.png [分頁id] # 無頭模擬器跑 app 並截圖（不開 Simulator 視窗）
backend/.venv/bin/python tools/pair.py   # 印配對 QR code（手機相機掃）
ccmove / quad-iterm               # 搬家指令／iTerm2 四宮格（symlink 在 ~/.local/bin）
```

開發時要直接跑：先 `launchctl bootout gui/$(id -u)/com.bruce.session-remote`，再 `./run.sh`
（預設 --reload；`RELOAD= ./run.sh` 關掉）。埠位由 `proj new` 分配，**不要自己改**。

## 分層規則（改程式之前先讀）

這個專案是三層的。**每一層只准往下叫，不准往上、不准跳層。**

```
ios/Sources/API.swift        ← app 唯一打後端的地方，View 不准直接 URLSession
        ↓  HTTP
backend/app/routers/         ← 收參數、翻譯例外成狀態碼。不寫業務邏輯、不寫 SQL
        ↓
backend/app/services/        ← 業務邏輯。不 import fastapi、不 import sqlalchemy
        ↓
backend/app/repositories/    ← 唯一碰外面的地方（iTerm2、ps、紀錄檔、JSON 檔、APNs）
```

具體禁令，違反了就是搬錯地方：

| 這一層 | 不准做的事 |
|---|---|
| `routers/` | 寫 `if` 判斷業務規則、寫 SQL、import sqlalchemy |
| `services/` | import fastapi（不該認得 HTTPException）、寫 SQL |
| `repositories/` | 認得 HTTP、決定業務規則 |
| iOS View | 直接用 URLSession。一律走 `API.swift` |

## 這些坑踩過了，別重犯

- **AppleScript 在 `tell application "iTerm2"` 裡，`tab` 是「分頁」類別不是 tab 字元**——
  拿來當分隔符號會讓整個列表變空、不報錯。先在 tell 外面 `set sep to (ASCII character 9)`。
- **文字跟 Enter 要分兩次送、中間隔 ~0.35 秒**，一起送 Claude Code 會當成貼上，Enter 變換行。
- **iTerm2 開新視窗／分頁會把自己拉到最前面**（它被隱藏時例外）。`iterm.new_tab` 會把原本在前面的 app 切回去。
  `current window` 在 iTerm2 被隱藏時是 missing value，要用 `first window`。
- **新分頁的 shell 會繼承 iTerm2 的環境變數**：iTerm2 若是從某個 claude 的 Bash 開的，會帶著
  `CLAUDE_CONFIG_DIR`。所以預設帳號也要明講 `env -u CLAUDE_CONFIG_DIR claude`。
- **uvicorn `--reload` 會等 SSE 長連線關掉才重載＝永遠卡住**。run.sh 加了 `--timeout-graceful-shutdown 2`，
  launchd 正式跑不開 reload。
- **launchd 底下第一次控制 iTerm2 會跳 macOS 權限框（「python3.15 想控制 iTerm」）**，按允許之前所有
  AppleScript 都逾時（API 回 503「iTerm2 沒回應」）。venv 的 Python 換版本會再跳一次。
- **iTerm2 第一次啟動卡在「No valid UNIX locale」對話框**（系統語系 en_TW 不是合法 UNIX locale），
  卡著時 AppleScript 全部逾時。已把預設設定檔的「Set locale variables automatically」關掉。
- **被 Esc 中斷時不會觸發 Stop hook**，`actions.interrupt` 自己把狀態改成待命。
- **輸入框不要用 `TextField(axis: .vertical)`**：超過 lineLimit 之後不會捲到游標，打多行時新字掉到框外看不到。
  改用 `ios/Sources/Composer.swift`（TextEditor＋量高度，長到上限就框內捲動，要 `.clipped()`）。
- **一次問好幾題時，hook 回報的是整張題目表，畫面顯示的是「目前那一題」**：題目與說明要用選項標籤比對出第幾題
  （`PromptMatch`），不能拿第一題。
- **複選題**的選項前面有 `[ ]`／`[✔]`、Submit 是沒編號的一行：數字鍵只會勾，送出要移到 Submit 按 Enter（key `submit`）。
- **回覆裡的換行照送**：文字一次 `write` 進去會被當成貼上、換行保留，送出靠之後另外按的 Enter（2026-10-21 實測）。
- 信任資料夾這類**沒編號的選單**只能用方向鍵：選項 key 是 `pick:N`，`actions._pick` 換算成 ↑↓＋Enter。

## 做過但結論是「不做」的

**沒有留下證據的否定結果等於沒有做過**，下一個人會再查一次。試過而且量過、
結論是不做的東西寫在這裡，附上可以重跑的證據。

| 項目 | 結論 | 證據（怎麼重跑） |
|---|---|---|
| Claude Code 內建 Remote Control | 使用者裁示不用：手機 App 一次只看得到一個帳號的 session，他有兩個帳號 | 官方文件 code.claude.com/docs/en/mobile「同一個 claude.ai 帳號」 |
| Terminal.app 的 session | 不列（規格）：送字只能模擬鍵盤，一定搶畫面 | 見上面「iTerm2」那條 |

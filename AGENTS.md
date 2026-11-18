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
| 小工具＋鎖定畫面即時狀態 | `ios/Widgets/`（另一個 target，WidgetKit＋ActivityKit），畫面本體在 `ios/Shared/WidgetViews.swift` | 跟 app 經 App Group（`group.com.bruuucechang.sessionremote`）共用網址與通行碼，小工具自己打 API；即時狀態由筆電用 liveactivity 推播更新（`notify.activity_payload`） |
| 額度與 context | 額度讀 agent-quota 寫在本機的 `widget.json`；context 讀 skills 的 `statusline.mjs` 寫的 `~/.claude/state/context/<session>.json` | 都不連網；狀態列沒更新過的 session 沒有 context 數字 |

**沒有資料庫、沒有網頁前端**（scaffold 跑的是 `--no-db --no-frontend`）。「前端」是 `ios/`，
`ios/Sources/API.swift` 是 app 裡唯一打網路的地方（等同網頁專案的前端 API client）。
持久化只有 `backend/data/*.json`（不進版控）。

## Build & Run

```bash
tools/install-agent.sh            # 常駐服務（launchd：com.bruce.session-remote，log 在 /tmp/session-remote.log）
tools/install.sh [--dry-run]      # 公開版給別人的安裝：venv＋hook 進 ~/.claude/settings.json＋launchd com.sessionremote.server＋配對 QR（作者這台不要跑，埠會撞）
cd backend && .venv/bin/pytest    # 後端單元測試
tools/install-ios.sh [--wait]     # 編譯並裝到 iPhone（--wait：等手機回到網路再裝）
tools/sim-shot.sh out.png [分頁id] # 無頭模擬器跑 app 並截圖（不開 Simulator 視窗）
tools/uitest.sh [--sim]           # XCUITest：起假資料後端（tools/fake-backend.sh，5390）→ 真機（預設，手機要解鎖）或模擬器 → 截圖在 ios/build/uitest/
backend/.venv/bin/python tools/pair.py   # 印配對 QR code（手機相機掃）
ccmove                            # 搬家指令（symlink 在 ~/.local/bin）；iTerm2 四宮格 quad-iterm 已搬到 ~/Projects/termkit
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
  改用 `ios/Sources/Composer.swift`（包 UITextView＋量高度，長到上限就框內捲動，要 `.clipped()`）。
- **送出要當下就清空輸入框**：以前等 `api.reply` 回來（1～2 秒）才清，使用者看到上一句一直掛著（2026-11-18）。
  中文組字中（marked text）光把 binding 設成空字串清不掉，`Composer` 送出前先 `unmarkText()` 再清 UITextView；
  送出中的那句先以「送出中」顯示在對話底部（`pendingReplies`），紀錄裡出現同一句或 15 秒後拿掉，失敗把字放回輸入框。
- **即時狀態（動態島＋鎖定畫面）只在有人等你回答時存在**（2026-11-18 裁示）：app 的 `ContentState.active` 與後端
  `notify.activity_payload` 都是 `waiting > 0`，結束立刻消失。完工推播預設關（設定 `done_push`）。
- **列表的等你回答卡片直接有選項按鈕**（`PromptPresentation.quickOptions`）：只放按一下就送的（單選、權限、計畫核准），
  複選／確認頁／信任資料夾顯示「點進去回答」。按鈕要 `.buttonStyle(.borderless)` 才不會被整列 NavigationLink 吃掉；
  文字色要明寫 `Color.primary`／`Color.secondary`，不然 borderless 按鈕裡的 `.secondary` 會被染成藍色。
- **在 `*-lanes` 底下跑 `tools/uitest.sh` 時 NewSessionTests 會紅**：假專案路徑含 `-lanes`，被開新 session 的「隱藏 lane 資料夾」規則藏掉。
  從不含 `-lanes` 的 symlink 跑（例：`ln -s <lane> /tmp/session-remote-x && cd /tmp/session-remote-x && tools/uitest.sh --sim`）。
- **一次問好幾題時，hook 回報的是整張題目表，畫面顯示的是「目前那一題」**：題目與說明要用選項標籤比對出第幾題
  （`PromptMatch`），不能拿第一題。
- **一次問好幾題、答完最後一題後的確認頁（Review your answers → `1. Submit answers`／`2. Cancel`）沒有頁尾**，
  `screen.parse_prompt` 靠「Ready to submit your answers?」那一行認，回傳 `review`（每題答了什麼）。只認頁尾的話手機上不會出現送出鈕（2026-10-22 實測 v2.1.306）。
- **複選題**的選項前面有 `[ ]`／`[✔]`、Submit 是沒編號的一行：數字鍵只會勾，送出要移到 Submit 按 Enter（key `submit`）。
  **一次問好幾題時那一行寫 `Next` 不是 `Submit`**。複選題的 Type something 按數字只會打勾、游標不動：
  要用方向鍵移到那一行直接打字（會自動勾起來），**不要按 Enter**（會取消勾選）（2026-10-22 實測 v2.1.307）。
- **選單開著時從手機打字**：沒有可以打字的那一項（確認頁、信任資料夾）就拒絕——字會被吃掉，Enter 卻會按下游標那一項。
  權限提示的「No, and tell Claude…」、計畫核准的「Tell Claude what to change」都當成 Type something。
- **手機按選項會帶 `label`**，`actions.press` 核對畫面上同一個 key 還是不是那個字，不是就拒絕（手機停在上一題時數字會送進下一題）。
- **巢狀的 `claude -p`**（被 Bash 工具或腳本叫起來的）往上找 tty 會找到外層 session：`report.mjs` 路上碰到沒有 tty 的 claude 就不送。
  subagent 的工具事件帶 `agent_id`，主線程在問選項題時不准把狀態改回工作中。
- **回覆裡的換行照送**：文字一次 `write` 進去會被當成貼上、換行保留，送出靠之後另外按的 Enter（2026-10-21 實測）。
- **即時狀態的 content-state 欄位名**（working／waiting／background／done／headline）在 `notify.activity_payload` 與
  `ios/Shared/SharedConfig.swift` 各寫一次，改一邊另一邊沒改，推播來的更新會解不開、畫面停在舊的，不報錯。
- **模擬器截圖要用 `launch --terminate-running-process`**：有了即時狀態之後系統會自己在背景把 app 叫起來，
  一般的 `simctl launch` 只是把那個舊程序拉到前面，SR_URL 這些環境變數沒帶到，畫面變成「連到筆電」。
- 小工具與鎖定畫面在無頭模擬器擺不出來：`SIMCTL_CHILD_SR_PREVIEW=widgets tools/sim-shot.sh out.png` 開一頁畫出來看；
  動態島要 `SIMCTL_CHILD_SR_ACTIVITY=1` 啟動後切到別的 app 再截圖。
  其他直接打開某一頁的開關：`SR_TOOL=<訊息 id 或工具名>`（工具詳情）、`SR_SEARCH=<字>`（對話搜尋）、
  `SR_NEW=1`（開新 session，加 `SR_DIR=<路徑>` 預選資料夾）、`SR_PAGE=30`（一頁幾則）、`SR_SCROLL=top`、`SR_DRAFT`／`SR_FOCUS=1`（輸入框）。
- **展示模式**（配對頁「先看看」）：資料全來自 `ios/Sources/DemoBackend.swift`，`API` 帶著 `demo` 時每個方法改問它、不打網路；
  不寫 App Group／紅點／即時狀態／草稿、不把推播 token 送去筆電（系統的推播授權照舊在啟動時問），也不記住（重開 app 回配對頁）。截圖用 `SIMCTL_CHILD_SR_DEMO=1 tools/sim-shot.sh out.png [demo-shop]`，
  UI 測試是 `DemoTests`；假資料的行為（不開模擬器）用 `tools/demo-check.sh`。小工具 target 也編 `API.swift`，所以 `project.yml` 的 SessionWidgets 要一起列 `DemoBackend.swift`。
- **開新 session 要有明顯的送出鈕**：以前點資料夾就直接開，填了第一句話之後鍵盤蓋住清單、使用者找不到哪裡送出。現在點資料夾只是選，按右上角「開始」才開（2026-10-25）。
- **`simctl boot` 會把當下的 `SIMCTL_CHILD_*` 留在模擬器的系統環境裡**：用 `SIMCTL_CHILD_SR_NEW=1 tools/sim-shot.sh` 開機的模擬器，之後每次啟動 app（含 XCUITest）都帶著 SR_NEW=1、一打開就跳開新 session。`tools/uitest.sh --sim` 每次先重開模擬器（2026-10-25 實測）。
- **UI 測試的假資料情境**：`FakeBackend.reset("many")`／`launchApp(scenario: "empty")` 換成 `backend/tests/fixtures/uitest/scenario-<名字>.json`；
  scenario 可寫 `starred`、`close_fails`（關分頁丟錯）、`quota`（重置時間寫 `"+26h"`）。假的開新 session 會真的多一列。
  `SR_FIRSTRUN=1` 當成沒設定過、走第一次配對（存的東西不寫進手機）。
- **app 要宣告繁中（`CFBundleDevelopmentRegion: zh-Hant`）**：手機語言是英文時，沒宣告的話系統元件（確認框的取消、搜尋沒結果、網路錯誤訊息）都講英文。
  網路錯誤另外在 `API.describe` 翻成中文（2026-10-25 真機實測）。
- **英文介面（B8）**：String Catalog 是 `ios/Resources/Localizable.xcstrings`，**key 就是繁中原文**（開發語言 zh-Hant），手機語言英文才換英文。
  SwiftUI 的字面字串（`Text("…")`、`Button("…")`）自動會翻；**存進 `String` 再顯示的要寫 `String(localized: "…")`**，不然永遠是中文。
  執行時才知道的字用 `L()`；後端回的中文訊息（錯誤 detail、「已中斷」、計畫核准）由 app 用 `serverText()` 翻（`ios/Shared/L10n.swift`），後端不分語言。
  新增或改中文字串後：帶 `SWIFT_EMIT_LOC_STRINGS=YES` build → `tools/l10n-check.py --sync` 補 key → 填英文 → `tools/l10n-check.py` 要 ✓（刻意不翻的行尾寫 `// l10n:skip`）。
  分區標題這類拿來判斷的字要用英文 key 判斷（`SessionListView` 用 `sec.key`），不能比對翻過的字。日期格式用 `appLocale`，不寫死 zh_Hant_TW。
  英文截圖：`SR_LANG=en tools/sim-shot.sh out.png`（只換 app 語言）。**模擬器系統語言是英文**，所以 UI 測試的 `launchApp` 預設帶
  `-AppleLanguages (zh-Hant)`（不帶的話 35 個用中文 label 找元素的測試全紅，2026-11-16 實測）；英文介面的測試是 `DemoTests.testEnglishDemo`。
- **XCUITest 點靠右對齊的輸入框要點最右邊**：點正中間游標落在最前面，刪除字元刪不到東西（SecureField 看起來像沒反應）。
  整列的字合在 NavigationLink 按鈕的 label 裡、分隔符號跟著語言（繁中是「、」），用 `label BEGINSWITH` 找。
- **XCUITest 找文字要限定在哪一塊**：對話搜尋的結果字在後面的對話裡也有，`app.any(...)` 會找到底下那則訊息、搜尋壞了也過；用 `app.cells.containing(...)`（2026-10-25）。
- **別的程序綁 `127.0.0.1:5390` 會搶走模擬器的請求**：假後端聽 0.0.0.0:5390，macOS 照樣讓別人再綁 127.0.0.1:5390，本機請求改送到它（app 拿到「Not Found」、假後端 log 沒有請求）。`tools/uitest.sh` 跑的期間會監看並在最後印 ⚠（2026-10-25 實測）。
- **app 剛開就直接推進對話頁（推播、小工具、`SR_OPEN`）時標題列偶爾整條空白**：標題列先用列表那一筆（`listed`），不要只靠 detail 回來後的更新（模擬器連跑 5 次 1 次）。
- 信任資料夾這類**沒編號的選單**只能用方向鍵：選項 key 是 `pick:N`，`actions._pick` 換算成 ↑↓＋Enter。
- **題目卡顯示的字在 `PromptWords`**：權限提示、計畫核准、信任資料夾、確認頁是 Claude Code 自己的選單、標籤固定英文，只翻**顯示**的字；
  按下去送的 key 與 label 一定用原文（`actions.press` 拿原文核對畫面）。認不得的標籤照原文顯示。
- **題目卡的 UI 測試**用 `scenario-prompts.json`：FAKE-ASK（單選）、FAKE-MULTI（複選＋Submit）、FAKE-STEPS（三題的第 2 題）、FAKE-REVIEW（確認頁）、
  FAKE-PERM（Bash 權限）、FAKE-TRUST（信任資料夾）；計畫核准是預設情境的 FAKE-PLAN。選項按鈕的無障礙 label 是「標籤，推薦，說明」、複選題 value 是「已勾／沒勾」。
  手機上跑的測試讀不到筆電的檔案：要換畫面就把文字寫在測試裡 `FakeBackend.setScreen`。
- **新的一題出現就收鍵盤**：送完字鍵盤還開著、Claude 接著問題目時，題目卡會停在「打字中只留兩行」、選項整個看不到（2026-10-26 真機實測）。
- **B5 真機實測** `tools/livetest.sh`：連正式服務 5391，在 `~/Projects/.uitest-sandbox/run-<時間>` 開真的 Claude（資料夾設定用 haiku）。
  session 名稱會被命名 hook 取成「.uitest-sandbox｜…」，標題列核對要兩種都認。手機自動鎖定會讓 xcodebuild 卡在「device is locked」一直等。
- **iTerm2 AppleScript 偶爾回「Invalid index (-1719)」**：逐一找分頁時別的分頁剛好開或關。`iterm._osa` 自動重試（找到之前還沒送字，安全）。
- **同時有兩個 iTerm2 程序時，AppleScript 會連到新開的那個**：2026-10-26 17:32 不明原因多開一個 0 視窗的 iTerm2，服務的 session 列表整個變空（API 回 `{"sessions":[]}`、不報錯）。查法：`osascript -e 'tell application "iTerm2" to count windows'` 是 0、`lsappinfo list | grep -A3 iTerm2` 看到兩個 pid；關掉空的那個就好。
- **`launchctl bootout` 是非同步的**：馬上 bootstrap 會「Bootstrap failed: 5」而服務整個停掉；`tools/install-agent.sh` 會等卸載完。
- **v2.1.310 的權限通知只寫「Claude needs your permission」**，沒有工具名：工具名改由後端 `transcript.awaiting` 判斷（拿不準就不講），不要拿「對話最後一則工具」（subagent、平行呼叫都會指錯）。
- **bash 變數後面直接接全形字**（`$PORT（`）在 `set -u` 底下會被當成變數名的一部分而炸掉，一律寫 `${PORT}`。
- **「背景跑」不是 hook 給的狀態**：列表時看 claude 程序底下還活著的 Bash 工具 shell（指令含 `shell-snapshots/snapshot-`）。
  done／idle＋有背景＝`background`；背景全部結束時 `sessions.check_background`（每 10 秒，只查記下來的 pid）把完工時間改成第一次看到結束的那一刻，**再等一輪**還停在完工才推「完工」：背景結束時 Claude Code 會叫醒模型接著做，當下就推會推兩次（2026-11-08 審查）。醒來那一輪做完由 Stop 自己推，看門的不再推。
  背景 subagent、派到別台的工作不是子程序，偵測不到。假資料 scenario 用 `"background": ["指令", …]`（規格 `docs/background-status-spec.md`）。
- **輸入框叫出鍵盤時題目卡會收成兩行**，只限有可以打字的那一項；確認頁、信任資料夾不收，不然選項整個不見、打的字又送不出去（2026-10-25）。

## 做過但結論是「不做」的

**沒有留下證據的否定結果等於沒有做過**，下一個人會再查一次。試過而且量過、
結論是不做的東西寫在這裡，附上可以重跑的證據。

| 項目 | 結論 | 證據（怎麼重跑） |
|---|---|---|
| Claude Code 內建 Remote Control | 使用者裁示不用：手機 App 一次只看得到一個帳號的 session，他有兩個帳號 | 官方文件 code.claude.com/docs/en/mobile「同一個 claude.ai 帳號」 |
| Terminal.app 的 session | 不列（規格）：送字只能模擬鍵盤，一定搶畫面 | 見上面「iTerm2」那條 |

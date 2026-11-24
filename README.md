# session-remote

用 iPhone 查看和操作 Mac 上 iTerm2 裡的 Claude Code 工作階段。

## 最近更新
<!-- readme:recent 自動產生，不要手改 -->
- [2026-11-24](docs/worklog/2026-11-24.md)：docs(readme): 更新最近更新
- [2026-11-23](docs/worklog/2026-11-23.md)：docs(readme): 更新最近更新
- [2026-11-22](docs/worklog/2026-11-22.md)：docs(readme): 更新最近更新
- [2026-11-21](docs/worklog/2026-11-21.md)：docs(readme): 更新最近更新
- [2026-11-20](docs/worklog/2026-11-20.md)：docs(readme): 更新最近更新
- [2026-11-19](docs/worklog/2026-11-19.md)：docs(readme): 更新最近更新；docs(readme): 重寫說明與架構
- [2026-11-18](docs/worklog/2026-11-18.md)：改善手機送出訊息的體驗：按下就清空輸入框、收起鍵盤並顯示「送出中」，失敗時會還原文字；動態島與鎖定畫面只在有工作階段等待回答時顯示，沒人等待就立即消失
<!-- /readme:recent -->

## 這是什麼
<!-- readme:about 2026-11-19 -->
用 iPhone 查看和操作 Mac 上 iTerm2 裡的 Claude Code 工作階段。

session-remote 適合離開電腦時仍想掌握 Claude Code 工作進度的人。手機可以把兩個帳號的工作階段合在同一個列表，閱讀對話、回答選項題和權限提示、輸入文字、中斷工作或開啟新對話。

App 也能顯示背景工作、使用額度與 context 使用比例，並透過小工具、鎖定畫面和動態島呈現狀態。設定推播後，等待回答時可收到通知；完工通知可在設定中開啟。尚未配對時，也能用展示模式體驗介面。

Mac 服務與手機 app 已上線，主要操作流程已在 iPhone 上驗證；TestFlight 公開發布仍在準備中。只有 iTerm2 裡的工作階段會出現在清單，Mac 必須保持喚醒並開啟 Tailscale。另有一項待查疑慮：送出文字時，若其他分頁剛好關閉，文字可能送到錯誤分頁。
<!-- /readme:about -->

## 架構
<!-- readme:arch 2026-11-19 -->
iPhone 上的 SwiftUI app 顯示工作階段、對話和操作畫面，透過 API 與 Mac 上的 FastAPI 服務溝通。小工具使用 app 共用的連線設定，自行向服務取得清單；鎖定畫面與動態島的即時狀態可透過推播更新。

Mac 端的路由接收請求，服務層處理狀態、操作與通知，資料存取層負責讀取本機檔案、查詢程序、控制 iTerm2 和傳送推播。Claude Code 的 hook 將事件和終端機識別資訊送到本機服務，對話內容則讀取 Claude Code 的紀錄。

手機透過 Tailscale 連線並使用通行碼。後端以事件串流通知手機資料已變更，手機再重新取得清單。推播使用 Apple 推播服務；額度與 context 資料則讀取本機檔案。專案沒有資料庫或網頁前端。

```mermaid
flowchart TD
    Claude["iTerm2 裡的 Claude Code"] -->|工作階段事件| Hook["hooks/report.mjs"]
    Hook -->|POST /hook：事件與終端機識別資訊| Server["Mac 上的 FastAPI 服務"]
    App["iPhone app"] -->|Tailscale：API 請求與通行碼| Server
    Server -->|SSE 變更通知與 API 回應| App
    Widget["iPhone 小工具"] -->|API 請求與通行碼| Server
    Server -->|工作階段清單| Widget
    Server -->|AppleScript：讀取畫面與送出文字| Claude
    Files["Mac 上的對話紀錄、額度與 context 檔案"] -->|JSONL 對話與 JSON 狀態資料| Server
    Server -->|工作階段與裝置資料| State["Mac 上的 JSON 狀態檔"]
    State -->|已儲存的狀態與裝置資料| Server
    Server -->|通知與即時狀態更新| APNs["Apple 推播服務"]
    APNs -->|通知與即時狀態更新| App
```

### 手機介面

```mermaid
flowchart TD
    Entry["ios/Sources/SessionRemoteApp.swift"] -->|建立 app 狀態| Store["ios/Sources/Store.swift"]
    List["ios/Sources/SessionListView.swift"] -->|讀取清單狀態| Store
    Detail["ios/Sources/SessionDetailView.swift"] -->|讀取對話狀態與操作| Store
    Store -->|清單請求與事件串流| API["ios/Sources/API.swift"]
    Detail -->|對話與操作請求| API
    Store -->|儲存網址與通行碼| Shared["ios/Shared/SharedConfig.swift"]
    Widget["ios/Widgets/SessionWidgets.swift"] -->|讀取共用連線設定| Shared
    Widget -->|取得工作階段清單| API
    Widget -->|工作階段資料| Views["ios/Shared/WidgetViews.swift"]
    Store -->|工作階段狀態| Live["ios/Sources/LiveActivityController.swift"]
    Live -->|即時狀態註冊資訊| API
    API -->|展示模式請求| Demo["ios/Sources/DemoBackend.swift"]
```

### Mac 後端

```mermaid
flowchart TD
    Main["backend/app/main.py"] -->|掛載 API 路由| API["backend/app/routers/api.py"]
    Main -->|掛載 hook 路由| Hook["backend/app/routers/hook.py"]
    Hook -->|工作階段事件| Sessions["backend/app/services/sessions.py"]
    API -->|清單與對話查詢| Sessions
    API -->|回覆與操作請求| Actions["backend/app/services/actions.py"]
    API -->|事件串流版本| Events["backend/app/services/events.py"]
    API -->|額度查詢| Quota["backend/app/services/quota.py"]
    Actions -->|查找工作階段| Sessions
    Actions -->|送字與控制分頁| ITerm["backend/app/repositories/iterm.py"]
    Sessions -->|查詢分頁與畫面| ITerm
    Sessions -->|讀取對話紀錄| Transcripts["backend/app/repositories/transcripts.py"]
    Sessions -->|查詢 Claude 與背景程序| Procs["backend/app/repositories/procs.py"]
    Sessions -->|狀態變更通知| Events
    Sessions -->|通知請求| Notify["backend/app/services/notify.py"]
    Hook -->|本機通知請求| Notify
    Notify -->|推播內容| APNs["backend/app/repositories/apns.py"]
    Quota -->|讀取額度快照| QuotaRepo["backend/app/repositories/quota.py"]
```

| 資料夾 | 放什麼 |
|---|---|
| `backend/app` | 後端入口、設定、路由、服務與資料存取程式 |
| `backend/tests` | 後端測試、畫面範例與介面測試資料 |
| `docs` | 規格、筆記與舊版說明 |
| `docs/worklog` | 按日期記錄的工作日誌 |
| `hooks` | Claude Code 狀態回報程式 |
| `ios/Sources` | iPhone app 畫面、狀態與 API 程式 |
| `ios/Shared` | app 與小工具共用的設定和畫面 |
| `ios/Widgets` | 小工具與即時狀態 |
| `ios/Resources` | 本地化文字與 app 圖示等資源 |
| `ios/UITests` | iPhone app 介面測試 |
| `launchd` | Mac 常駐服務設定 |
| `tools` | 安裝、配對、測試與其他工具 |
<!-- /readme:arch -->

## 自己裝來用（不用 Apple 開發者帳號）

需要：一台 Mac，裝好 [iTerm2](https://iterm2.com)、[Tailscale](https://tailscale.com)、node、Python 3.10 以上，
在 iTerm2 裡跑 Claude Code；iPhone 也裝 Tailscale、登入同一個帳號。

1. iPhone 從 TestFlight 公開連結裝 Sessions（連結上線後補在這裡）。
2. Mac 上：

   ```bash
   git clone https://github.com/bruuucechang/session-remote.git
   cd session-remote
   tools/install.sh --dry-run   # 先看會做什麼
   tools/install.sh             # 實際安裝，最後印出配對 QR code
   ```

   它會建 Python 環境、產通行碼寫進 `.env`、把 hook 加進 `~/.claude/settings.json`（先備份）、
   裝成開機自動啟動的服務（log 在 `~/Library/Logs/session-remote.log`）。重跑安全。
3. 用 iPhone 相機掃 QR code。已經開著的 Claude Code 要重開才會被看到；第一次從手機操作時 Mac 會問要不要讓它控制 iTerm，按允許。

限制：沒有推播（等你回答、做完的通知、鎖定畫面與動態島要作者的推播金鑰）；只認 iTerm2 裡的 Claude Code；
預設只認 `~/.claude` 一個設定目錄；Mac 要保持喚醒。

## 怎麼跑
<!-- readme:run 2026-11-19 -->
需要一台安裝 iTerm2、Tailscale、Node.js 和 Python 3.10 以上版本的 Mac，並在 iTerm2 中執行 Claude Code。iPhone 也需要安裝 Tailscale，並登入同一個帳號。

公開安裝流程可先預覽變更，再安裝後端、設定常駐服務並產生配對 QR code：

```bash
git clone https://github.com/bruuucechang/session-remote.git
cd session-remote
tools/install.sh --dry-run
tools/install.sh
```

安裝後用 iPhone 相機掃描 QR code。已開啟的 Claude Code 必須重新啟動才會被看到；首次從手機操作時，請允許 macOS 控制 iTerm2。公開版的 TestFlight 連結尚未上線；推播功能需要另行設定推播金鑰。

開發環境可在專案根目錄執行：

```bash
# 安裝並啟動 Mac 常駐服務
tools/install-agent.sh

# 編譯並安裝 iPhone app
tools/install-ios.sh

# 顯示配對 QR code
backend/.venv/bin/python tools/pair.py
```

若要直接執行後端，先停止常駐服務：

```bash
launchctl bootout gui/$(id -u)/com.bruce.session-remote
./run.sh
```

後端單元測試：

```bash
cd backend && .venv/bin/pytest
```

以下指令在專案根目錄執行：

```bash
# 介面測試，預設使用已解鎖的 iPhone
tools/uitest.sh

# 使用模擬器進行介面測試
tools/uitest.sh --sim

# 查看服務狀態
curl -s localhost:5391/health
```
<!-- /readme:run -->

## 工作日誌
每天做了什麼在 [`docs/worklog/`](docs/worklog/)，一天一份，檔名就是日期。
舊版 README：[`docs/README-舊版.md`](docs/README-舊版.md)

<!-- 標記外面的內容不會被自動覆寫 -->

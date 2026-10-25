# 區塊計畫：session-remote 手機 app 大整理

> 一個 session 做一塊。做完跑驗收 → 打勾 → 寫 HANDOFF → 關掉開新的。
> 規格：`docs/ui-overhaul-spec.md`（範圍、測試對象、明確不做都以它為準）。

## B1 測試地基：假資料後端＋XCUITest＋真機跑得起來  [完成]
- 目標：有一條 `xcodebuild test` 能在接著的 iPhone 上跑、吃假資料後端、點開列表與一個 session 並截圖
- 驗收：`tools/uitest.sh`（新）在真機跑完全綠，輸出截圖目錄；後端 `cd backend && .venv/bin/pytest` 綠
- 碰：`backend/app/`（假資料模式，只加 repositories 層的替身）、`ios/project.yml`（加 `SessionRemoteUITests` target）、`ios/UITests/`、`tools/uitest.sh`
- 不做：修任何畫面 bug（B2 以後）；測試 session 實測（B5）

## B2 列表、開新 session、設定、配對  [完成]
- 目標：這幾頁 bug 修掉、層級整理（要處理的在最上面、空／載入／錯誤狀態齊）、各有 UI 測試
- 驗收：`tools/uitest.sh` 真機全綠（含這塊新增的測試，各看過紅一次）；每種狀態截圖目視過
- 碰：`ios/Sources/SessionListView.swift`、`NewSessionView.swift`、`SettingsView.swift`、`SessionRemoteApp.swift`、`ios/UITests/`
- 不做：對話頁與回答題目（B3、B4）；小工具與推播
- 先讀過的：設定頁「儲存並連線」失敗時沒講怎麼辦；關分頁／標星號失敗的錯誤擠在列表最上面一行紅字（不在出事的那一列）；`SessionRow.ago` 用 status_since，做完很久的 session 也只顯示「6小時前」沒講是什麼時候做完

## B3 對話頁：訊息、輸入框、Esc、關分頁、搜尋、工具詳情  [完成]
- 驗收備註：使用者帶手機出門，B3 只在模擬器全綠（23 條）；手機回來後在 B4 開工前跑一次 `tools/uitest.sh` 真機補驗
- 目標：對話頁 bug 修掉、送出鈕永遠看得到、長訊息與工具詳情正常、狀態齊，各有 UI 測試
- 驗收：同 B2
- 碰：`ios/Sources/SessionDetailView.swift`、`MessageViews.swift`、`Composer.swift`、`ToolDetailView.swift`、`ios/UITests/`
- 不做：題目卡（B4）
- B2 看到的：剛開的新 session 還沒有任何訊息時對話頁整片黑，沒有空狀態（「Claude 正在啟動…」之類）
- B1 實測時看到的：輸入框空著時送出鈕看起來還是可以按；收起來的工具群組只顯示最後一個（Edit），前面的 Bash 看不出來

## B4 回答題目：單選、複選、多題確認頁、權限提示、計畫核准、信任資料夾  [未開始]
- 目標：每種題目在假資料下畫得對、按得對（送出的 key 與 label 對），各有 UI 測試
- 驗收：同 B2，並且後端 pytest 綠
- 碰：`ios/Sources/SessionDetailView.swift` 的題目卡部分、`backend` 假資料的題目畫面、`ios/UITests/`
- 不做：改後端 `screen.parse_prompt` 的解析規則（除非假資料重現出它的 bug，另開一塊）

## B5 測試 session 實測＋總驗收  [未開始]
- 目標：用自己開的測試 session 在真機上實測送字、按選項、複選、多題確認頁、權限提示、Esc、關分頁、開新帶第一句話
- 驗收：上述每項成功一次（看筆電上的分頁與 transcript 確認）；`tools/uitest.sh` 全綠；裝到手機請使用者用一次
- 碰：`ios/UITests/`（實測用的測試，預設不跑）、`tools/`
- 不做：碰使用者自己的 session

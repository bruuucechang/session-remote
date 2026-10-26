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

## B4 回答題目：單選、複選、多題確認頁、權限提示、計畫核准、信任資料夾  [完成]
- 目標：每種題目在假資料下畫得對、按得對（送出的 key 與 label 對），各有 UI 測試
- 驗收：同 B2，並且後端 pytest 綠
- 碰：`ios/Sources/SessionDetailView.swift` 的題目卡部分、`backend` 假資料的題目畫面、`ios/UITests/`
- 不做：改後端 `screen.parse_prompt` 的解析規則（除非假資料重現出它的 bug，另開一塊）
- 驗收備註：手機不在時 B4 只在模擬器全綠；2026-10-25 22:35 真機補驗 B3＋B4：`tools/uitest.sh` 31 條全綠
- B4 看到、沒修的（`parse_prompt` 不准動）：權限提示的選項太長換行時，第二行（例如「/Users/…/shop」）被丟掉，手機上只看到「…commands in」；
  Bash 工具的摘要用 description 不是指令本身，題目卡上的工具列要點開才看得到指令

## B5 測試 session 實測＋總驗收  [進行中]
- 目標：用自己開的測試 session 在真機上實測送字、按選項、複選、多題確認頁、權限提示、Esc、關分頁、開新帶第一句話
- 驗收：上述每項成功一次（看筆電上的分頁與 transcript 確認）；`tools/uitest.sh` 全綠；裝到手機請使用者用一次
- 碰：`ios/UITests/`（實測用的測試，預設不跑）、`tools/`
- 不做：碰使用者自己的 session
- 實測：`tools/livetest.sh`（ios/UITests/LiveTests.swift，手機要解鎖、自動鎖定設「永不」）。在 `~/Projects/.uitest-sandbox/run-<時間>` 開真的 Claude（haiku），每一步先核對 API 的 cwd 才動手
- 2026-10-26 01:50 進度（4 輪真機實測）：開新帶第一句話、信任資料夾、單選、打字送出、複選、多題、確認頁 **都在真機上成功過**；
  還沒成功：權限提示、Esc 中斷、關分頁
- 權限提示查到了（2026-10-26 02:3x，tmux 開互動 claude 實測）：設定有效、權限框有跳；是 v2.1.310 的通知只寫「Claude needs your permission」、
  沒寫工具名，手機標題變回英文，實測等的「Claude 要用 Bash，允許嗎？」等不到。已改成用對話最後一則工具呼叫的名稱（PromptTests/testPermissionWithoutToolName，看過紅）。
  這種權限框只有 Yes／No（假畫面 `perm_rule.txt` 是實測抄的）
- 實測抓到並修掉：送完字鍵盤還開著時下一題的選項被收起來（PromptTests/testNewPromptDismissesKeyboard，看過紅）
- 實測看到、還沒查：關分頁第一次回「iTerm2：…Invalid index (-1719)」，再按一次才關掉（claude 已經結束、分頁位置變了？）
- 審查提到、沒修（低）：讀 iTerm2 畫面偶爾失敗時後端回 `prompt: null`，下一次又有題目，app 會當成「新題目出現」把正在打字的鍵盤收掉；
  要修就讓後端讀不到畫面時回 503、app 保留舊的 detail

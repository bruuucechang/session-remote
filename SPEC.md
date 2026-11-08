# session-remote 規格（2026-10-16，待確認）

用 iPhone 看這台 Air 上所有 iTerm2 裡的 Claude Code session，兩個帳號（gmail、rakucamp）合在同一個畫面，並能從手機回答。

## 目標

1. 列表頁：每個 session 一張卡——名稱、帳號、狀態（工作中／等你回答／背景跑／完工；背景跑＝回合結束但背景任務還在，見 `docs/background-status-spec.md`）、最後一句話。現在開幾個就顯示幾個。
2. 點進去：完整對話紀錄，聊天介面排版；工具呼叫折疊成一行摘要。
3. 手機能做的事：
   - 回答選項題（AskUserQuestion）與權限提示（點選項）
   - 打字自由回覆
   - 中斷正在跑的 session（等於按 Esc）
   - 開新 session：選 `~/Projects` 底下的資料夾＋帳號，在 iTerm2 開新分頁跑 claude
4. 推播通知：session 變成「等你回答」或「做完」時，手機沒開 app 也會跳。

## 組成

| 部分 | 做法 |
|---|---|
| 手機 | 原生 iOS app（SwiftUI），用你的開發者帳號簽章、裝到 iPhone，不上架 |
| 筆電服務 | 常駐背景服務（launchd），只聽 Tailscale 網路＋本機，另加一組通行碼 |
| 狀態來源 | Claude Code hooks（兩個帳號共用同一份 settings.json）回報到筆電服務；對話從 session 紀錄檔讀 |
| 送字進 session | iTerm2 的腳本介面，從背景送字到指定分頁，不把視窗拉到前面 |
| 推播 | 筆電直接送到 Apple 推播伺服器（需要你在開發者後台建一把推播金鑰，步驟我會寫好） |

## 附帶

- 裝 iTerm2（brew，免費）。
- 四宮格自動排版改出 iTerm2 版。
- 搬家指令：列出最近的對話，一鍵在 iTerm2 用對的帳號接回（`claude --resume`）。舊的 Terminal session 由你自己決定什麼時候關。

## 驗收

- 筆電服務：`curl` 打 API 看得到 iTerm2 裡每個 session、帳號、狀態正確；送字、Esc、選項都在對應分頁生效，且前景視窗沒被換掉。
- iOS app：模擬器跑起來截圖目視列表、對話、回答流程；裝到你的 iPhone 後由你實機確認推播（我沒辦法替你看手機）。

## 明確不做

- 不顯示還在 Terminal.app 裡跑的 session。
- 只接這台 Air；不接 M5 Pro、Mani、Windows desk。
- 不上架 App Store、不走 Tailscale 以外的連線、不經過任何第三方伺服器（推播除外，走 Apple）。
- 不用 Claude Code 內建的 Remote Control。
- 不看終端機畫面鏡像，只看對話紀錄。

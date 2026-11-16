# 公開版規格：TestFlight＋一個指令裝好 Mac 端

> 2026-11-16 與使用者談定。目標：沒有 Apple 開發者帳號、不用 Xcode 的人，
> 點 TestFlight 公開連結裝 app，Mac 跑一個指令裝好後端，就能用。

## 決定了的事

| 項目 | 決定 |
|---|---|
| 發布方式 | 用使用者的付費帳號（team `CXJ2S2G4JD`）上 TestFlight，開公開測試連結 |
| 別人的推播 | **沒有**。推播只能用使用者的 APNs 金鑰送，別人的 Mac 沒有金鑰；後端沒設金鑰本來就整段略過。打開 app 時靠 SSE 即時更新 |
| 使用者自己的手機 | 照舊用 Xcode 開發簽章版（sandbox 推播），不換成 TestFlight 版 |
| 審核 | app 加**展示模式**：配對畫面多一個「先看看」，用內建假資料跑整套流程、不連網；審核員與還沒裝後端的人都能試 |
| 語言 | 加**英文**：手機語言是英文就顯示英文，其他照舊繁中。app 畫面、題目卡翻譯、錯誤訊息、後端回給手機看的訊息都要 |
| Mac 端安裝 | 一個指令（`tools/install.sh`）：建 venv、裝 launchd 常駐、把 `hooks/report.mjs` 加進 `~/.claude/settings.json`（先備份、重跑不重複加）、產通行碼、印配對 QR code |
| 帳號 | 沒有 skills repo 的帳號清單時，預設只認 `~/.claude` 一個帳號；要多個用設定檔列出 |
| App Store Connect | Claude 準備：Xcode 上傳、在使用者已登入的 Chrome 建 app 與填表；聯絡資料到時問；隱私權政策放 repo。**送審前停下來給使用者看，由使用者按送出** |

## 明確不做

- 不架推播轉發站，別人收不到推播、鎖定畫面與動態島不會自己更新。
- 不上架 App Store（只到 TestFlight）。
- 不支援 Terminal.app 等其他終端機（維持只認 iTerm2）。
- 不做 Windows／Linux 後端。
- 不改使用者自己這台的安裝方式（`tools/install-agent.sh` 與 skills repo 的 hook 照舊能用）。

## 驗收

1. 後端單元測試全綠：`cd backend && .venv/bin/pytest`。
2. 拿掉帳號清單檔、APNs 金鑰、agent-quota、context 目錄（用環境變數指到不存在的路徑）時服務照常起來，`curl` `/api/sessions` 回 200。
3. 在一個乾淨的 `HOME`（暫存目錄）跑 `tools/install.sh --dry-run` 與實際跑：`settings.json` 有備份、hook 只加一次。
4. 模擬器截圖：展示模式能走完清單 → 對話 → 回答選項題；英文與繁中各截一輪。
5. Archive 成功並上傳到 App Store Connect，處理完出現在 TestFlight。

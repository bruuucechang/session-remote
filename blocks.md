# 區塊計畫：session-remote 公開版（TestFlight）

> 一個 session 做一塊。做完跑驗收 → 打勾 → 寫 HANDOFF → 關掉開新的。
> 規格：`docs/public-release-spec.md`（範圍、明確不做都以它為準）。上一批 B1～B5 在 `blocks-done.md`。

## B6 後端去個人化＋一個指令裝好 Mac 端  [完成]
- 目標：別人的 Mac 沒有 skills repo、agent-quota、APNs 金鑰也能跑；`tools/install.sh` 一次裝好
- 驗收：`cd backend && .venv/bin/pytest` 綠；帳號清單、金鑰、額度、context 都指到不存在的路徑時服務起得來、`curl /api/sessions` 回 200；
  乾淨暫存 `HOME` 跑 `tools/install.sh --dry-run` 與實跑兩次：`settings.json` 有備份、hook 只出現一次
- 碰：`backend/app/config.py`、帳號讀取的 repository、`tools/install.sh`（新）、`launchd/` 樣板、`.env.example`、README 安裝段
- 不做：改使用者自己這台的 `tools/install-agent.sh` 流程；Windows／Linux

## B7 展示模式  [完成]
- 目標：配對畫面多一個「先看看」，用 app 內建假資料跑清單 → 對話 → 回答選項題／權限提示，不連網；設定頁能退出展示模式
- 驗收：`tools/sim-shot.sh` 截圖看得到展示模式的清單、對話、題目卡；`tools/uitest.sh --sim` 照舊全綠
- 碰：`ios/Sources/API.swift`（換成可替換的資料來源）、`Store.swift`、配對／設定畫面、新的假資料檔
- 不做：展示模式裡的小工具與動態島

## B8 英文介面  [完成]
- 目標：手機語言是英文時 app、小工具、題目卡翻譯、錯誤訊息都是英文；其他語言照舊繁中
- 驗收：模擬器設英文與繁中各截一輪（清單、對話、題目卡、設定、展示模式）；`tools/uitest.sh --sim` 綠
- 碰：`ios/` 的字串（String Catalog）、`project.yml` 的 `CFBundleLocalizations`、後端回給手機顯示的訊息
- 不做：其他語言
- 做法：String Catalog `ios/Resources/Localizable.xcstrings`（key＝繁中原文、241 條）；後端訊息由 app 的 `serverText()` 翻，後端沒改；核對工具 `tools/l10n-check.py`
- 沒翻：推播與即時狀態推播的內容（別人沒有推播，規格裁示），作者自己用繁中

## B9 TestFlight 上傳到送審前  [擱置 2026-11-18]
- 擱置時的進度（分支 `pr/261118-b9-prep`）：出口管制宣告、`docs/privacy.md`、README 怎麼裝、拿掉預設的作者 IP 都已做完；Release archive 成功；UI 測試 42 個全過、Release 版展示模式 4 項過。
  還沒做：App Store Connect 建 app、上傳、填 TestFlight 資料。待決定：公開版要不要關掉開 app 就詢問通知（別人收不到推播）
- 目標：隱私權政策頁、export compliance、版本號就緒；Archive 上傳成功；App Store Connect 建好 app、填好測試資訊與公開連結設定，**停在送審前**
- 驗收：TestFlight 看得到處理完的 build；送審表單填完、截圖給使用者看；聯絡資料向使用者要
- 碰：`ios/project.yml`、`docs/privacy.md`（新）、README「怎麼裝」
- 不做：按送審（使用者按）；上架 App Store

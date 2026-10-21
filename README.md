# session-remote

iPhone 上看這台 Air 所有 iTerm2 裡的 Claude Code session（兩個帳號合一），並從手機回答。
規格見 `SPEC.md`，給 agent 的規則與踩過的坑見 `AGENTS.md`。

## 第一次設定（要你本人做的）

1. **允許控制 iTerm2**：常駐服務第一次動作時，macOS 會跳「python3.15 想控制 iTerm」→ 按「允許」。
   沒按之前手機會看到「iTerm2 沒回應」。
2. **裝 app 到 iPhone**：手機接上同一個 Wi-Fi（或用線接 Mac）、解鎖，跑 `tools/install-ios.sh`。
3. **配對**：`backend/.venv/bin/python tools/pair.py` 印出 QR code，用 iPhone 相機掃 → 打開 Sessions app 自動填好。
4. **推播（選做）**：developer.apple.com → Certificates, IDs & Profiles → Keys → ＋ →
   勾「Apple Push Notifications service (APNs)」→ 下載 `.p8`（只能下載一次）。
   放到 `~/.config/session-remote/AuthKey_<KeyID>.p8`，在 `.env` 填 `APNS_KEY_PATH`、`APNS_KEY_ID`，
   再跑 `tools/install-agent.sh` 重啟服務。`curl localhost:5391/health` 的 `push` 變 `true` 就好了。

## 日常

| 要做的事 | 指令 |
|---|---|
| 開一組 iTerm2 四宮格 | `quad-iterm`（預設帳號）／`quad-iterm --account=peter`；2026-10-21 起放在 termkit repo（`~/Projects/termkit`） |
| 把 Terminal 裡的對話搬到 iTerm2 | 先在 Terminal 結束那個 claude，再 `ccmove` 看編號、`ccmove 3` 接回 |
| 服務狀態 | `curl -s localhost:5391/health`、`tail -f /tmp/session-remote.log` |
| 重啟服務 | `tools/install-agent.sh` |

**只有 iTerm2 裡的 session 會出現在手機上**；Terminal.app 裡的不會（規格）。
筆電要醒著、Tailscale 要開著，手機才連得到。

## 埠位

api 5391（web 5390 沒用到）。由 `proj new` 分配，登記在 `~/Projects/office/projects.json`。

"""環境設定集中在這裡讀。

**其他地方一律不要碰 os.environ。** 散在各處的環境變數讀取是最難追的一種
設定 bug：你改了 .env 卻有一半的程式沒吃到，而且看程式碼看不出來還有誰在讀。
"""

import os
import subprocess
from pathlib import Path

HOME = Path.home()
API_PORT = int(os.environ.get("API_PORT", "5391"))
WEB_PORT = int(os.environ.get("WEB_PORT", "5390"))

# 手機從 Tailscale 連進來，所以要聽 0.0.0.0；但只放行本機與 tailnet（100.64.0.0/10），
# 而且除了 /hook 以外都要帶通行碼（SESSION_REMOTE_TOKEN）。
HOST = os.environ.get("HOST", "0.0.0.0")
TOKEN = os.environ.get("SESSION_REMOTE_TOKEN", "")

DATA_DIR = Path(os.environ.get("SESSION_REMOTE_DATA", str(Path(__file__).resolve().parents[1] / "data")))
PROJECTS_ROOT = Path(os.environ.get("PROJECTS_ROOT", str(HOME / "Projects")))


def _local_host_name() -> str:
    try:
        return subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


# 帳號清單的唯一真相在 skills repo（acct、quad、pane-state 都讀同一份）
ACCOUNTS_FILE = Path(os.environ.get(
    "ACCOUNTS_FILE",
    str(HOME / ".claude/skills/home/claude/accounts" / f"{_local_host_name()}.json"),
))

# Apple 推播（APNs）。金鑰沒設定時推播整個略過，其他功能照常。
APNS_KEY_PATH = os.environ.get("APNS_KEY_PATH", "")
APNS_KEY_ID = os.environ.get("APNS_KEY_ID", "")
APNS_TEAM_ID = os.environ.get("APNS_TEAM_ID", "CXJ2S2G4JD")
APNS_BUNDLE_ID = os.environ.get("APNS_BUNDLE_ID", "com.bruuucechang.sessionremote")

# agent-quota 的選單列 app 每幾分鐘寫一次的額度快照（本機檔，不連網）
QUOTA_FILE = Path(os.environ.get("QUOTA_FILE", str(HOME / "Library/Application Support/agent-quota/widget.json")))
# skills 的 statusline.mjs 寫的每個 session 的 context 用量（<session_id>.json）
CONTEXT_DIR = Path(os.environ.get("CONTEXT_DIR", str(HOME / ".claude/state/context")))
UPLOAD_DIR = DATA_DIR / "uploads"

CORS_ORIGINS = [
    f"http://localhost:{WEB_PORT}",
    f"http://127.0.0.1:{WEB_PORT}",
]

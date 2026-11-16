#!/usr/bin/env python3
"""印出配對用的 QR code：iPhone 相機掃了會打開 Sessions app 並自動填好網址與通行碼。

    backend/.venv/bin/python tools/pair.py

網址用這台的 Tailscale IP（手機在外面也連得到）。通行碼從 .env 讀。
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlencode

import qrcode

ROOT = Path(__file__).resolve().parents[1]
env = dict(l.split("=", 1) for l in (ROOT / ".env").read_text().splitlines() if "=" in l and not l.startswith("#"))
token = env.get("SESSION_REMOTE_TOKEN", "").strip()
if not token:
    sys.exit(".env 裡沒有 SESSION_REMOTE_TOKEN")
# App Store 版的 Tailscale 沒有把 tailscale 指令放進 PATH：install.sh 會用 TAILSCALE 傳實際路徑
ts = os.environ.get("TAILSCALE") or shutil.which("tailscale") or "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
try:
    ip = subprocess.run([ts, "ip", "-4"], capture_output=True, text=True).stdout.split()
except OSError:
    ip = []
if not ip:
    sys.exit("拿不到 Tailscale IP（tailscale 沒開？）")
url = "sessionremote://setup?" + urlencode({"url": f"http://{ip[0]}:{env.get('API_PORT', '5391')}", "token": token})
qr = qrcode.QRCode(border=2)
qr.add_data(url)
qr.print_ascii(invert=True)
print(f"\n掃不了的話，在 app 的設定手動填：\n  網址   http://{ip[0]}:{env.get('API_PORT', '5391')}\n  通行碼 {token}")

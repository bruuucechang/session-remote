"""Claude Code 的對話紀錄檔（<設定目錄>/projects/<編碼過的 cwd>/<session_id>.jsonl）。

這裡只負責讀出原始紀錄；要怎麼排成聊天畫面是 services/transcript.py 的事。
紀錄檔可以長到好幾 MB，所以按 (路徑) 快取、只讀新增的部分。
"""

import json
import re
import threading
from pathlib import Path

KEEP = {"user", "assistant", "custom-title"}

_cache: dict[str, dict] = {}
_lock = threading.Lock()


def project_dir(config_dir: str, cwd: str) -> Path:
    return Path(config_dir) / "projects" / re.sub(r"[^A-Za-z0-9]", "-", cwd)


def latest_for(config_dir: str, cwd: str) -> str | None:
    """沒有 hook 回報過的 session：拿那個資料夾最近改過的紀錄檔充數。"""
    d = project_dir(config_dir, cwd)
    try:
        files = sorted(d.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    except FileNotFoundError:
        return None
    return str(files[0]) if files else None


def read(path: str) -> list[dict]:
    p = Path(path)
    try:
        size = p.stat().st_size
    except FileNotFoundError:
        return []
    with _lock:
        c = _cache.get(path)
        if c is None or size < c["offset"]:
            c = {"offset": 0, "entries": [], "partial": b""}
            _cache[path] = c
        if size > c["offset"]:
            with p.open("rb") as f:
                f.seek(c["offset"])
                chunk = c["partial"] + f.read(size - c["offset"])
            c["offset"] = size
            lines = chunk.split(b"\n")
            c["partial"] = lines.pop()   # 最後一行可能還沒寫完
            for line in lines:
                if not line.strip():
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get("type") in KEEP:
                    c["entries"].append(d)
        return list(c["entries"])

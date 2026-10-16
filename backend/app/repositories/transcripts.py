"""Claude Code 的對話紀錄檔（<設定目錄>/projects/<編碼過的 cwd>/<session_id>.jsonl）。

這裡只負責讀出原始紀錄；要怎麼排成聊天畫面是 services/transcript.py 的事。
紀錄檔可以長到好幾 MB，所以按 (路徑) 快取、只讀新增的部分。
"""

import json
import threading
from pathlib import Path

KEEP = {"user", "assistant", "custom-title"}

_cache: dict[str, dict] = {}
_lock = threading.Lock()


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

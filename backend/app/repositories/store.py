"""持久化：data/ 底下的小 JSON 檔，一個用途一個檔。

  sessions.json  hook 回報的 session 狀態（服務重開不能忘掉誰在等你回答）
  devices.json   手機的推播 token

分開放是刻意的：兩邊各自整份讀寫，放同一個檔會互相把對方的改動蓋掉。
"""

import json
import os
import threading
from pathlib import Path

from .. import config

_LOCK = threading.Lock()


def _file(name: str) -> Path:
    return config.DATA_DIR / f"{name}.json"


def load(name: str) -> dict:
    f = _file(name)
    try:
        return json.loads(f.read_text())
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        # 壞檔留著給人看，不要默默蓋掉
        f.rename(f.with_suffix(".corrupt.json"))
        return {}


def save(name: str, data: dict) -> None:
    with _LOCK:
        f = _file(name)
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp = Path(str(f) + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1))
        os.replace(tmp, f)

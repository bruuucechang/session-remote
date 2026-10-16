"""帳號清單（skills repo 的 accounts/<LocalHostName>.json，acct／quad 也讀這份）。"""

import json
import os

from .. import config


def load() -> list[dict]:
    try:
        return json.loads(config.ACCOUNTS_FILE.read_text())["accounts"]
    except Exception:
        return [{"id": "default", "label": "預設", "config_dir": "~/.claude"}]


def norm_dir(d: str) -> str:
    """設定目錄正規化成絕對路徑；空字串＝預設 ~/.claude。"""
    return os.path.realpath(os.path.expanduser(d or "~/.claude"))

"""每個 session 用了多少 context：skills 的 statusline.mjs 每次更新狀態列時寫的 <session_id>.json。

這個數字只有 Claude Code 給狀態列的輸入裡有（紀錄檔看不出 context 視窗多大），所以借狀態列寫出來。
"""

import json

from .. import config


def pct(session_id: str | None) -> int | None:
    if not session_id or "/" in session_id:
        return None
    try:
        d = json.loads((config.CONTEXT_DIR / f"{session_id}.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    v = d.get("pct")
    return int(v) if isinstance(v, (int, float)) else None

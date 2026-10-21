"""兩個 Claude 帳號的額度：讀 agent-quota 選單列 app 寫在本機的快照（widget.json），不連網。

快照裡每個帳號一列（key 是 claude-<帳號 id>），數字是 agent-quota 從官方 usage 端點拿的。
檔案不在（那台沒裝 agent-quota）就回空的，手機那一塊不顯示。
"""

import json

from .. import config


def rows() -> list[dict]:
    try:
        data = json.loads(config.QUOTA_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return []
    return [r for r in data.get("rows", []) if isinstance(r, dict)]


def generated_at() -> str | None:
    try:
        return json.loads(config.QUOTA_FILE.read_text()).get("generatedAt")
    except (FileNotFoundError, json.JSONDecodeError):
        return None

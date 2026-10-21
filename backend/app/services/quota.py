"""手機列表上方的額度條：這台機器上的帳號，各列 Claude 與 Codex（accounts 檔裡的 id ↔ 快照裡的 claude-<id>／codex-<id>）。"""

from ..repositories import accounts as accounts_repo
from ..repositories import quota as quota_repo


def accounts() -> dict:
    """每個帳號列 Claude 與 Codex 兩列（快照裡的 key 是 claude-<id>／codex-<id>），Claude 在前。"""
    rows = {r.get("key"): r for r in quota_repo.rows()}
    out = []
    for vendor in ("claude", "codex"):
        for a in accounts_repo.load():
            r = rows.get(f"{vendor}-{a.get('id')}")
            if not r:
                continue
            out.append({
                "id": f"{vendor}-{a.get('id')}",
                "account": a.get("id"),
                "vendor": vendor,
                "label": a.get("label") or a.get("id"),
                "weekly_pct": r.get("weeklyPercent"),
                "weekly_resets": r.get("weeklyResetsAt"),
                "short_pct": r.get("shortPercent"),
                "short_resets": r.get("shortResetsAt"),
                "stale": bool(r.get("stale")),
                "blocked": bool(r.get("blocked")),
            })
    return {"accounts": out, "generated_at": quota_repo.generated_at()}

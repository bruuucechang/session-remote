"""手機列表上方的額度條：只列這台機器上有的 Claude 帳號（accounts 檔裡的 id ↔ 快照裡的 claude-<id>）。"""

from ..repositories import accounts as accounts_repo
from ..repositories import quota as quota_repo


def accounts() -> dict:
    rows = {r.get("key"): r for r in quota_repo.rows()}
    out = []
    for a in accounts_repo.load():
        r = rows.get(f"claude-{a.get('id')}")
        if not r:
            continue
        out.append({
            "id": a.get("id"),
            "label": a.get("label") or a.get("id"),
            "weekly_pct": r.get("weeklyPercent"),
            "weekly_resets": r.get("weeklyResetsAt"),
            "short_pct": r.get("shortPercent"),
            "short_resets": r.get("shortResetsAt"),
            "stale": bool(r.get("stale")),
            "blocked": bool(r.get("blocked")),
        })
    return {"accounts": out, "generated_at": quota_repo.generated_at()}

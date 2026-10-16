#!/usr/bin/env python3
"""把 Terminal.app 裡的 Claude Code 對話搬到 iTerm2（手機才看得到、回得了）。

    ccmove            列出兩個帳號最近 48 小時的對話（最新的在上面）
    ccmove 3          在 iTerm2 開新分頁，用對的帳號 `claude --resume` 接回第 3 個
    ccmove 3 5 6      一次接回好幾個

流程：先在 Terminal 那邊結束那個 claude（/exit 或 Ctrl+C 兩次），再跑 ccmove 接回。
還在跑的（hook 回報過、程序還活著）會標「執行中」並拒絕接回——同一個對話開兩個 claude
會各寫各的，紀錄檔會打架。確定它已經關了的話加 --force。
"""

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from app.repositories import accounts as accounts_repo  # noqa: E402
from app.repositories import iterm  # noqa: E402

WINDOW_H = 48


def running_session_ids() -> set[str]:
    try:
        state = json.loads((ROOT / "backend/data/sessions.json").read_text())
    except Exception:
        return set()
    alive = set()
    for rec in state.values():
        pid = rec.get("pid")
        try:
            if pid:
                os.kill(pid, 0)
                alive.add(rec.get("session_id"))
        except OSError:
            pass
    return alive


def summarize(path: Path) -> tuple[str, str]:
    """回傳 (標題, cwd)。標題取最後一個 custom-title，沒有就用第一句話。"""
    title, first, cwd = "", "", ""
    with path.open(errors="replace") as f:
        for line in f:
            if '"custom-title"' in line:
                try:
                    title = json.loads(line).get("customTitle") or title
                except json.JSONDecodeError:
                    pass
            elif not cwd and '"type":"user"' in line:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                cwd = d.get("cwd", "")
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str) and not c.startswith("<"):
                    first = c.strip().splitlines()[0][:60] if c.strip() else ""
    return title or first or "（沒有標題）", cwd


def recent() -> list[dict]:
    out = []
    cutoff = time.time() - WINDOW_H * 3600
    for a in accounts_repo.load():
        cfg = accounts_repo.norm_dir(a.get("config_dir", ""))
        for p in Path(cfg, "projects").glob("*/*.jsonl"):
            m = p.stat().st_mtime
            if m < cutoff:
                continue
            out.append({"path": p, "mtime": m, "account": a, "config_dir": cfg, "session_id": p.stem})
    out.sort(key=lambda r: r["mtime"], reverse=True)
    return out[:20]


def main(argv: list[str]) -> int:
    force = "--force" in argv
    picks = [int(x) for x in argv if x.isdigit()]
    rows = recent()
    running = running_session_ids()
    if not picks:
        for i, r in enumerate(rows, 1):
            title, cwd = summarize(r["path"])
            r["title"], r["cwd"] = title, cwd
            ago = int((time.time() - r["mtime"]) / 60)
            when = f"{ago} 分前" if ago < 120 else f"{ago // 60} 小時前"
            flag = "  [執行中]" if r["session_id"] in running else ""
            print(f"{i:>2}. {title[:40]:<40}  {r['account'].get('id'):<6} {when:>8}  {Path(cwd).name}{flag}")
        print("\n接回：ccmove <編號> [<編號> …]　（先在 Terminal 結束那個 claude）")
        return 0
    for n in picks:
        if not 1 <= n <= len(rows):
            print(f"✗ 沒有第 {n} 個")
            continue
        r = rows[n - 1]
        title, cwd = summarize(r["path"])
        if r["session_id"] in running and not force:
            print(f"✗ {n}. {title} 還在跑，先在 Terminal 結束它（確定關了就加 --force）")
            continue
        if cwd and not os.path.isdir(cwd):
            cwd = str(Path.home())
        if r["config_dir"] == accounts_repo.norm_dir(""):
            run = "env -u CLAUDE_CONFIG_DIR claude"
        else:
            run = f"CLAUDE_CONFIG_DIR={shlex.quote(r['config_dir'])} claude"
        iterm.new_tab(f"cd {shlex.quote(cwd or str(Path.home()))} && {run} --resume {r['session_id']}")
        print(f"✓ {n}. {title} → iTerm2（{r['account'].get('id')}）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""把 hooks/report.mjs 掛進 Claude Code 的 settings.json（給公開版安裝用，tools/install.sh 會叫）。

    python3 tools/install_hooks.py [--dry-run] [--settings 路徑]

- 預設改 $CLAUDE_CONFIG_DIR/settings.json，沒設就是 ~/.claude/settings.json。
- 改之前先備份成 settings.json.bak-<時間>；檔案不存在就新建。
- 重跑安全：某個事件底下已經有指令含 report.mjs 就不再加；是這支寫的格式而埠或路徑變了，就改成新的。
- 用 node 直接跑、不包 shell：report.mjs 用父程序 pid 快取 tty，包一層 shell 快取永遠不中。
"""
import argparse
import json
import os
import re
import shlex
import shutil
import sys
import time
from pathlib import Path

EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
REPORT = Path(__file__).resolve().parents[1] / "hooks" / "report.mjs"


def default_settings() -> Path:
    base = os.environ.get("CLAUDE_CONFIG_DIR") or str(Path.home() / ".claude")
    return Path(base).expanduser() / "settings.json"


# 這支工具自己寫的格式：node <加了引號的 …/hooks/report.mjs> <事件>[ <埠>]。只有這種會被改寫（換埠、搬 repo 後重裝）；
# 別的寫法（例如作者自己包一層 ext.mjs）當成使用者自己管的，看到就不加也不動。


def managed(cmd: str) -> bool:
    """用 shell 的規則拆開再比：node <…/hooks/report.mjs> <事件> [<埠>]。路徑含引號、$ 也認得。"""
    try:
        a = shlex.split(cmd)
    except ValueError:
        return False
    return (len(a) in (3, 4) and a[0] == "node" and a[1].endswith("/hooks/report.mjs")
            and a[2].isalnum() and (len(a) == 3 or a[3].isdigit()))


def merge(settings: dict, report: Path, port: str = "5391") -> list[str]:
    """把缺的或過期的事件寫進 settings，回傳改了哪些事件。埠不是預設的 5391 才帶在參數後面。"""
    hooks = settings.setdefault("hooks", {})
    suffix = "" if port in ("", "5391") else f" {port}"
    changed = []
    for ev in EVENTS:
        want = f"node {shlex.quote(str(report))} {ev}{suffix}"  # 路徑可能含 $、反引號：用單引號規則
        groups = hooks.setdefault(ev, [])
        mine = [h for g in groups for h in g.get("hooks", []) if "report.mjs" in h.get("command", "")]
        if not mine:
            groups.append({"hooks": [{"type": "command", "command": want, "async": True}]})
            changed.append(ev)
            continue
        for h in mine:
            if managed(h.get("command", "")) and h["command"] != want:
                h["command"] = want
                if ev not in changed:
                    changed.append(ev)
    return changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--settings", type=Path, default=None)
    ap.add_argument("--port", default="5391", help="服務的埠（.env 的 API_PORT）")
    a = ap.parse_args()
    path = a.settings or default_settings()

    settings = {}
    if path.exists():
        try:
            settings = json.loads(path.read_text() or "{}")
        except json.JSONDecodeError as e:
            print(f"✗ {path} 不是合法的 JSON（{e}），不動它", file=sys.stderr)
            return 1
    added = merge(settings, REPORT, a.port)
    if not added:
        print(f"✓ hook 已經掛好了（{path}）")
        return 0
    if a.dry_run:
        print(f"（試跑）會在 {path} 加上或更新：{', '.join(added)}")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        stamp = time.strftime('%Y%m%d-%H%M%S')
        bak = path.with_name(f"{path.name}.bak-{stamp}")
        n = 1
        while bak.exists():  # 同一秒跑兩次不能蓋掉第一份（那份才是安裝前的原樣）
            bak = path.with_name(f"{path.name}.bak-{stamp}-{n}")
            n += 1
        shutil.copy2(path, bak)
        print(f"  備份：{bak}")
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
    tmp.replace(path)
    print(f"✓ 在 {path} 加上或更新 hook：{', '.join(added)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

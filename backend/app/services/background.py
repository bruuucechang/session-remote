"""背景任務：回合結束了，Claude 用 Bash 開的背景程序還活著（run_in_background、waitfor）。

判定與顯示的規則都在這裡；去哪裡拿程序清單是 `repositories/procs.background_shells` 的事。
"""

import os
import re

# Claude Code 的 Bash 工具每次都開一個 `zsh -c "source …/shell-snapshots/snapshot-….sh … && eval '<指令>' < /dev/null …"`
_MARK = "shell-snapshots/snapshot-"
_EVAL = re.compile(r"\beval '(.*)' < /dev/null", re.S)
_LABEL = re.compile(r"--label[ =]['\"]?([^\s'\"]+)")
# 只是在準備的那幾行：設變數、換資料夾、export
_SETUP = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=\S*|cd\s.*|export\s.*|set\s.*|source\s.*|\.\s.*)$")
_MAX = 80


def is_tool_shell(command: str) -> bool:
    return _MARK in command


def label(command: str) -> str:
    """手機上一行講得出它在跑什麼：waitfor 用它的 label，其他取第一個真的在做事的指令。"""
    m = _EVAL.search(command)
    body = m.group(1) if m else command
    # ps 把換行印成 \012；單引號在 eval '…' 裡被寫成 '\''
    body = body.replace("\\012", "\n").replace("'\\''", "'")
    lb = _LABEL.search(body)
    if lb and "waitfor" in body:
        return f"waitfor {lb.group(1)}"
    home = os.path.expanduser("~")
    for part in re.split(r"\n|;|&&", body):
        part = " ".join(part.split())
        if not part or _SETUP.match(part):
            continue
        part = part.replace(home, "~")
        return part if len(part) <= _MAX else part[: _MAX - 1] + "…"
    return "背景指令"


def labels(commands: list[str]) -> list[str]:
    return [label(c) for c in commands if is_tool_shell(c)]

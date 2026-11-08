"""這台機器上正在跑的 claude 程序：在哪個 tty、哪個設定目錄（帳號）、工作目錄。"""

import re
import os
import subprocess
from dataclasses import dataclass

from .. import config


@dataclass
class ClaudeProc:
    pid: int
    tty: str          # /dev/ttys003
    config_dir: str   # 空字串＝預設 ~/.claude
    cwd: str


def _run(args: list[str]) -> str:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


def _cwd(pid: int) -> str:
    out = _run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
    for line in out.splitlines():
        if line.startswith("n"):
            return line[1:]
    return ""


def _config_dir(pid: int) -> str:
    # ps eww 只看得到自己這個使用者的程序環境變數；claude 都是自己開的，夠用
    m = re.search(r"\bCLAUDE_CONFIG_DIR=(\S+)", _run(["ps", "eww", "-o", "command=", "-p", str(pid)]))
    return m.group(1) if m else ""


def list_claude() -> list[ClaudeProc]:
    out = _run(["ps", "-axo", "pid=,tty=,comm="])
    procs = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3 or parts[1] in ("??", "-"):
            continue
        comm = parts[2].strip()
        if comm != "claude" and not comm.endswith("/claude"):
            continue
        pid = int(parts[0])
        procs.append(ClaudeProc(pid=pid, tty="/dev/" + parts[1], config_dir=_config_dir(pid), cwd=_cwd(pid)))
    return procs


def background_shells() -> dict[int, list[str]] | None:
    """每個程序底下的子程序指令（按父程序 pid）。一次 ps 全拿，判斷哪些算背景任務是 services 的事。
    ps 失敗（逾時）回 None：正常的 ps 至少列得出自己，空的一定是失敗，不能當成「沒有子程序」。"""
    out = _run(["ps", "-ww", "-axo", "ppid=,command="])
    if not out.strip():
        return None
    kids: dict[int, list[str]] = {}
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            kids.setdefault(int(parts[0]), []).append(parts[1])
    return kids


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


# 假資料模式：整組換成替身（UI 測試用，不碰真的 iTerm2／程序）
if config.FAKE:
    from . import fake as _fake
    list_claude = _fake.list_claude  # noqa: F811
    alive = _fake.alive  # noqa: F811
    background_shells = _fake.background_shells  # noqa: F811

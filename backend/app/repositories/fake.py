"""假資料模式（SR_FAKE=<scenario.json>）：給 UI 測試用的 iTerm2 與程序替身。

開了這個模式，`iterm` 與 `procs` 的函式整組換成這裡的（見兩個檔案最底下），
不碰真的 iTerm2、不送任何字進真的 session。送出去的字、按鍵、開關分頁都記在 `log()`，
測試用 `/fake/log` 讀回來核對。

scenario.json 的形狀：
  {"sessions": [{"id", "tty", "pid", "cwd", "config_dir", "name",
                 "screen": "相對 scenario 的畫面文字檔（可省）",
                 "record": {sessions.json 裡那一筆：status、pending、activity…},
                 "transcript": "相對 scenario 的 .jsonl（可省）",
                 "starred": true（可省）, "close_fails": true（可省：關分頁丟 ItermError）,
                 "write_fails": true（可省：送字丟 ItermError）,
                 "background": ["回合結束後還在跑的背景指令", …]（可省）}],
   "quota": {"rows": [agent-quota widget.json 的列；*ResetsAt 可寫 "+26h"＝從現在算起]}（可省＝沒有額度卡）}

別的情境放在同一個資料夾的 scenario-<名字>.json，`reset("<名字>")` 換過去。
"""

import json
import os
import re
import shlex
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .. import config

_lock = threading.Lock()
_state: dict = {}


def _base() -> Path:
    return Path(config.FAKE).resolve().parent


def _load() -> dict:
    return json.loads(Path(_state.get("file") or config.FAKE).read_text())


def _write_quota(q: dict | None) -> None:
    # 沒明講 QUOTA_FILE 就會寫到 agent-quota 真的快照（tools/fake-backend.sh 會指到暫存目錄）
    if "QUOTA_FILE" not in os.environ:
        raise RuntimeError("假資料模式要指定 QUOTA_FILE，不然會改到真的額度快照")
    if q is None:
        config.QUOTA_FILE.unlink(missing_ok=True)
        return
    now = datetime.now(timezone.utc)

    def at(v):
        m = re.fullmatch(r"\+(\d+)h", str(v))
        return (now + timedelta(hours=int(m[1]))).isoformat() if m else v

    rows = [{k: at(v) if k.endswith("ResetsAt") else v for k, v in r.items()} for r in q.get("rows", [])]
    config.QUOTA_FILE.write_text(json.dumps({"generatedAt": now.isoformat(), "rows": rows}))


def reset(name: str = "") -> None:
    """回到 scenario 的初始狀態：分頁、畫面、送字紀錄全部重來。name 給了就換成 scenario-<name>.json。"""
    if name and not re.fullmatch(r"[a-z0-9-]+", name):
        raise ValueError(f"情境名稱只能是小寫英數與 -：{name}")
    file = str(_base() / f"scenario-{name}.json") if name else config.FAKE
    sc = json.loads(Path(file).read_text())   # 讀得到才換：情境名稱打錯時留在原本的情境
    _state["file"] = file
    _write_quota(sc.get("quota"))
    with _lock:
        _state["sessions"] = {s["id"]: dict(s) for s in sc.get("sessions", [])}
        _state["screens"] = {
            s["id"]: (_base() / s["screen"]).read_text() if s.get("screen") else ""
            for s in sc.get("sessions", [])
        }
        _state["log"] = []
        _state["next"] = 1


def records() -> dict:
    """scenario 換算成 sessions.json 的內容（按 tty），紀錄檔路徑換成絕對路徑。"""
    out = {}
    for s in _load().get("sessions", []):
        rec = {"tty": s["tty"], "pid": s["pid"], "config_dir": s.get("config_dir", ""),
               "cwd": s.get("cwd"), "session_id": s.get("session_id") or s["id"].lower(),
               "status": "idle", "status_since": None, "pending": None, "activity": ""}
        rec.update(s.get("record") or {})
        if s.get("transcript"):
            rec["transcript_path"] = str(_base() / s["transcript"])
        out[s["tty"]] = rec
    return out


def starred() -> list[str]:
    return [s["id"] for s in _load().get("sessions", []) if s.get("starred")]


def log() -> list[dict]:
    with _lock:
        return list(_state["log"])


def set_screen(session_id: str, text: str) -> None:
    with _lock:
        _state["screens"][session_id] = text


def _add(entry: dict) -> None:
    with _lock:
        _state["log"].append(entry)


# ---------------------------------------------------------------- iterm 替身


def is_running() -> bool:
    return True


def list_sessions():
    from .iterm import ItermSession
    with _lock:
        return [ItermSession(id=s["id"], tty=s["tty"], name=s.get("name", "")) for s in _state["sessions"].values()]


def _need(session_id: str) -> None:
    from .iterm import ItermError
    if session_id not in _state["sessions"]:
        raise ItermError(f"找不到 iTerm2 分頁 {session_id}")


def contents(session_id: str) -> str:
    _need(session_id)
    with _lock:
        return _state["screens"].get(session_id, "")


def write(session_id: str, text: str) -> None:
    from .iterm import ItermError
    _need(session_id)
    if _state["sessions"][session_id].get("write_fails"):
        raise ItermError("假資料：送字失敗")
    _add({"op": "write", "id": session_id, "text": text})


def write_ascii(session_id: str, code: int) -> None:
    _need(session_id)
    _add({"op": "ascii", "id": session_id, "code": code})


def write_seq(session_id: str, seq: str) -> None:
    _need(session_id)
    _add({"op": "seq", "id": session_id, "seq": seq})


def close(session_id: str) -> None:
    from .iterm import ItermError
    _need(session_id)
    if _state["sessions"][session_id].get("close_fails"):
        raise ItermError("假資料：這個分頁關不掉")
    with _lock:
        _state["sessions"].pop(session_id, None)
    _add({"op": "close", "id": session_id})


def new_tab(command: str) -> str:
    """記下指令，並真的多一個分頁（列表上看得到、點得進去），資料夾與帳號照指令裡的 cd 與 CLAUDE_CONFIG_DIR。"""
    words = shlex.split(command)
    cwd = words[words.index("cd") + 1] if "cd" in words else ""
    cfg = next((w.split("=", 1)[1] for w in words if w.startswith("CLAUDE_CONFIG_DIR=")), "")
    with _lock:
        n = _state["next"]
        _state["next"] += 1
        sid = f"FAKE-NEW-{n}"
        _state["sessions"][sid] = {"id": sid, "tty": f"/dev/fakenew{n}", "pid": 910000 + n, "cwd": cwd,
                                   "config_dir": cfg, "name": Path(cwd).name}
        _state["screens"][sid] = ""
    _add({"op": "new_tab", "id": sid, "command": command})
    return sid


# ---------------------------------------------------------------- procs 替身


def list_claude():
    from .procs import ClaudeProc
    with _lock:
        return [ClaudeProc(pid=s["pid"], tty=s["tty"], config_dir=s.get("config_dir", ""), cwd=s.get("cwd", ""))
                for s in _state["sessions"].values()]


def background_shells() -> dict[int, list[str]]:
    """scenario 的 "background": ["指令", …]＝這個 session 回合結束後還活著的背景 Bash（照真的格式包起來）。"""
    pre = "/bin/zsh -c source ~/.claude/shell-snapshots/snapshot-zsh-0-fake.sh && eval '"
    with _lock:
        return {s["pid"]: [pre + c + "' < /dev/null" for c in s.get("background", [])]
                for s in _state["sessions"].values() if s.get("background")}


def alive(pid: int) -> bool:
    # 永遠當它已經結束：actions.close 才不會對假的 pid 送 SIGTERM
    return False


if config.FAKE:
    reset()

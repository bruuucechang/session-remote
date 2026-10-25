"""假資料模式（SR_FAKE=<scenario.json>）：給 UI 測試用的 iTerm2 與程序替身。

開了這個模式，`iterm` 與 `procs` 的函式整組換成這裡的（見兩個檔案最底下），
不碰真的 iTerm2、不送任何字進真的 session。送出去的字、按鍵、開關分頁都記在 `log()`，
測試用 `/fake/log` 讀回來核對。

scenario.json 的形狀：
  {"sessions": [{"id", "tty", "pid", "cwd", "config_dir", "name",
                 "screen": "相對 scenario 的畫面文字檔（可省）",
                 "record": {sessions.json 裡那一筆：status、pending、activity…},
                 "transcript": "相對 scenario 的 .jsonl（可省）"}]}
"""

import json
import threading
from pathlib import Path

from .. import config

_lock = threading.Lock()
_state: dict = {}


def _base() -> Path:
    return Path(config.FAKE).resolve().parent


def _load() -> dict:
    return json.loads(Path(config.FAKE).read_text())


def reset() -> None:
    """回到 scenario 的初始狀態：分頁、畫面、送字紀錄全部重來。"""
    sc = _load()
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
    _need(session_id)
    _add({"op": "write", "id": session_id, "text": text})


def write_ascii(session_id: str, code: int) -> None:
    _need(session_id)
    _add({"op": "ascii", "id": session_id, "code": code})


def write_seq(session_id: str, seq: str) -> None:
    _need(session_id)
    _add({"op": "seq", "id": session_id, "seq": seq})


def close(session_id: str) -> None:
    _need(session_id)
    with _lock:
        _state["sessions"].pop(session_id, None)
    _add({"op": "close", "id": session_id})


def new_tab(command: str) -> str:
    with _lock:
        sid = f"FAKE-NEW-{_state['next']}"
        _state["next"] += 1
    _add({"op": "new_tab", "id": sid, "command": command})
    return sid


# ---------------------------------------------------------------- procs 替身


def list_claude():
    from .procs import ClaudeProc
    with _lock:
        return [ClaudeProc(pid=s["pid"], tty=s["tty"], config_dir=s.get("config_dir", ""), cwd=s.get("cwd", ""))
                for s in _state["sessions"].values()]


def alive(pid: int) -> bool:
    # 永遠當它已經結束：actions.close 才不會對假的 pid 送 SIGTERM
    return False


if config.FAKE:
    reset()

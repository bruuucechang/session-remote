"""Session 的狀態機與列表。

兩個來源合起來：
  - hook 回報（按 tty 存）：狀態、正在問什麼、紀錄檔在哪
  - 現況掃描：iTerm2 有哪些分頁、哪些分頁上跑著 claude、是哪個帳號

**只列 iTerm2 分頁上的 claude**（規格：Terminal.app 裡的不列）。
列表的 id 用 iTerm2 分頁 id——它在分頁存活期間不變，送字也是用它。

狀態：
  working 工作中 → waiting 等你回答 → done 做完 / idle 待命 / unknown 還沒回報過
"""

import os
import threading
import time
from datetime import datetime, timezone

from ..repositories import contexts, accounts as accounts_repo
from ..repositories import iterm, procs, store, transcripts
from . import events, notify, screen, transcript

WAITING, WORKING, DONE, IDLE, UNKNOWN = "waiting", "working", "done", "idle", "unknown"

_lock = threading.RLock()
_state = {"sessions": store.load("sessions")}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _save():
    store.save("sessions", _state["sessions"])


def _set(rec: dict, status: str, pending=None, activity=None) -> bool:
    changed = rec.get("status") != status
    if changed:
        rec["status_since"] = _now()
    rec["status"] = status
    rec["pending"] = pending
    if activity is not None:
        rec["activity"] = activity
    return changed


# ---------------------------------------------------------------- hook 進來


def apply_hook(event: str, tty: str | None, pid: int | None, config_dir: str, payload: dict) -> None:
    if not tty:
        return
    with _lock:
        sessions = _state["sessions"]
        if event == "SessionEnd":
            sessions.pop(tty, None)
            _save()
            events.bump()
            notify.summary_changed()
            return
        rec = sessions.get(tty)
        sid = payload.get("session_id")
        # 同一個 tty 換了一個 claude（舊的關掉、新的開起來）：整筆重來
        if rec is None or rec.get("pid") != pid or (sid and rec.get("session_id") not in (None, sid)):
            rec = {"tty": tty, "status": IDLE, "status_since": _now(), "pending": None, "activity": ""}
            sessions[tty] = rec
        rec.update({
            "pid": pid,
            "config_dir": config_dir,
            "session_id": sid or rec.get("session_id"),
            "transcript_path": payload.get("transcript_path") or rec.get("transcript_path"),
            "cwd": payload.get("cwd") or rec.get("cwd"),
            "updated": _now(),
        })
        prev = rec.get("status")
        tool = payload.get("tool_name", "")

        if event == "SessionStart":
            _set(rec, IDLE)
        elif event == "UserPromptSubmit":
            _set(rec, WORKING, activity="")
        elif event == "PreToolUse":
            if tool == "AskUserQuestion":
                qs = (payload.get("tool_input") or {}).get("questions") or []
                _set(rec, WAITING, pending={"kind": "ask", "questions": qs})
            else:
                _set(rec, WORKING, activity=f"{tool}：{transcript.tool_summary(tool, payload.get('tool_input'))}")
        elif event == "PostToolUse":
            _set(rec, WORKING)
        elif event == "Notification":
            msg = payload.get("message", "")
            kind = payload.get("notification_type", "")
            if kind == "idle_prompt" or "waiting for your input" in msg:
                pass   # 做完 60 秒後的「閒置」提醒：狀態已經是 done，不重複
            elif rec.get("status") != WAITING or (rec.get("pending") or {}).get("kind") != "ask":
                _set(rec, WAITING, pending={"kind": "permission", "message": msg})
        elif event == "Stop":
            _set(rec, DONE)

        _save()
        new = rec.get("status")
    events.bump()
    if new != prev:
        # 每一次狀態變了都要通知：跳通知只在等你／做完，但紅點數字與鎖定畫面的狀態每一種變化都要跟
        notify.session_changed(tty)


def mark_idle(tty: str) -> None:
    with _lock:
        rec = _state["sessions"].get(tty)
        if rec:
            _set(rec, IDLE)
            _save()
    events.bump()
    notify.summary_changed()


def forget(tty: str) -> None:
    """分頁從手機關掉了：不等 SessionEnd hook（被 SIGTERM 的時候不一定有）"""
    with _lock:
        _state["sessions"].pop(tty, None)
        _save()
    global _scan_cache
    _scan_cache = (0.0, [])
    events.bump()
    notify.summary_changed()


# ---------------------------------------------------------------- 列表


_scan_cache: tuple[float, list] = (0.0, [])
_SCAN_TTL = 1.5


def _scan() -> list[tuple[iterm.ItermSession, procs.ClaudeProc]]:
    global _scan_cache
    if time.time() - _scan_cache[0] < _SCAN_TTL:
        return _scan_cache[1]
    by_tty = {}
    for p in procs.list_claude():
        # 同一個 tty 上有兩個 claude（巢狀）時取 pid 小的那個，也就是使用者開的
        if p.tty not in by_tty or p.pid < by_tty[p.tty].pid:
            by_tty[p.tty] = p
    pairs = [(s, by_tty[s.tty]) for s in iterm.list_sessions() if s.tty in by_tty]
    _scan_cache = (time.time(), pairs)
    return pairs


def _account(config_dir: str) -> dict:
    target = accounts_repo.norm_dir(config_dir)
    for a in accounts_repo.load():
        if accounts_repo.norm_dir(a.get("config_dir", "")) == target:
            return {"id": a.get("id"), "label": a.get("label") or a.get("id")}
    return {"id": "unknown", "label": os.path.basename(target)}


def _record_for(proc: procs.ClaudeProc) -> dict:
    rec = _state["sessions"].get(proc.tty)
    if rec and rec.get("pid") == proc.pid:
        return rec
    return {}


def _transcript_path(rec: dict, proc: procs.ClaudeProc) -> str | None:
    # 還沒回報過的 session 不猜紀錄檔：同一個資料夾常有好幾個對話，猜錯會把別人的內容秀出來
    return rec.get("transcript_path")


def _view(s: iterm.ItermSession, proc: procs.ClaudeProc, with_messages: bool = False) -> dict:
    rec = _record_for(proc)
    path = _transcript_path(rec, proc)
    built = transcript.build(transcripts.read(path)) if path else {"title": None, "messages": []}
    cwd = rec.get("cwd") or proc.cwd
    # 還沒有標題時用資料夾名：iTerm2 分頁名在這之前是 shell 的指令（例如「cd (claude)」），沒有意義
    name = built["title"] or os.path.basename(cwd.rstrip("/")) or s.name.strip()
    status, pending = rec.get("status", UNKNOWN), rec.get("pending")
    if status == UNKNOWN:
        # 還沒回報過（例如剛開、卡在「信任這個資料夾嗎」）：看畫面上是不是正在問
        try:
            prompt = screen.parse_prompt(iterm.contents(s.id))
        except iterm.ItermError:
            prompt = None
        if prompt:
            status = WAITING
            pending = {"kind": "screen", "message": " / ".join(o["label"] for o in prompt["options"])}
    view = {
        "id": s.id,
        "tty": proc.tty,
        "name": name,
        "cwd": cwd,
        "account": _account(proc.config_dir),
        "status": status,
        "status_since": rec.get("status_since"),
        "activity": rec.get("activity", ""),
        "pending": pending,
        "last_text": transcript.last_text(built["messages"])[:300],
        "session_id": rec.get("session_id"),
        "context_pct": contexts.pct(rec.get("session_id")),
    }
    if with_messages:
        view["messages"] = built["messages"]
    return view


_ORDER = {WAITING: 0, DONE: 1, WORKING: 2, IDLE: 3, UNKNOWN: 4}


def list_views() -> list[dict]:
    with _lock:
        views = [_view(s, p) for s, p in _scan()]
    views.sort(key=lambda v: (_ORDER.get(v["status"], 9), v["name"]))
    return views


def find(session_id: str) -> tuple[iterm.ItermSession, procs.ClaudeProc] | None:
    for s, p in _scan():
        if s.id == session_id:
            return s, p
    return None


def page(messages: list[dict], limit: int, after: str | None = None, before: str | None = None) -> dict:
    """手機只抓它還沒有的那一段（省行動網路）。

    after：那一則之後的全部；找不到（例如 /clear 換了紀錄檔）就回最後 limit 則並標 reset，手機整串換掉。
    before：那一則之前的 limit 則（往上滑載入更早的）。
    has_more：回傳的第一則之前還有沒有。
    """
    ids = [m["id"] for m in messages]
    if after is not None and after in ids:
        start = ids.index(after) + 1
        return {"messages": messages[start:], "reset": False, "has_more": False, "partial": True}
    if before is not None and before in ids:
        end = ids.index(before)
        start = max(0, end - limit)
        return {"messages": messages[start:end], "reset": False, "has_more": start > 0, "partial": True}
    start = max(0, len(messages) - limit)
    return {"messages": messages[start:], "reset": True, "has_more": start > 0, "partial": False}


def detail(session_id: str, limit: int = 200, after: str | None = None, before: str | None = None) -> dict | None:
    hit = find(session_id)
    if not hit:
        return None
    with _lock:
        v = _view(*hit, with_messages=True)
    v["total_messages"] = len(v["messages"])
    pg = page(v["messages"], limit, after, before)
    v["messages"] = pg["messages"]
    v["reset"] = pg["reset"]
    v["has_more"] = pg["has_more"]
    try:
        text = iterm.contents(session_id)
        v["prompt"] = screen.parse_prompt(text)
        v["screen"] = screen.tail(text)
    except iterm.ItermError:
        v["prompt"], v["screen"] = None, []
    return v


def waiting_count() -> int:
    return sum(1 for v in list_views() if v["status"] == WAITING)


def summary() -> dict:
    """鎖定畫面與動態島要顯示的：幾個在工作、幾個等你、等你的第一個在問什麼。"""
    views = list_views()
    waiting = [v for v in views if v["status"] == WAITING]
    working = [v for v in views if v["status"] == WORKING]
    if waiting:
        top = waiting[0]
        pending = top.get("pending") or {}
        qs = pending.get("questions") or []
        ask = qs[0].get("question") if pending.get("kind") == "ask" and qs else None
        headline = f"{top['name'].split('｜')[0]}：{ask or pending.get('message') or '等你回答'}"
    elif working:
        top = working[0]
        headline = f"{top['name'].split('｜')[0]}：{top.get('activity') or '工作中'}"
    else:
        headline = "都做完了"
    return {"working": len(working), "waiting": len(waiting),
            "done": sum(1 for v in views if v["status"] == DONE), "headline": headline[:120]}


def view_by_tty(tty: str) -> dict | None:
    for s, p in _scan():
        if p.tty == tty:
            with _lock:
                return _view(s, p)
    return None

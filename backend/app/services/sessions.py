"""Session 的狀態機與列表。

兩個來源合起來：
  - hook 回報（按 tty 存）：狀態、正在問什麼、紀錄檔在哪
  - 現況掃描：iTerm2 有哪些分頁、哪些分頁上跑著 claude、是哪個帳號

**只列 iTerm2 分頁上的 claude**（規格：Terminal.app 裡的不列）。
列表的 id 用 iTerm2 分頁 id——它在分頁存活期間不變，送字也是用它。

狀態：
  working 工作中 → waiting 等你回答 → done 完工 / idle 待命 / unknown 還沒回報過
  background 背景跑：不是 hook 給的，是列表時算的——done／idle 但 Claude 開的背景 Bash 還活著。
  背景全部結束時 `check_background` 把完工時間改成第一次看到結束的那一刻，再等一輪（Claude Code 會叫醒模型接著做）
  還停在完工才通知（推播只在那時候跳，所以完工時間會比推播早最多一輪）。
"""

import os
import threading
import time
from datetime import datetime, timezone

from ..repositories import contexts, accounts as accounts_repo
from ..repositories import iterm, procs, store, transcripts
from . import background, events, notify, screen, transcript

WAITING, WORKING, DONE, IDLE, UNKNOWN = "waiting", "working", "done", "idle", "unknown"
BACKGROUND = "background"

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
            # 只刪同一個 session 的：/clear 時新的 SessionStart 可能先到，舊的 SessionEnd 後到
            rec = sessions.get(tty)
            if rec and rec.get("session_id") not in (None, payload.get("session_id")):
                return
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
        # subagent 的工具事件帶同一個 session_id、多一個 agent_id：主線程正在問選項題時，它們不能把狀態改回工作中。
        # 權限提示不擋：那可能就是這個 subagent 自己要的權限，核准後它的 PostToolUse 要能把狀態放回來
        sub_waiting = (bool(payload.get("agent_id")) and prev == WAITING
                       and ((rec.get("pending") or {}).get("kind") == "ask" or (rec.get("pending") or {}).get("plan")))

        if sub_waiting and event in ("PreToolUse", "PostToolUse"):
            pass
        elif event == "SessionStart":
            _set(rec, IDLE)
        elif event == "UserPromptSubmit":
            _set(rec, WORKING, activity="")
        elif event == "PreToolUse":
            if tool == "AskUserQuestion":
                qs = (payload.get("tool_input") or {}).get("questions") or []
                _set(rec, WAITING, pending={"kind": "ask", "questions": qs})
            elif tool == "ExitPlanMode":
                # 計畫模式交計畫：一定要你核准才會往下
                _set(rec, WAITING, pending={"kind": "permission", "plan": True, "message": "計畫寫好了，等你核准"})
            else:
                _set(rec, WORKING, activity=f"{tool}：{transcript.tool_summary(tool, payload.get('tool_input'))}")
        elif event == "PostToolUse":
            _set(rec, WORKING)
        elif event == "Notification":
            msg = payload.get("message", "")
            kind = payload.get("notification_type", "")
            # 只有真的在等你決定的通知才算（權限、MCP 要你填的表單）；auth_success 這類不算
            asks = kind in ("permission_prompt", "elicitation_dialog") or (not kind and "permission" in msg.lower())
            if not asks:
                pass
            elif rec.get("status") != WAITING or (rec.get("pending") or {}).get("kind") != "ask":
                _set(rec, WAITING, pending={"kind": "permission", "message": msg})
        elif event == "Stop":
            _set(rec, DONE)
            # 先記下來：沒人打開手機列表時，背景結束也要有人看到
            # ps 失敗（None）也先記：交給看門的去判斷，不然當下就推了「完工」
            if pid and _bg_labels(pid, fresh=True) != []:
                _track(tty, pid)
            elif prev != DONE:
                # 背景結束後被叫醒、這一輪做完沒有新背景：這次 Stop 自己就推完工，看門的不准再推一次
                # （完工→完工沒變的話 Stop 不推，留給看門的推）
                _untrack(tty)

        _save()
        new = rec.get("status")
    events.bump()
    if new != prev:
        # 每一次狀態變了都要通知：跳通知只在等你／做完，但紅點數字與鎖定畫面的狀態每一種變化都要跟
        notify.session_changed(tty)


def reload_state(records: dict) -> None:
    """整份換掉 hook 狀態（假資料模式重來時用）。"""
    global _scan_cache
    with _lock:
        _state["sessions"] = records
        _scan_cache = (0.0, [])
        _save()
    events.bump()


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


# ---------------------------------------------------------------- 背景任務

_bg: dict[str, int] = {}          # tty → pid：上次看到有背景任務的 session，等它們結束
_bg_since: dict[str, float] = {}  # tty → 什麼時候記下來的：比這次 ps 還新的不准拿這次 ps 判結束
_bg_gone: dict[str, float] = {}   # tty → 第一次看到背景都沒了的時間：再等一輪才算完工
_kids_cache: tuple[float, dict] = (0.0, {})
_WATCH_EVERY = 10
_watching = False


def _bg_labels(pid: int, fresh: bool = False) -> list[str] | None:
    """None＝這次 ps 失敗、手上也沒有舊的可用。"""
    global _kids_cache
    if fresh or time.time() - _kids_cache[0] >= _SCAN_TTL:
        kids = procs.background_shells()
        if kids is None:
            return None if fresh else background.labels(_kids_cache[1].get(pid, []))   # 失敗就沿用舊的
        _kids_cache = (time.time(), kids)
    return background.labels(_kids_cache[1].get(pid, []))


def _track(tty: str, pid: int) -> None:
    """記下這個 session 有背景在跑（呼叫的人要拿著 _lock）。"""
    _bg[tty] = pid
    _bg_since[tty] = time.time()
    _bg_gone.pop(tty, None)
    _ensure_watch()


def _untrack(tty: str) -> None:
    _bg.pop(tty, None)
    _bg_since.pop(tty, None)
    _bg_gone.pop(tty, None)


def effective_status(status: str, bg: list[str]) -> str:
    """回合結束（完工、待命）但還有背景在跑＝背景跑；等你回答、工作中照舊。"""
    return BACKGROUND if bg and status in (DONE, IDLE) else status


def check_background() -> None:
    """看記下來的那幾個 session 背景結束了沒；結束而且還停著（完工）就改完工時間、通知（跳推播）。

    背景結束後 Claude Code 會把模型叫醒接著做，所以第一次看到沒了先不算，下一輪還停在完工才推：
    不然先推一則「完工」、模型又做完一輪再推一則。
    """
    if not _bg:
        return
    t0 = time.time()
    kids = procs.background_shells()
    if kids is None:
        return   # ps 失敗不等於背景結束，下一輪再看
    global _kids_cache
    finished, ended = [], False
    with _lock:
        # 快取換成這次的新資料要在鎖裡：不然列表拿舊快取又把剛移掉的記回去，同一件推兩次
        if t0 > _kids_cache[0]:
            _kids_cache = (t0, kids)
        for tty, pid in list(_bg.items()):
            if _bg_since.get(tty, 0) >= t0:
                continue   # ps 之後才記的（Stop 剛好插進來）：這份快照看不到它的背景
            if background.labels(kids.get(pid, [])):
                _bg_gone.pop(tty, None)
                continue
            gone = _bg_gone.setdefault(tty, t0)
            if gone == t0:
                continue   # 第一次看到沒了：等下一輪
            _untrack(tty)
            ended = True
            rec = _state["sessions"].get(tty)
            if rec and rec.get("pid") == pid and rec.get("status") == DONE:
                rec["status_since"] = datetime.fromtimestamp(gone, timezone.utc).isoformat()
                finished.append(tty)
        if finished:
            _save()
    if ended:
        # 列表要跟著變（待命的背景結束也是）；停在完工的通知 notify 跳推播（順便更新鎖定畫面）
        events.bump()
        if not finished:
            notify.summary_changed()
    for tty in finished:
        notify.session_changed(tty)


def _ensure_watch() -> None:
    global _watching
    if _watching:
        return
    _watching = True

    def loop():
        while True:
            time.sleep(_WATCH_EVERY)
            try:
                check_background()
            except Exception as e:   # 看門的不能自己死掉
                import logging
                logging.getLogger("sessions").warning("查背景任務失敗：%s", e)

    threading.Thread(target=loop, daemon=True).start()


def _view(s: iterm.ItermSession, proc: procs.ClaudeProc, with_messages: bool = False) -> dict:
    rec = _record_for(proc)
    path = _transcript_path(rec, proc)
    built = transcript.build(transcripts.read(path)) if path else {"title": None, "messages": []}
    cwd = rec.get("cwd") or proc.cwd
    # 還沒有標題時用資料夾名：iTerm2 分頁名在這之前是 shell 的指令（例如「cd (claude)」），沒有意義
    name = built["title"] or os.path.basename(cwd.rstrip("/")) or s.name.strip()
    status, pending = rec.get("status", UNKNOWN), rec.get("pending")
    # 工作中不算：前景指令也是子程序，數字不準
    bg = [] if status == WORKING else (_bg_labels(proc.pid) or [])
    if bg and status in (DONE, IDLE) and proc.tty not in _bg:
        _track(proc.tty, proc.pid)
    status = effective_status(status, bg)
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
        "background": bg,
        "last_text": transcript.last_text(built["messages"])[:300],
        "session_id": rec.get("session_id"),
        "context_pct": contexts.pct(rec.get("session_id")),
        "starred": s.id in store.load("stars"),
    }
    if with_messages:
        view["messages"] = built["messages"]
        view["awaiting_tool"] = transcript.awaiting(built)
    return view


_ORDER = {WAITING: 0, DONE: 1, WORKING: 2, BACKGROUND: 3, IDLE: 4, UNKNOWN: 5}


def list_views() -> list[dict]:
    with _lock:
        pairs = _scan()
        views = [_view(s, p) for s, p in pairs]
        _prune_stars({s.id for s, _ in pairs})
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


def _entries(session_id: str) -> list[dict] | None:
    hit = find(session_id)
    if not hit:
        return None
    path = _transcript_path(_record_for(hit[1]), hit[1])
    return transcripts.read(path) if path else []


def tool_detail(session_id: str, message_id: str) -> dict | None:
    entries = _entries(session_id)
    return None if entries is None else transcript.tool_detail(entries, message_id)


def search(session_id: str, q: str) -> list[dict] | None:
    entries = _entries(session_id)
    return None if entries is None else transcript.search(transcript.build(entries)["messages"], q)


def recent_dirs() -> list[str]:
    """開新 session 時排在最前面的資料夾：現在開著的 session 的資料夾＋最近從手機開過的，新的在前。"""
    seen: dict[str, str] = dict(store.load("recent_dirs"))
    for v in list_views():
        seen.setdefault(v["cwd"], "")
    # 有時間戳的（手機開過的）照時間新到舊，其他照列表順序接在後面
    return sorted(seen, key=lambda d: seen[d], reverse=True)


def remember_dir(directory: str) -> None:
    with _lock:
        data = store.load("recent_dirs")
        data[directory] = _now()
        # 只留最近 20 個
        keep = sorted(data.items(), key=lambda kv: kv[1], reverse=True)[:20]
        store.save("recent_dirs", dict(keep))


# ---------------------------------------------------------------- 星號


def set_star(session_id: str, starred: bool) -> None:
    """星號跟著 iTerm2 分頁走（使用者裁示）：分頁關了星號就跟著消失。"""
    with _lock:
        stars = store.load("stars")
        if starred:
            stars[session_id] = _now()
        else:
            stars.pop(session_id, None)
        store.save("stars", stars)
    events.bump()


def replace_stars(session_ids: list[str]) -> None:
    """整份換掉星號（假資料模式重來時用）。"""
    with _lock:
        store.save("stars", {k: _now() for k in session_ids})
    events.bump()


def is_starred(session_id: str) -> bool:
    return session_id in store.load("stars")


def _prune_stars(alive: set[str]) -> None:
    stars = store.load("stars")
    gone = [k for k in stars if k not in alive]
    if gone and alive:   # 掃不到任何分頁（iTerm2 卡住）時不要把星號全清掉
        for k in gone:
            stars.pop(k)
        store.save("stars", stars)


def waiting_count() -> int:
    return sum(1 for v in list_views() if v["status"] == WAITING)


def summary() -> dict:
    """鎖定畫面與動態島要顯示的：幾個在工作、幾個等你、等你的第一個在問什麼。"""
    views = list_views()
    waiting = [v for v in views if v["status"] == WAITING]
    working = [v for v in views if v["status"] == WORKING]
    bg = [v for v in views if v["status"] == BACKGROUND]
    if waiting:
        top = waiting[0]
        pending = top.get("pending") or {}
        qs = pending.get("questions") or []
        ask = qs[0].get("question") if pending.get("kind") == "ask" and qs else None
        headline = f"{top['name'].split('｜')[0]}：{ask or pending.get('message') or '等你回答'}"
    elif working:
        top = working[0]
        headline = f"{top['name'].split('｜')[0]}：{top.get('activity') or '工作中'}"
    elif bg:
        top = bg[0]
        headline = f"{top['name'].split('｜')[0]}：背景 {top['background'][0]}"
    else:
        headline = "都完工了"
    return {"working": len(working), "waiting": len(waiting), "background": len(bg),
            "done": sum(1 for v in views if v["status"] == DONE), "headline": headline[:120]}


def view_by_tty(tty: str) -> dict | None:
    for s, p in _scan():
        if p.tty == tty:
            with _lock:
                return _view(s, p)
    return None

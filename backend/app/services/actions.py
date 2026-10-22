"""手機送過來的動作：回覆、選選項、按鍵、中斷、開新 session。

送字的節奏是實測出來的（2026-10-16）：文字與 Enter 要分兩次送、中間隔一下，
一起送的話 Claude Code 會把 Enter 當成貼上內容的一部分，變成換行而不是送出。
"""

import os
import shlex
import signal
import time

from .. import config
from ..repositories import accounts as accounts_repo
from ..repositories import iterm, procs, projects, uploads
from . import sessions, screen

GAP = 0.35

KEYS = {
    "up": ("seq", "[A"), "down": ("seq", "[B"), "right": ("seq", "[C"), "left": ("seq", "[D"),
    "shift_tab": ("seq", "[Z"),
    "enter": ("ascii", 13), "esc": ("ascii", 27), "tab": ("ascii", 9), "backspace": ("ascii", 127),
}


class NotFound(Exception):
    pass


class BadRequest(Exception):
    pass


def _require(session_id: str):
    hit = sessions.find(session_id)
    if not hit:
        raise NotFound(session_id)
    return hit


def press(session_id: str, key: str, label: str | None = None) -> None:
    """label：手機按下去時那顆按鈕的字。給了就先核對畫面上同一個 key 還是不是它，
    免得手機顯示的是上一題（還沒更新）、數字卻送進下一題。"""
    _require(session_id)
    if label is not None and (key.isdigit() or key.startswith("pick:")):
        prompt = screen.parse_prompt(iterm.contents(session_id))
        now = next((o["label"] for o in (prompt or {}).get("options", []) if o["key"] == key), None)
        if now != label:
            raise BadRequest("畫面已經換了，重新整理再選一次")
    if key.isdigit() and len(key) <= 2:
        iterm.write(session_id, key)
        return
    if key.startswith("pick:"):
        _pick(session_id, key)
        return
    if key == "submit":
        _submit(session_id)
        return
    if key not in KEYS:
        raise BadRequest(f"不認得的按鍵：{key}")
    kind, val = KEYS[key]
    if kind == "seq":
        iterm.write_seq(session_id, val)
    else:
        iterm.write_ascii(session_id, val)


def _pick(session_id: str, key: str) -> None:
    """沒編號的清單：從目前選中的那項用方向鍵移到目標，再按 Enter。"""
    prompt = screen.parse_prompt(iterm.contents(session_id))
    if not prompt or not prompt.get("selected", "").startswith("pick:"):
        raise BadRequest("畫面上已經沒有這個選單了")
    keys = [o["key"] for o in prompt["options"]]
    if key not in keys:
        raise BadRequest("沒有這個選項")
    diff = keys.index(key) - keys.index(prompt["selected"])
    for _ in range(abs(diff)):
        iterm.write_seq(session_id, "[B" if diff > 0 else "[A")
        time.sleep(0.1)
    time.sleep(GAP)
    iterm.write_ascii(session_id, 13)


def _row(prompt: dict, key: str) -> int:
    """複選題某一項在第幾行（0 起算）。Submit／Next 那行沒有編號、緊接在 submit_after 後面，
    所以它後面的選項（Chat about this）實際上還要再往下一行。key 給 "submit" 就是 Submit 那行。"""
    keys = [o["key"] for o in prompt["options"]]
    after = keys.index(prompt["submit_after"])
    if key == "submit":
        return after + 1
    i = keys.index(key)
    return i + 1 if i > after else i


def _cursor(prompt: dict) -> int:
    sel = prompt.get("selected")
    return _row(prompt, sel) if sel == "submit" or sel in [o["key"] for o in prompt["options"]] else 0


def submit_moves(prompt: dict) -> int:
    """複選題從目前游標到 Submit 要按幾次方向鍵：正的往下、負的往上（游標在 Chat about this 時）。"""
    return _row(prompt, "submit") - _cursor(prompt)


def _move(session_id: str, n: int) -> None:
    for _ in range(abs(n)):
        iterm.write_seq(session_id, "[B" if n > 0 else "[A")
        time.sleep(0.1)


def _submit(session_id: str) -> None:
    prompt = screen.parse_prompt(iterm.contents(session_id))
    if not prompt or not prompt.get("submit_key"):
        raise BadRequest("畫面上沒有可以送出的複選題")
    _move(session_id, submit_moves(prompt))
    time.sleep(GAP)
    iterm.write_ascii(session_id, 13)


def reply(session_id: str, text: str) -> None:
    """打字送出。如果畫面上正開著選項題，先選「Type something」那一項再打字。"""
    _require(session_id)
    # 換行照留：文字一口氣送進去會被當成貼上，裡面的換行就是換行；送出靠後面另外按的 Enter（2026-10-21 實測）
    text = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        raise BadRequest("空白訊息")
    try:
        prompt = screen.parse_prompt(iterm.contents(session_id))
    except iterm.ItermError:
        prompt = None
    if prompt and not prompt.get("type_key"):
        # 選單開著時打的字會被吃掉，最後那個 Enter 卻會按下游標所在的那一項（權限提示就是「Yes」）
        raise BadRequest("畫面上正開著選單，先按上面的選項")
    if prompt and prompt.get("submit_key"):
        # 複選題：數字鍵只會勾、游標不動，要用方向鍵移到 Type something 那一行才打得進去；
        # 打字就會自動勾起來，不按 Enter（Enter 會把它取消勾選），送出用「送出選擇」（2026-10-22 實測）
        _move(session_id, _row(prompt, prompt["type_key"]) - _cursor(prompt))
        time.sleep(GAP)
        # 那一行已經打過字（標籤不是 Type something 了）：先刪掉，這次打的字取代它
        label = next(o["label"] for o in prompt["options"] if o["key"] == prompt["type_key"])
        if not label.startswith(screen.TYPE_SOMETHING):
            for _ in label:
                iterm.write_ascii(session_id, 127)
        iterm.write(session_id, text)
        return
    if prompt:
        iterm.write(session_id, prompt["type_key"])
        time.sleep(GAP)
    iterm.write(session_id, text)
    time.sleep(GAP)
    iterm.write_ascii(session_id, 13)


def close(session_id: str) -> None:
    """結束這個 Claude 並關掉分頁：Ctrl-C 兩下讓它自己收尾；3 秒還在就送 SIGTERM，最後關分頁。"""
    _, proc = _require(session_id)
    for _ in range(2):
        iterm.write_ascii(session_id, 3)
        time.sleep(0.6)
    deadline = time.time() + 3
    while procs.alive(proc.pid) and time.time() < deadline:
        time.sleep(0.2)
    if procs.alive(proc.pid):
        os.kill(proc.pid, signal.SIGTERM)
        time.sleep(0.8)
    iterm.close(session_id)
    sessions.forget(proc.tty)


MAX_UPLOAD = 15 * 1024 * 1024


def upload(session_id: str, data: bytes, ext: str) -> str:
    _require(session_id)
    ext = ext.lower().lstrip(".")
    if ext not in uploads.EXTS:
        raise BadRequest(f"不收這種檔案：{ext}")
    if not data or len(data) > MAX_UPLOAD:
        raise BadRequest("檔案是空的或超過 15 MB")
    return str(uploads.save(data, ext))


def interrupt(session_id: str) -> None:
    _, proc = _require(session_id)
    iterm.write_ascii(session_id, 27)
    # 被 Esc 打斷時 Claude Code 不會觸發 Stop hook，狀態要自己改
    sessions.mark_idle(proc.tty)


def new_session(directory: str, account_id: str, prompt: str = "") -> str:
    root = os.path.realpath(config.PROJECTS_ROOT)
    target = os.path.realpath(directory)
    if not (target == root or target.startswith(root + os.sep)) or not os.path.isdir(target):
        raise BadRequest("只能開在 ~/Projects 底下的資料夾")
    acct = next((a for a in accounts_repo.load() if a.get("id") == account_id), None)
    if not acct:
        raise BadRequest(f"沒有這個帳號：{account_id}")
    cfg = accounts_repo.norm_dir(acct.get("config_dir", ""))
    # 預設帳號也要明講（env -u）：iTerm2 若是從某個帶著 CLAUDE_CONFIG_DIR 的程序啟動的，
    # 新分頁的 shell 會繼承它，什麼都不寫就會開成另一個帳號（2026-10-16 實測踩到）
    if cfg == accounts_repo.norm_dir(""):
        run = "env -u CLAUDE_CONFIG_DIR claude"
    else:
        run = f"CLAUDE_CONFIG_DIR={shlex.quote(cfg)} claude"
    prompt = prompt.strip()
    if prompt:
        # 第一句話當成 claude 的參數：開起來就直接開工（互動模式，之後照常能接著聊）
        # 前面加 --：第一句話以「-」開頭時才不會被當成 claude 的參數
        run += " -- " + shlex.quote(prompt)
    sid = iterm.new_tab(f"cd {shlex.quote(target)} && {run}")
    sessions.remember_dir(target)
    return sid


def project_dirs() -> list[str]:
    return projects.list_dirs()


def recent_dirs() -> list[str]:
    root = os.path.realpath(config.PROJECTS_ROOT)
    return [d for d in sessions.recent_dirs() if d.startswith(root + os.sep) and os.path.isdir(d)][:6]


def account_list() -> list[dict]:
    return [{"id": a.get("id"), "label": a.get("label") or a.get("id")} for a in accounts_repo.load()]

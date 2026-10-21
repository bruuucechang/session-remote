"""手機送過來的動作：回覆、選選項、按鍵、中斷、開新 session。

送字的節奏是實測出來的（2026-10-16）：文字與 Enter 要分兩次送、中間隔一下，
一起送的話 Claude Code 會把 Enter 當成貼上內容的一部分，變成換行而不是送出。
"""

import os
import shlex
import time

from .. import config
from ..repositories import accounts as accounts_repo
from ..repositories import iterm, projects
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


def press(session_id: str, key: str) -> None:
    _require(session_id)
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


def submit_moves(prompt: dict) -> int:
    """複選題從目前游標往下按幾次才到 Submit（Submit 緊接在 submit_after 那一項後面）。"""
    if prompt.get("selected") == "submit":
        return 0
    keys = [o["key"] for o in prompt["options"]]
    cur = keys.index(prompt["selected"]) if prompt.get("selected") in keys else 0
    return keys.index(prompt["submit_after"]) + 1 - cur


def _submit(session_id: str) -> None:
    prompt = screen.parse_prompt(iterm.contents(session_id))
    if not prompt or not prompt.get("submit_key"):
        raise BadRequest("畫面上沒有可以送出的複選題")
    for _ in range(max(0, submit_moves(prompt))):
        iterm.write_seq(session_id, "[B")
        time.sleep(0.1)
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
    if prompt and prompt.get("type_key"):
        iterm.write(session_id, prompt["type_key"])
        time.sleep(GAP)
    iterm.write(session_id, text)
    time.sleep(GAP)
    iterm.write_ascii(session_id, 13)


def interrupt(session_id: str) -> None:
    _, proc = _require(session_id)
    iterm.write_ascii(session_id, 27)
    # 被 Esc 打斷時 Claude Code 不會觸發 Stop hook，狀態要自己改
    sessions.mark_idle(proc.tty)


def new_session(directory: str, account_id: str) -> str:
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
    return iterm.new_tab(f"cd {shlex.quote(target)} && {run}")


def project_dirs() -> list[str]:
    return projects.list_dirs()


def account_list() -> list[dict]:
    return [{"id": a.get("id"), "label": a.get("label") or a.get("id")} for a in accounts_repo.load()]

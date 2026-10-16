"""hook → 狀態。不碰 iTerm2、不寫真的狀態檔、不推播。"""

import pytest

from app.services import notify, sessions


@pytest.fixture(autouse=True)
def isolate(monkeypatch):
    monkeypatch.setattr(sessions, "_state", {"sessions": {}})
    monkeypatch.setattr(sessions, "_save", lambda: None)
    pushed = []
    monkeypatch.setattr(notify, "session_changed", lambda tty: pushed.append(tty))
    return pushed


def hook(event, **payload):
    sessions.apply_hook(event, "/dev/ttys009", 123, "", {"session_id": "s1", **payload})


def status():
    return sessions._state["sessions"]["/dev/ttys009"]["status"]


def test_full_cycle_and_pushes(isolate):
    hook("SessionStart")
    assert status() == "idle"
    hook("UserPromptSubmit")
    assert status() == "working"
    hook("PreToolUse", tool_name="AskUserQuestion", tool_input={"questions": [{"question": "要哪個？"}]})
    assert status() == "waiting"
    assert sessions._state["sessions"]["/dev/ttys009"]["pending"]["kind"] == "ask"
    # 選項題期間跳的 Notification 不能把題目蓋成權限提示
    hook("Notification", message="Claude needs your input")
    assert sessions._state["sessions"]["/dev/ttys009"]["pending"]["kind"] == "ask"
    hook("PostToolUse", tool_name="AskUserQuestion")
    assert status() == "working"
    hook("Notification", message="Claude needs your permission to use Bash", notification_type="permission_prompt")
    assert status() == "waiting"
    hook("Stop")
    assert status() == "done"
    hook("Notification", message="Claude is waiting for your input", notification_type="idle_prompt")
    assert status() == "done"
    # 推播只在進入 waiting / done 的那一刻
    assert len(isolate) == 3


def test_new_claude_on_same_tty_resets():
    hook("UserPromptSubmit")
    sessions.apply_hook("SessionStart", "/dev/ttys009", 456, "", {"session_id": "s2"})
    rec = sessions._state["sessions"]["/dev/ttys009"]
    assert rec["pid"] == 456 and rec["status"] == "idle"


def test_session_end_removes():
    hook("SessionStart")
    hook("SessionEnd")
    assert "/dev/ttys009" not in sessions._state["sessions"]

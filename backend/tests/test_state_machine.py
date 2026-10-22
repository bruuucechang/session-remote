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
    # 每一次狀態變了都通知 notify（紅點與鎖定畫面要跟）；跳不跳通知由 notify 自己看是不是 waiting／done。
    # 同一個狀態重複回報（done 之後的 idle_prompt）不算變化
    assert len(isolate) == 5


def test_new_claude_on_same_tty_resets():
    hook("UserPromptSubmit")
    sessions.apply_hook("SessionStart", "/dev/ttys009", 456, "", {"session_id": "s2"})
    rec = sessions._state["sessions"]["/dev/ttys009"]
    assert rec["pid"] == 456 and rec["status"] == "idle"


def test_session_end_removes():
    hook("SessionStart")
    hook("SessionEnd")
    assert "/dev/ttys009" not in sessions._state["sessions"]


def test_page_after_before_and_reset():
    from app.services.sessions import page
    ms = [{"id": str(i)} for i in range(10)]
    p = page(ms, 3)
    assert [m["id"] for m in p["messages"]] == ["7", "8", "9"] and p["reset"] and p["has_more"]
    p = page(ms, 3, after="7")
    assert [m["id"] for m in p["messages"]] == ["8", "9"] and not p["reset"]
    p = page(ms, 3, after="9")
    assert p["messages"] == [] and not p["reset"]
    p = page(ms, 3, after="不見了")          # /clear 換了紀錄檔：整串換掉
    assert p["reset"] and [m["id"] for m in p["messages"]] == ["7", "8", "9"]
    p = page(ms, 3, before="7")
    assert [m["id"] for m in p["messages"]] == ["4", "5", "6"] and p["has_more"]
    p = page(ms, 3, before="2")
    assert [m["id"] for m in p["messages"]] == ["0", "1"] and not p["has_more"]


def rec():
    return sessions._state["sessions"].get("/dev/ttys009")


def test_session_end_of_other_session_keeps_record():
    # /clear：新的 SessionStart 先到、舊的 SessionEnd 後到，不能把新的刪掉
    hook("SessionStart")
    sessions.apply_hook("SessionEnd", "/dev/ttys009", 123, "", {"session_id": "old"})
    assert rec() is not None


def test_subagent_tool_events_do_not_clear_question():
    hook("PreToolUse", tool_name="AskUserQuestion", tool_input={"questions": [{"question": "要哪個？"}]})
    hook("PreToolUse", tool_name="Read", agent_id="sub1")
    hook("PostToolUse", tool_name="Read", agent_id="sub1")
    assert status() == "waiting" and rec()["pending"]["kind"] == "ask"
    hook("PostToolUse", tool_name="AskUserQuestion")
    assert status() == "working"


def test_subagent_permission_is_released_by_its_own_post_tool_use():
    hook("UserPromptSubmit")
    hook("Notification", message="Claude needs your permission to use Bash", notification_type="permission_prompt")
    hook("PostToolUse", tool_name="Bash", agent_id="sub1")
    assert status() == "working"


def test_unrelated_notification_is_not_waiting():
    hook("Stop")
    hook("Notification", message="Authentication successful", notification_type="auth_success")
    assert status() == "done"


def test_plan_approval_is_waiting():
    hook("UserPromptSubmit")
    hook("PreToolUse", tool_name="ExitPlanMode", tool_input={"plan": "x"})
    assert status() == "waiting"

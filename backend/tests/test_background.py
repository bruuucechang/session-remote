"""背景任務：判定、顯示的字、背景結束才推完工。不碰真的程序與 iTerm2。"""

import os
import time

import pytest

from app.services import background, notify, sessions

PRE = ("/bin/zsh -c source /Users/x/.claude/shell-snapshots/snapshot-zsh-1-abc.sh 2>/dev/null || true "
       "&& setopt NO_EXTENDED_GLOB 2>/dev/null || true && eval ")
POST = " < /dev/null && pwd -P >| /tmp/claude-8ddd-cwd"


def shell(body: str) -> str:
    return PRE + "'" + body + "'" + POST


def test_label_waitfor():
    cmd = shell('S=/tmp/s; ~/.claude/tools/waitfor --label next-champ --every 600 --fail "! curl -sf x" -- $S/next.sh')
    assert background.label(cmd) == "waitfor next-champ"


def test_label_skips_setup_lines():
    cmd = shell("S=/tmp/s\\012cd /Users/x/Projects/a\\012./run.sh sim boss-full 20 > $S/out.log")
    assert background.label(cmd) == "./run.sh sim boss-full 20 > $S/out.log"


def test_label_shortens_home_and_long_commands():
    home = os.path.expanduser("~")
    cmd = shell(f"python3 {home}/Projects/a/train.py " + "--x 1 " * 30)
    out = background.label(cmd)
    assert out.startswith("python3 ~/Projects/a/train.py") and len(out) == 80 and out.endswith("…")


def test_labels_ignore_non_tool_children():
    assert background.labels(["caffeinate -i -t 300", shell("sleep 100")]) == ["sleep 100"]


@pytest.mark.parametrize("status,bg,want", [
    ("done", ["x"], "background"),
    ("idle", ["x"], "background"),
    ("done", [], "done"),
    ("waiting", ["x"], "waiting"),   # 等你回答照舊，列上另外標背景數
    ("working", ["x"], "working"),
])
def test_effective_status(status, bg, want):
    assert sessions.effective_status(status, bg) == want


def test_should_alert_background_is_silent():
    assert not notify.should_alert({"status": "background", "starred": True}, {"star_only_push": False})


@pytest.fixture
def tracked(monkeypatch):
    monkeypatch.setattr(sessions, "_state", {"sessions": {
        "/dev/ttys009": {"tty": "/dev/ttys009", "pid": 123, "status": "done", "status_since": "2026-01-01T00:00:00+00:00"}}})
    monkeypatch.setattr(sessions, "_save", lambda: None)
    monkeypatch.setattr(sessions, "_bg", {"/dev/ttys009": 123})
    monkeypatch.setattr(sessions, "_bg_since", {})
    monkeypatch.setattr(sessions, "_bg_gone", {})
    pushed = []
    monkeypatch.setattr(notify, "session_changed", lambda tty: pushed.append(tty))
    return pushed


def test_background_still_running_no_push(tracked, monkeypatch):
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {123: [shell("sleep 100")]})
    sessions.check_background()
    assert tracked == [] and sessions._bg == {"/dev/ttys009": 123}


def test_background_finished_pushes_done(tracked, monkeypatch):
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    sessions.check_background()
    assert tracked == [], "第一次看到背景沒了就推：模型可能馬上被叫醒接著做"
    sessions.check_background()
    rec = sessions._state["sessions"]["/dev/ttys009"]
    assert tracked == ["/dev/ttys009"] and sessions._bg == {}
    assert rec["status"] == "done" and rec["status_since"] > "2026-01-01T00:00:00+00:00"   # 完工時間＝背景結束的時間


def test_background_finished_after_new_turn_no_push(tracked, monkeypatch):
    # 背景結束時使用者已經又開了一輪：不是完工，不推
    sessions._state["sessions"]["/dev/ttys009"]["status"] = "working"
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    sessions.check_background()
    sessions.check_background()
    assert tracked == [] and sessions._bg == {}


def test_activity_counts_background_as_active():
    sm = {"working": 0, "waiting": 0, "background": 1, "done": 2, "headline": "x"}
    p, _ = notify.activity_payload(sm, None, 1000.0, start=False)
    assert p["aps"]["event"] == "update" and p["aps"]["content-state"]["background"] == 1


def test_idle_background_finished_updates_summary(tracked, monkeypatch):
    # 待命的背景結束：不推完工，但鎖定畫面的「背景 1」要跟著消失
    sessions._state["sessions"]["/dev/ttys009"]["status"] = "idle"
    calls = []
    monkeypatch.setattr(notify, "summary_changed", lambda force=False: calls.append(1))
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    sessions.check_background()
    sessions.check_background()
    assert tracked == [] and calls == [1]


def test_ps_failure_is_not_finished(tracked, monkeypatch):
    # ps 失敗（逾時）跟「背景都結束了」要分得出來，不然推一則假的完工
    monkeypatch.setattr(sessions.procs, "_run", lambda args: "")
    sessions.check_background()
    assert tracked == [] and sessions._bg == {"/dev/ttys009": 123}


def test_background_end_wakes_model_single_push(tracked, monkeypatch):
    # 背景結束 → Claude Code 叫醒模型接著做（工作中）→ 做完 Stop 自己推完工；看門的不准先推一則
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    sessions.check_background()
    sessions._state["sessions"]["/dev/ttys009"]["status"] = "working"
    sessions.check_background()
    assert tracked == [] and sessions._bg == {}


def test_background_back_resets_grace(tracked, monkeypatch):
    # 第一次沒看到、下一輪又有了（例如接著開了新的背景）：不算結束
    kids = {}
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: kids)
    sessions.check_background()
    kids[123] = [shell("sleep 100")]
    sessions.check_background()
    kids.clear()
    sessions.check_background()
    assert tracked == [] and sessions._bg == {"/dev/ttys009": 123}


def test_stop_during_ps_not_dropped(tracked, monkeypatch):
    # ps 跑的同時 Stop 剛記下新的背景：拿舊快照不准判它結束
    def ps():
        sessions._bg_since["/dev/ttys009"] = time.time()
        return {}
    monkeypatch.setattr(sessions.procs, "background_shells", ps)
    sessions.check_background()
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {123: [shell("sleep 100")]})
    sessions.check_background()
    assert tracked == [] and sessions._bg == {"/dev/ttys009": 123} and sessions._bg_gone == {}


def test_woken_turn_finishes_within_grace_single_push(tracked, monkeypatch):
    # 看門的第一輪看到沒了 → 模型醒來（工作中）→ 10 秒內做完 Stop（自己推完工）→ 看門的第二輪不准再推
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    monkeypatch.setattr(sessions, "_ensure_watch", lambda: None)
    sessions.check_background()
    rec = sessions._state["sessions"]["/dev/ttys009"]
    rec["status"] = "working"
    sessions.apply_hook("Stop", "/dev/ttys009", 123, "", {})
    assert tracked == ["/dev/ttys009"]
    sessions.check_background()
    assert tracked == ["/dev/ttys009"] and sessions._bg == {}


def test_woken_turn_done_to_done_watcher_pushes(tracked, monkeypatch):
    # 醒來那一輪沒經過工作中（完工→完工，Stop 不推）：留給看門的推一次
    monkeypatch.setattr(sessions.procs, "background_shells", lambda: {})
    monkeypatch.setattr(sessions, "_ensure_watch", lambda: None)
    sessions.check_background()
    sessions.apply_hook("Stop", "/dev/ttys009", 123, "", {})
    assert tracked == []
    sessions.check_background()
    assert tracked == ["/dev/ttys009"]

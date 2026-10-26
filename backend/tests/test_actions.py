"""手機送來的動作換算成哪些按鍵。iTerm2 換成假的，只記下送了什麼。"""

import pytest

from app.services import actions, sessions
from tests.test_screen import ASK, MULTI, PERMISSION, REVIEW, _scr


@pytest.fixture
def term(monkeypatch):
    sent = []
    screen_text = {"v": ""}
    monkeypatch.setattr(actions, "_require", lambda sid: None)
    monkeypatch.setattr(actions.time, "sleep", lambda s: None)
    monkeypatch.setattr(actions.iterm, "contents", lambda sid: screen_text["v"])
    monkeypatch.setattr(actions.iterm, "write", lambda sid, t: sent.append(("write", t)))
    monkeypatch.setattr(actions.iterm, "write_seq", lambda sid, s: sent.append(("seq", s)))
    monkeypatch.setattr(actions.iterm, "write_ascii", lambda sid, c: sent.append(("ascii", c)))

    def show(text):
        screen_text["v"] = text
        return sent
    return show


def test_reply_on_permission_prompt_picks_tell_claude_first(term):
    sent = term(PERMISSION)
    actions.reply("x", "不要刪，先備份")
    assert sent == [("write", "3"), ("write", "不要刪，先備份"), ("ascii", 13)]


def test_reply_refused_when_menu_has_no_type_option(term):
    term(REVIEW)
    with pytest.raises(actions.BadRequest):
        actions.reply("x", "隨便")


def test_reply_on_multiselect_moves_to_type_row_without_enter(term):
    # 游標在第 2 項，Type something 是第 3 項：往下 1 次、打字，不按 Enter（Enter 會取消勾選）
    sent = term(MULTI)
    actions.reply("x", "加辣椒")
    assert sent == [("seq", "[B"), ("write", "加辣椒")]


def test_submit_from_below_moves_up(term):
    # 游標在 Submit 底下的「Chat about this」：要往上 1 次，不是直接按 Enter
    sent = term(MULTI.replace("❯ 2.", "  2.").replace("  4. Chat", "❯ 4. Chat"))
    actions.press("x", "submit")
    assert sent == [("seq", "[A"), ("ascii", 13)]


def test_submit_next_in_multi_question(term):
    sent = term(_scr("multi_next"))
    actions.press("x", "submit")
    assert sent == [("seq", "[B")] * 4 + [("ascii", 13)]


def test_press_checks_label_against_screen(term):
    sent = term(ASK)
    actions.press("x", "2", label="綠")
    assert sent == [("write", "2")]
    with pytest.raises(actions.BadRequest):
        actions.press("x", "2", label="Submit answers")   # 手機還在顯示確認頁，畫面已經換到別的了


def test_new_session_prompt_after_double_dash(monkeypatch, tmp_path):
    cmds = []
    monkeypatch.setattr(actions.config, "PROJECTS_ROOT", str(tmp_path))
    monkeypatch.setattr(actions.accounts_repo, "load", lambda: [{"id": "a", "config_dir": "/x/.claude-b"}])
    monkeypatch.setattr(actions.iterm, "new_tab", lambda c: cmds.append(c) or "id")
    monkeypatch.setattr(sessions, "remember_dir", lambda d: None)
    actions.new_session(str(tmp_path), "a", "-p")
    assert cmds[0].endswith("claude -- -p")


def test_retype_on_multiselect_replaces_previous_text(term):
    # 第 3 行已經打過「加辣椒」、游標就在那一行：先刪 3 個字再打新的
    sent = term(_scr("multi_typed"))
    actions.reply("x", "加胡椒")
    assert sent == [("ascii", 127)] * 3 + [("write", "加胡椒")]


def test_osa_retries_invalid_index(monkeypatch):
    # 找分頁時別的分頁剛好開關：AppleScript 回 -1719，重試就好（2026-10-26 真機實測）
    import subprocess
    from app.repositories import iterm
    calls = []

    def fake(cmd, **kw):
        calls.append(cmd)
        if len(calls) == 1:
            return subprocess.CompletedProcess(cmd, 1, "", "execution error: Invalid index. (-1719)")
        return subprocess.CompletedProcess(cmd, 0, "ok\n", "")
    monkeypatch.setattr(iterm.subprocess, "run", fake)
    monkeypatch.setattr(iterm.time, "sleep", lambda s: None)
    assert iterm._osa("x") == "ok" and len(calls) == 2
    # 別的錯誤不重試
    calls.clear()
    monkeypatch.setattr(iterm.subprocess, "run", lambda cmd, **kw: (calls.append(cmd), subprocess.CompletedProcess(cmd, 1, "", "找不到"))[1])
    import pytest
    with pytest.raises(iterm.ItermError):
        iterm._osa("x")
    assert len(calls) == 1


def test_new_tab_never_retries(monkeypatch):
    # 開新分頁可能已經開好、送了指令才回 -1719：重試會多開一個 Claude
    import subprocess
    import pytest
    from app.repositories import iterm
    calls = []
    monkeypatch.setattr(iterm.subprocess, "run", lambda cmd, **kw: (calls.append(cmd), subprocess.CompletedProcess(cmd, 1, "", "Invalid index. (-1719)"))[1])
    monkeypatch.setattr(iterm.time, "sleep", lambda s: None)
    monkeypatch.setattr(iterm, "is_running", lambda: True)   # 不然會真的去開 iTerm2
    monkeypatch.setattr(iterm, "_frontmost", lambda: "")
    with pytest.raises(iterm.ItermError):
        iterm.new_tab("echo hi")
    assert len(calls) == 1

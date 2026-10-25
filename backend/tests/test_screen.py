"""畫面辨識：用實際從 iTerm2 讀回來的畫面文字（2026-10-16）。"""

from app.services import screen

ASK = """
❯ 測試用：請用 AskUserQuestion
────────────────────────────────
 ☐ 顏色
喜歡哪個顏色？
❯ 1. 紅
     選紅色
  2. 綠
     選綠色
  3. 藍
  4. Type something.
────────────────────────────────
  5. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
"""

TRUST = """
 Claude Code'll be able to read, edit, and execute files here.
 Security guide
 ❯ No, exit
   Yes, I trust this folder
 Enter to confirm · Esc to cancel
"""

IDLE = """
⏺ 好
✻ Crunched for 4s · done 6:49 PM
────────────────────────────────
  1. 這是對話裡的編號清單
  2. 不是選單
❯
────────────────────────────────
  peter@Air │ session-remote
"""


def test_numbered_options():
    p = screen.parse_prompt(ASK)
    assert [o["key"] for o in p["options"]] == ["1", "2", "3", "4", "5"]
    assert p["options"][0]["label"] == "紅"
    assert p["selected"] == "1"
    assert p["type_key"] == "4"


def test_unnumbered_menu_uses_pick_keys():
    p = screen.parse_prompt(TRUST)
    assert [o["label"] for o in p["options"]] == ["No, exit", "Yes, I trust this folder"]
    assert p["selected"] == "pick:1"


def test_numbered_list_in_conversation_is_not_a_prompt():
    assert screen.parse_prompt(IDLE) is None


MULTI = """
「官方功能遷移」要換掉哪幾樣自製機制？（可複選）
  1. [ ] 撞額度立刻換帳號 (Recommended)
         加官方的事件 hook
❯ 2. [✔] 跨 session 訊息取代打字
  3. [ ] Type something
     Submit
──────────────────────────────────────
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
"""


def test_multi_select_checkboxes_and_submit():
    p = screen.parse_prompt(MULTI)
    assert [o["label"] for o in p["options"]] == ["撞額度立刻換帳號 (Recommended)", "跨 session 訊息取代打字", "Type something", "Chat about this"]
    assert [o.get("checked") for o in p["options"]] == [False, True, False, None]
    assert p["selected"] == "2"
    assert p["type_key"] == "3"
    assert p["submit_key"] == "submit" and p["submit_after"] == "3"


def test_submit_moves_from_cursor():
    from app.services.actions import submit_moves
    p = screen.parse_prompt(MULTI)
    assert submit_moves(p) == 2            # 2 → 3 → Submit
    p2 = screen.parse_prompt(MULTI.replace("❯ 2.", "  2.").replace("     Submit", "❯    Submit"))
    assert p2["selected"] == "submit" and submit_moves(p2) == 0


def test_single_select_has_no_submit():
    assert "submit_key" not in screen.parse_prompt(ASK)


# 一次問兩題、兩題都答完之後的確認頁：沒有「Enter to select」頁尾（2026-10-22，v2.1.306）
REVIEW = """
❯ 請立刻用 AskUserQuestion 一次問我兩題
────────────────────────────────
←  ☒ 顏色  ☒ 大小  ✔ Submit  →
Review your answers
 ● 請選擇「顏色」：紅或綠？
   → 紅
 ● 請選擇「大小」：大或小？
   → 小
Ready to submit your answers?
❯ 1. Submit answers
  2. Cancel
"""


def test_review_page_is_a_prompt():
    p = screen.parse_prompt(REVIEW)
    assert p is not None
    assert [o["label"] for o in p["options"]] == ["Submit answers", "Cancel"]
    assert p["selected"] == "1"
    assert p["review"] == [
        {"question": "請選擇「顏色」：紅或綠？", "answer": "紅"},
        {"question": "請選擇「大小」：大或小？", "answer": "小"},
    ]


def test_review_only_on_review_page():
    assert "review" not in screen.parse_prompt(ASK)


def test_review_text_in_chat_is_not_a_prompt():
    idle = """
⏺ 確認頁長這樣：
  Ready to submit your answers?
  1. Submit answers
  2. Cancel
────────────────────────────────
❯
────────────────────────────────
  ? for shortcuts
"""
    assert screen.parse_prompt(idle) is None


def test_review_ignores_bullets_above_and_joins_wrapped_lines():
    above = "⏺ 我整理了兩個方向：\n  ● 方案甲：直接改\n  ● 方案乙：先查\n❯ 好，問我\n"
    assert len(screen.parse_prompt(above + REVIEW)["review"]) == 2
    wrapped = """
Review your answers
 ● Which color should the new
   button use?
   → a very long answer that
     wraps onto next line
Ready to submit your answers?
❯ 1. Submit answers
  2. Cancel
"""
    assert screen.parse_prompt(wrapped)["review"] == [
        {"question": "Which color should the new button use?", "answer": "a very long answer that wraps onto next line"}
    ]


# ---- 2026-10-22 用真的 claude（v2.1.307，60 欄寬的終端機）擷取的畫面，存在 tests/screens/

def _scr(name):
    from pathlib import Path
    return (Path(__file__).parent / "screens" / f"{name}.txt").read_text()


def test_multi_question_multiselect_uses_next():
    # 一次問好幾題時，複選題最後一行是 Next 不是 Submit：以前認不到，手機上沒有送出鈕
    p = screen.parse_prompt(_scr("multi_next"))
    assert p["submit_key"] == "submit" and p["submit_after"] == "4"
    assert [o.get("checked") for o in p["options"]][:3] == [True, False, True]
    p2 = screen.parse_prompt(_scr("multi_on_next"))
    assert p2["selected"] == "submit"


def test_review_page_with_session_title_line():
    # session 有了名稱以後，選項底下多一條「──── 雜項｜…」分隔線
    p = screen.parse_prompt(_scr("review_titled"))
    assert [o["label"] for o in p["options"]] == ["Submit answers", "Cancel"]
    assert [r["answer"] for r in p["review"]] == ["綠", "起司, 洋蔥", "大"]


def test_plan_approval_prompt():
    p = screen.parse_prompt(_scr("plan_approve"))
    assert [o["label"] for o in p["options"]] == [
        "Yes, and use auto mode", "Yes, manually approve edits", "Tell Claude what to change"]
    assert p["type_key"] == "3" and p["selected"] == "1"


def test_numbered_list_in_chat_followed_by_input_box_is_not_a_prompt():
    chat = """
⏺ 兩個做法：
  1. 直接改
  2. Other: 先查
  Do you want to go with 1 or 2?
────────────────────────────────
❯
────────────────────────────────
  peter@Air │ session-remote
"""
    assert screen.parse_prompt(chat) is None


def test_old_chat_list_above_real_prompt_is_dropped():
    p = screen.parse_prompt("⏺ 清單：\n  1. 甲\n  2. 乙\n  3. 丙\n❯ 好，問我\n" + ASK)
    assert [o["label"] for o in p["options"]][:3] == ["紅", "綠", "藍"]


PERMISSION = """
 Bash command
   rm -rf build
   Remove build directory
 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for rm commands in this project
   3. No, and tell Claude what to do differently (esc)
"""


def test_permission_prompt_has_type_key():
    p = screen.parse_prompt(PERMISSION)
    assert p["type_key"] == "3"


def test_other_must_match_exactly():
    p = screen.parse_prompt(ASK.replace("3. 藍", "3. Other people"))
    assert p["type_key"] == "4"


def test_plan_approval_with_more_options_and_title_line():
    text = _scr("plan_approve").replace(
        "     2. Yes, manually approve edits",
        "     2. Yes, manually approve edits\n     3. Yes, clear context\n     4. Yes, bypass").replace("3. Tell", "5. Tell")
    p = screen.parse_prompt(text + "\n──────── 雜項｜計畫 ─\n")
    assert p and p["type_key"] == "5"


def test_bash_mode_input_box_also_ends_chat_list():
    chat = "⏺ 兩個做法：\n  1. 直接改\n  2. 先查\n  Do you want to go with 1 or 2?\n────\n! \n────\n"
    assert screen.parse_prompt(chat) is None


# ---- UI 測試（ios/UITests/PromptTests）用的假畫面：手機上按的 key 要跟這裡對得上


def test_uitest_prompt_screens():
    ask = screen.parse_prompt(_scr("ask_single"))
    assert ask["options"][0]["label"] == "Fly.io (Recommended)" and ask["type_key"] == "4"
    multi = screen.parse_prompt(_scr("multi_submit"))
    assert [o.get("checked") for o in multi["options"]][:4] == [False, True, False, False]
    assert multi["selected"] == "2" and multi["submit_after"] == "4"
    perm = screen.parse_prompt(_scr("perm_bash"))
    assert [o["key"] for o in perm["options"]] == ["1", "2", "3"] and perm["type_key"] == "3"
    trust = screen.parse_prompt(_scr("trust_folder"))
    assert [o["label"] for o in trust["options"]] == ["No, exit", "Yes, I trust this folder"]
    assert trust["selected"] == "pick:1" and trust["type_key"] is None


def test_uitest_multi_submit_moves():
    # 游標在番茄（第 2 行）：往下 3 行才到 Submit
    from app.services.actions import submit_moves
    assert submit_moves(screen.parse_prompt(_scr("multi_submit"))) == 3


def test_permission_rule_prompt_v2_1_310():
    # 2026-10-26 互動 claude 實測：ask 規則跳的權限框只有 Yes／No、沒有可以打字的那一項
    p = screen.parse_prompt(_scr("perm_rule"))
    assert [o["label"] for o in p["options"]] == ["Yes", "No"]
    assert p["selected"] == "1" and p["type_key"] is None

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

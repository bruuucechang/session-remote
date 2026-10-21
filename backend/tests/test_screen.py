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

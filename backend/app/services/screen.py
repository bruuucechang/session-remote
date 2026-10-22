"""從 iTerm2 分頁的畫面文字認出「現在正在問你什麼、有哪些選項」。

選項題（AskUserQuestion）與權限提示在畫面上都長成編號清單：

    ❯ 1. 紅
         選紅色
      2. 綠
      4. Type something.
    Enter to select · ↑/↓ to navigate · Esc to cancel

按數字鍵就會選那一項，所以手機上的按鈕只要送數字。
只在畫面最後一段出現對話框的頁尾時才認，免得把對話內容裡的編號清單當成選項。
"""

import re

_OPT = re.compile(r"^\s*(❯\s*)?(\d{1,2})\.\s+(.+?)\s*$")
# 計畫模式的核准畫面（Yes／Tell Claude what to change）沒有 Esc to cancel，靠「Would you like to proceed?」認
_FOOTER = ("Enter to select", "Esc to cancel", "Enter to confirm", "Do you want to", "Would you like to proceed?")
# 按了會變成可以打字的那一項：選項題的 Type something、計畫核准的「Tell Claude what to change」、
# 權限提示的「No, and tell Claude what to do differently」
TYPE_SOMETHING = ("Type something", "Tell Claude what to change", "No, and tell Claude")
TYPE_EXACT = ("Other", "其他")
# 複選題每個選項前面有核取方塊；送出是清單最後一行、沒有編號：
# 只有一題時寫 Submit，一次問好幾題時寫 Next（2026-10-22 實測 v2.1.307）
_CHECK = re.compile(r"^\[([ ✔✓xX×])\]\s*(.*)$")
_SUBMIT = re.compile(r"^\s*(❯\s*)?(Submit|Next)\s*$")
# 一次問好幾題、答完最後一題後的確認頁（「1. Submit answers / 2. Cancel」）沒有頁尾，
# 要靠這一行認（2026-10-22 實測 v2.1.306）
_REVIEW = ("Ready to submit your answers?", "Review your answers")


def _review(window: list[str]) -> list[dict] | None:
    """確認頁上列出的「● 題目／→ 答案」；不是確認頁就回 None。

    要三個條件都成立才算：有「Review your answers」、它後面有「Ready to submit your answers?」
    而且在最後幾行、那一行之後全是編號選項——免得對話裡貼出來的範例被當成確認頁。
    """
    r = next((i for i in range(len(window) - 1, -1, -1) if window[i].strip() == _REVIEW[0]), None)
    # 選項底下可能還有一條 session 名稱的分隔線（「──── 專案｜摘要 ─」）
    after = [l for l in window[r + 1:] if not l.strip().startswith("─")] if r is not None else []
    if r is None or r < len(window) - 8 or not after or not all(_OPT.match(l) for l in after):
        return None
    h = next((i for i in range(r - 1, -1, -1) if window[i].strip() == _REVIEW[1]), None)
    if h is None:
        return None
    items: list[dict] = []
    in_answer = False
    for l in window[h + 1:r]:
        t = l.strip()
        if t.startswith("● "):
            items.append({"question": t[2:].strip(), "answer": ""})
            in_answer = False
        elif t.startswith("→ ") and items:
            items[-1]["answer"] = t[2:].strip()
            in_answer = True
        elif items and t:
            # 太長被換行：接回上一段（英數字之間補空白）
            field = "answer" if in_answer else "question"
            prev = items[-1][field]
            sep = " " if prev[-1:].isascii() and prev[-1:].isalnum() and t[:1].isascii() and t[:1].isalnum() else ""
            items[-1][field] = prev + sep + t
    return items


def tail(text: str, n: int = 18) -> list[str]:
    lines = [l.rstrip() for l in text.splitlines()]
    lines = [l for l in lines if l.strip()]
    return lines[-n:]


def _unnumbered(window: list[str]) -> tuple[list[dict], str | None]:
    """沒有編號的清單（例如「信任這個資料夾嗎」）：頁尾正上方那幾行，❯ 標的是目前選中的。

    這種只能用方向鍵移過去再按 Enter，所以 key 寫成 pick:<第幾項>，由 actions 換算成按鍵。
    """
    end = next((i for i in range(len(window) - 1, -1, -1) if any(f in window[i] for f in _FOOTER)), None)
    if end is None:
        return [], None
    block = []
    for l in reversed(window[:end]):
        m = re.match(r"^\s*(❯)?\s+(\S.*)$", l) if l.startswith((" ", "❯")) else None
        if not m or not (l.lstrip().startswith("❯") or l.startswith("   ")):
            break
        block.append((bool(m.group(1)), m.group(2).strip()))
    block.reverse()
    if not any(sel for sel, _ in block):
        return [], None
    opts = [{"key": f"pick:{i + 1}", "label": label} for i, (_, label) in enumerate(block)]
    selected = next(f"pick:{i + 1}" for i, (sel, _) in enumerate(block) if sel)
    return opts, selected


def parse_prompt(text: str) -> dict | None:
    lines = [l.rstrip() for l in text.splitlines() if l.strip()]
    window = lines[-30:]
    review = _review(window)
    if review is None and not any(any(f in l for f in _FOOTER) for l in window[-8:]):
        return None
    options = []
    selected = None
    submit_after = None
    for l in window:
        # 編號清單之後又出現輸入框（「❯」或「❯ 打過的字」）：前面那串是對話裡的清單，不是選單，丟掉
        t = l.strip()
        if (t == "❯" or t.startswith("❯ ")) and not _OPT.match(l) and not _SUBMIT.match(l):
            options, selected, submit_after = [], None, None
            continue
        sm = _SUBMIT.match(l)
        if sm and options:
            submit_after = options[-1]["key"]
            if sm.group(1):
                selected = "submit"
            continue
        m = _OPT.match(l)
        if not m:
            continue
        num = int(m.group(2))
        # 新的一組從 1 開始：只留最後一組
        if num == 1:
            options = []
            submit_after = None
        opt = {"key": str(num), "label": m.group(3)}
        c = _CHECK.match(opt["label"])
        if c:
            opt = {"key": opt["key"], "label": c.group(2), "checked": c.group(1) != " "}
        options.append(opt)
        if m.group(1):
            selected = str(num)
    if not options:
        options, selected = _unnumbered(window)
        if not options:
            return None
    other = next((o["key"] for o in options
                  if o["label"].startswith(TYPE_SOMETHING) or o["label"].rstrip(".") in TYPE_EXACT), None)
    out = {"options": options, "selected": selected, "type_key": other}
    if review is not None:
        out["review"] = review
    if submit_after:
        # 複選題：數字鍵只會勾／取消，送出要移到 Submit 那一行按 Enter（actions.press("submit")）
        out["submit_key"] = "submit"
        out["submit_after"] = submit_after
    return out

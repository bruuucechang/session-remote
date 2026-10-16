"""把對話紀錄的原始條目排成聊天畫面要的訊息串。

規則：使用者說的話、Claude 的回覆照原文；工具呼叫折成一行摘要；
思考過程、工具結果、系統注入的提醒、subagent 的支線都不顯示。
"""

import re

_CMD = re.compile(r"<command-name>(.*?)</command-name>", re.S)
_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)


def _user_text(content) -> str | None:
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        if any(b.get("type") == "tool_result" for b in content):
            return None
        text = "\n".join(b.get("text", "") for b in content if b.get("type") == "text")
    else:
        return None
    text = text.strip()
    if not text:
        return None
    m = _CMD.search(text)
    if m:   # 斜線指令：只顯示 /指令 參數
        args = _ARGS.search(text)
        return (m.group(1).strip() + " " + (args.group(1).strip() if args else "")).strip()
    if text.startswith(("<local-command", "<system-reminder", "<command-", "Caveat:", "<bash-", "<task-notification")):
        return None
    return text


def tool_summary(name: str, inp: dict) -> str:
    inp = inp or {}
    if name == "Bash":
        return inp.get("description") or inp.get("command", "")[:120]
    if name in ("Read", "Edit", "Write", "NotebookEdit"):
        return inp.get("file_path", "")
    if name in ("Grep", "Glob"):
        return inp.get("pattern", "")
    if name == "AskUserQuestion":
        qs = inp.get("questions") or []
        return qs[0].get("question", "") if qs else ""
    if name in ("Agent", "Task"):
        return inp.get("description", "")
    if name in ("WebFetch",):
        return inp.get("url", "")
    if name == "WebSearch":
        return inp.get("query", "")
    for v in inp.values():
        if isinstance(v, str) and v:
            return v[:120]
    return ""


def build(entries: list[dict]) -> dict:
    """回傳 {"title": str|None, "messages": [...]}。"""
    title = None
    messages = []
    for e in entries:
        t = e.get("type")
        if t == "custom-title":
            title = e.get("customTitle") or title
            continue
        if e.get("isSidechain") or e.get("isMeta"):
            continue
        msg = e.get("message") or {}
        ts = e.get("timestamp")
        if t == "user":
            text = _user_text(msg.get("content"))
            if text and text.startswith("[Request interrupted"):
                messages.append({"id": e.get("uuid"), "role": "system", "text": "已中斷", "ts": ts})
            elif text:
                messages.append({"id": e.get("uuid"), "role": "user", "text": text, "ts": ts})
        elif t == "assistant":
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for i, b in enumerate(content):
                bt = b.get("type")
                if bt == "text" and b.get("text", "").strip():
                    messages.append({"id": f"{e.get('uuid')}-{i}", "role": "assistant", "text": b["text"].strip(), "ts": ts})
                elif bt == "tool_use":
                    messages.append({
                        "id": f"{e.get('uuid')}-{i}", "role": "tool", "tool": b.get("name", ""),
                        "text": tool_summary(b.get("name", ""), b.get("input")), "ts": ts,
                    })
    return {"title": title, "messages": messages}


def last_text(messages: list[dict]) -> str:
    for m in reversed(messages):
        if m["role"] == "assistant":
            return m["text"]
        if m["role"] == "user":
            return "你：" + m["text"]
    return ""

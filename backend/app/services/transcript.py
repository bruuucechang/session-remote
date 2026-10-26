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
    use_ids: dict[str, str] = {}   # 工具訊息 id → tool_use id
    done: set[str] = set()         # 已經有 tool_result 的 tool_use id
    for e in entries:
        t = e.get("type")
        if t == "custom-title":
            title = e.get("customTitle") or title
            continue
        if e.get("isSidechain") or e.get("isMeta"):
            continue
        msg = e.get("message") or {}
        ts = e.get("timestamp")
        if t == "user" and isinstance(msg.get("content"), list):
            done.update(b.get("tool_use_id") for b in msg["content"] if isinstance(b, dict) and b.get("type") == "tool_result")
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
                    use_ids[f"{e.get('uuid')}-{i}"] = b.get("id", "")
                    messages.append({
                        "id": f"{e.get('uuid')}-{i}", "role": "tool", "tool": b.get("name", ""),
                        "text": tool_summary(b.get("name", ""), b.get("input")), "ts": ts,
                    })
    return {"title": title, "messages": messages, "open": {m for m, u in use_ids.items() if u not in done}}


def awaiting(built: dict) -> dict | None:
    """正在等權限的那一則工具呼叫：對話最後一段連續的工具呼叫裡還沒跑完的，恰好一則才算。

    權限通知新版只寫「Claude needs your permission」（v2.1.310），手機靠這個講出是哪個工具。
    拿不準就回 None（讓手機只寫「要你允許」）：同時開著兩則以上（平行呼叫，被問的不一定是哪個）、
    或那一段有還沒跑完的 Agent／Task（可能是 subagent 在要權限，它的工具呼叫不在主對話裡）。
    """
    tail = []
    for m in reversed(built["messages"]):
        if m["role"] != "tool":
            break
        tail.append(m)
    pending = [m for m in tail if m["id"] in built.get("open", set())]
    if len(pending) != 1 or pending[0].get("tool") in ("Agent", "Task"):
        return None
    return pending[0]


def last_text(messages: list[dict]) -> str:
    for m in reversed(messages):
        if m["role"] == "assistant":
            return m["text"]
        if m["role"] == "user":
            return "你：" + m["text"]
    return ""


def _result_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


MAX_DETAIL = 20_000


def tool_detail(entries: list[dict], message_id: str) -> dict | None:
    """手機點開一個工具呼叫：完整的輸入（指令、路徑、改了什麼）與它的輸出。

    message_id 是 build() 給工具那一行的 id（<uuid>-<第幾塊>）。輸出在後面某一筆 user 紀錄的 tool_result 裡，
    用 tool_use_id 對回來。太長的截斷，免得手機一次吃幾 MB。
    """
    uuid, _, idx = message_id.rpartition("-")
    if not idx.isdigit():
        return None
    use = None
    for e in entries:
        if e.get("type") == "assistant" and e.get("uuid") == uuid:
            content = (e.get("message") or {}).get("content")
            if isinstance(content, list) and int(idx) < len(content):
                b = content[int(idx)]
                if b.get("type") == "tool_use":
                    use = b
            break
    if use is None:
        return None
    output, is_error = None, False
    for e in entries:
        content = (e.get("message") or {}).get("content")
        if e.get("type") != "user" or not isinstance(content, list):
            continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") == use.get("id"):
                output = _result_text(b.get("content"))
                is_error = bool(b.get("is_error"))
        if output is not None:
            break
    inp = use.get("input") or {}
    clipped = {k: (v[:MAX_DETAIL] if isinstance(v, str) else v) for k, v in inp.items()}
    return {
        "tool": use.get("name", ""),
        "summary": tool_summary(use.get("name", ""), inp),
        "input": clipped,
        "output": output[:MAX_DETAIL] if output is not None else None,
        "output_truncated": output is not None and len(output) > MAX_DETAIL,
        "is_error": is_error,
    }


def search(messages: list[dict], q: str, limit: int = 50) -> list[dict]:
    """整段對話裡找字（不分大小寫），最新的在前；回傳那一則的 id 與命中處前後一小段。"""
    q = q.strip().lower()
    if not q:
        return []
    hits = []
    for m in reversed(messages):
        text = m.get("text", "")
        i = text.lower().find(q)
        if i < 0:
            continue
        start = max(0, i - 40)
        hits.append({"id": m["id"], "role": m["role"], "tool": m.get("tool"),
                     "snippet": ("…" if start else "") + text[start:i + len(q) + 80].replace("\n", " ")})
        if len(hits) >= limit:
            break
    return hits

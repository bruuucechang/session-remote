from app.services import transcript


def test_build_hides_noise_and_folds_tools():
    entries = [
        {"type": "custom-title", "customTitle": "專案｜第一句"},
        {"type": "user", "uuid": "u1", "message": {"content": "幫我跑測試"}},
        {"type": "user", "uuid": "u0", "isMeta": True, "message": {"content": "meta"}},
        {"type": "user", "uuid": "u2", "message": {"content": "<system-reminder>x</system-reminder>"}},
        {"type": "assistant", "uuid": "a1", "message": {"content": [
            {"type": "thinking", "thinking": "..."},
            {"type": "tool_use", "name": "Bash", "input": {"command": "pytest", "description": "跑測試"}},
        ]}},
        {"type": "user", "uuid": "u3", "message": {"content": [{"type": "tool_result", "content": "ok"}]}},
        {"type": "assistant", "uuid": "a2", "isSidechain": True, "message": {"content": [{"type": "text", "text": "支線"}]}},
        {"type": "assistant", "uuid": "a3", "message": {"content": [{"type": "text", "text": "全過了"}]}},
        {"type": "user", "uuid": "u4", "message": {"content": "<command-name>/ship</command-name><command-args>now</command-args>"}},
    ]
    b = transcript.build(entries)
    assert b["title"] == "專案｜第一句"
    assert [(m["role"], m["text"]) for m in b["messages"]] == [
        ("user", "幫我跑測試"),
        ("tool", "跑測試"),
        ("assistant", "全過了"),
        ("user", "/ship now"),
    ]
    assert transcript.last_text(b["messages"]) == "你：/ship now"


def test_tool_detail_pairs_result_and_search():
    from app.services.transcript import build, search, tool_detail
    entries = [
        {"type": "assistant", "uuid": "a1", "message": {"content": [
            {"type": "text", "text": "改一下"},
            {"type": "tool_use", "id": "tu1", "name": "Edit",
             "input": {"file_path": "/x.py", "old_string": "a = 1", "new_string": "a = 2"}}]}},
        {"type": "user", "uuid": "u1", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "tu1", "content": [{"type": "text", "text": "已修改"}]}]}},
        {"type": "user", "uuid": "u2", "message": {"content": "幫我找 Banana 在哪"}},
    ]
    d = tool_detail(entries, "a1-1")
    assert d["tool"] == "Edit" and d["input"]["new_string"] == "a = 2" and d["output"] == "已修改" and not d["is_error"]
    assert tool_detail(entries, "a1-0") is None      # 那一塊是文字不是工具
    assert tool_detail(entries, "nope-1") is None
    hits = search(build(entries)["messages"], "banana")
    assert [h["id"] for h in hits] == ["u2"] and "Banana" in hits[0]["snippet"]
    assert search(build(entries)["messages"], "  ") == []


def _use(uuid, *tools, side=False):
    return {"type": "assistant", "uuid": uuid, "isSidechain": side, "message": {"content": [
        {"type": "tool_use", "id": f"{uuid}-{n}", "name": n, "input": {"command": n}} for n in tools]}}


def _result(*ids):
    return {"type": "user", "uuid": "r-" + ids[0], "message": {"content": [
        {"type": "tool_result", "tool_use_id": i, "content": "ok"} for i in ids]}}


def test_awaiting_tool_is_the_single_open_call():
    # 權限通知沒寫工具名時，手機靠這個講出是哪一個：只認「最後一段工具呼叫裡恰好一則還沒跑完」
    built = transcript.build([_use("a", "Read"), _result("a-Read"), _use("b", "Bash")])
    assert transcript.awaiting(built)["tool"] == "Bash"


def test_awaiting_tool_none_when_ambiguous():
    # 已經跑完的工具不算（tool_use 還沒寫進紀錄的那一刻，不能拿上一個 Read 頂替）
    assert transcript.awaiting(transcript.build([_use("a", "Read"), _result("a-Read")])) is None
    # 平行呼叫、兩則都還沒跑完：被問的不一定是最後一個
    assert transcript.awaiting(transcript.build([_use("a", "Bash", "Read")])) is None
    # subagent 在跑：要權限的可能是它（它的呼叫不在主對話裡）
    built = transcript.build([_use("a", "Agent"), _use("s", "Bash", side=True)])
    assert transcript.awaiting(built) is None
    # 很久以前被中斷、沒有結果的呼叫不算（中間隔了別的訊息）
    old = [_use("a", "Bash"), {"type": "user", "uuid": "u", "message": {"content": "算了"}}]
    assert transcript.awaiting(transcript.build(old)) is None

"""POST /notify 的服務層：沒金鑰略過、沒裝置不送、有就照 APNs 送（不連真的 Apple）。"""

from app.services import notify


def test_skipped_without_key(monkeypatch):
    monkeypatch.setattr(notify.apns, "configured", lambda: False)
    assert notify.send_text("t", "b") == "skipped"


def test_no_devices(monkeypatch):
    monkeypatch.setattr(notify.apns, "configured", lambda: True)
    monkeypatch.setattr(notify.store, "load", lambda name: {})
    assert notify.send_text("t", "b") == "no-devices"


def test_muted_thread(monkeypatch):
    sent = []
    data = {"settings": {"mute_threads": ["autoloop"]}, "devices": {"tok": {"env": "sandbox"}}}
    monkeypatch.setattr(notify.apns, "configured", lambda: True)
    monkeypatch.setattr(notify.store, "load", lambda name: data.get(name, {}))
    monkeypatch.setattr(notify.apns, "send", lambda tok, env, payload, collapse_id=None: sent.append(tok))
    assert notify.send_text("出圖檢查點", "x", thread="autoloop") == "muted" and sent == []
    assert notify.send_text("推送佇列被退回、沒人修", "x", thread="pushq") == "sent" and sent == ["tok"]


def test_sends_without_session_key(monkeypatch):
    sent = []
    monkeypatch.setattr(notify.apns, "configured", lambda: True)
    monkeypatch.setattr(notify.store, "load", lambda name: {"tok": {"env": "sandbox"}})
    monkeypatch.setattr(notify.apns, "send", lambda tok, env, payload, collapse_id=None: sent.append((tok, payload, collapse_id)))
    assert notify.send_text("合併了", "第 3 輪") == "sent"
    (tok, payload, cid), = sent
    assert tok == "tok" and cid is None and "session" not in payload
    assert payload["aps"]["alert"] == {"title": "合併了", "body": "第 3 輪"}


def test_activity_payload_events():
    from app.services.notify import activity_payload
    busy = {"working": 2, "waiting": 1, "done": 0, "headline": "animyria：要怎麼處理？"}
    p, prio = activity_payload(busy, {"working": 2, "waiting": 0, "done": 0, "headline": "x"}, 1000.0, start=False)
    assert p["aps"]["event"] == "update" and prio == 10 and "alert" in p["aps"]
    assert p["aps"]["content-state"] == {"working": 2, "waiting": 1, "background": 0, "done": 0,
                                         "headline": "animyria：要怎麼處理？"}
    p, prio = activity_payload(busy, busy, 1000.0, start=False)
    assert prio == 5 and "alert" not in p["aps"]
    idle = {"working": 0, "waiting": 0, "done": 3, "headline": "都做完了"}
    p, _ = activity_payload(idle, busy, 1000.0, start=False)
    assert p["aps"]["event"] == "end" and p["aps"]["dismissal-date"] == 1000 + 900
    p, prio = activity_payload(busy, None, 1000.0, start=True)
    assert p["aps"]["event"] == "start" and p["aps"]["attributes-type"] == "SessionsActivityAttributes" and prio == 10


def test_should_alert_star_only():
    from app.services.notify import should_alert
    on, off = {"star_only_push": True}, {"star_only_push": False}
    done = {"status": "done", "starred": False}
    assert should_alert(done, off) and not should_alert(done, on)
    assert should_alert({"status": "done", "starred": True}, on)
    assert should_alert({"status": "waiting", "starred": False}, on)   # 等你回答一律跳
    assert not should_alert({"status": "working", "starred": True}, off)

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
    assert p["aps"]["event"] == "end" and p["aps"]["dismissal-date"] == 1000
    p, prio = activity_payload(busy, None, 1000.0, start=True)
    assert p["aps"]["event"] == "start" and p["aps"]["attributes-type"] == "SessionsActivityAttributes" and prio == 10


def test_should_alert_star_only():
    from app.services.notify import should_alert
    on, off = {"done_push": True, "star_only_push": True}, {"done_push": True, "star_only_push": False}
    done = {"status": "done", "starred": False}
    assert should_alert(done, off) and not should_alert(done, on)
    assert should_alert({"status": "done", "starred": True}, on)
    assert should_alert({"status": "waiting", "starred": False}, on)   # 等你回答一律跳
    assert not should_alert({"status": "working", "starred": True}, off)


def test_done_push_defaults_off(monkeypatch):
    monkeypatch.setattr(notify.store, "load", lambda name: {"star_only_push": False})
    assert notify.settings()["done_push"] is False
    for starred in (True, False):
        for cfg in ({}, {"done_push": False}, {"done_push": False, "star_only_push": True}):
            assert not notify.should_alert({"status": "done", "starred": starred}, cfg)
            assert notify.should_alert({"status": "waiting", "starred": starred}, cfg)


def test_activity_only_waiting_starts_and_ends_immediately(monkeypatch):
    sent = []
    data = {"activities": {"start": {"kind": "start", "env": "sandbox"}}}
    monkeypatch.setattr(notify.store, "load", lambda name: data.get(name, {}).copy())
    monkeypatch.setattr(notify.store, "save", lambda name, value: data.update({name: value}))
    monkeypatch.setattr(notify.apns, "send", lambda token, env, payload, **kw: sent.append((token, payload)))
    monkeypatch.setattr("time.time", lambda: 1234.5)
    busy = {"working": 2, "waiting": 0, "background": 1, "done": 0, "headline": "x"}
    for sm in (busy, {**busy, "background": 0}, {**busy, "working": 0}):
        notify._push_activity(sm, None)
        assert sent == []
    waiting = {**busy, "waiting": 1}
    notify._push_activity(waiting, busy)
    assert sent[-1][1]["aps"]["event"] == "start"
    data["activities"]["update"] = {"kind": "update", "env": "sandbox"}
    notify._push_activity(busy, waiting)
    assert sent[-1][0] == "update"
    assert sent[-1][1]["aps"]["event"] == "end"
    assert sent[-1][1]["aps"]["dismissal-date"] == 1234
    assert data["activities"] == {"start": {"kind": "start", "env": "sandbox"}}
    notify._push_activity(busy, busy)
    assert len(sent) == 2


def test_done_push_settings_preserve_other_preferences(monkeypatch):
    data = {"settings": {"star_only_push": True, "mute_threads": ["autoloop"]}}
    monkeypatch.setattr(notify.store, "load", lambda name: data.get(name, {}).copy())
    monkeypatch.setattr(notify.store, "save", lambda name, value: data.update({name: value}))
    from app.routers.api import Settings, set_settings
    assert set_settings(Settings(done_push=True))["done_push"] is True
    cfg = notify.update_settings(done_push=False, star_only_push=None)
    assert cfg == {"done_push": False, "star_only_push": True, "mute_threads": ["autoloop"]}

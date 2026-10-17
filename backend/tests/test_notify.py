"""POST /notify 的服務層：沒金鑰略過、沒裝置不送、有就照 APNs 送（不連真的 Apple）。"""

from app.services import notify


def test_skipped_without_key(monkeypatch):
    monkeypatch.setattr(notify.apns, "configured", lambda: False)
    assert notify.send_text("t", "b") == "skipped"


def test_no_devices(monkeypatch):
    monkeypatch.setattr(notify.apns, "configured", lambda: True)
    monkeypatch.setattr(notify.store, "load", lambda name: {})
    assert notify.send_text("t", "b") == "no-devices"


def test_sends_without_session_key(monkeypatch):
    sent = []
    monkeypatch.setattr(notify.apns, "configured", lambda: True)
    monkeypatch.setattr(notify.store, "load", lambda name: {"tok": {"env": "sandbox"}})
    monkeypatch.setattr(notify.apns, "send", lambda tok, env, payload, collapse_id=None: sent.append((tok, payload, collapse_id)))
    assert notify.send_text("合併了", "第 3 輪") == "sent"
    (tok, payload, cid), = sent
    assert tok == "tok" and cid is None and "session" not in payload
    assert payload["aps"]["alert"] == {"title": "合併了", "body": "第 3 輪"}

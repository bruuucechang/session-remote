"""推播：session 變成「等你回答」或「做完」時通知手機。

在背景執行緒送，hook 那邊不用等 Apple 回應。
"""

import logging
import threading

from ..repositories import apns, store

log = logging.getLogger("notify")

_devices_lock = threading.Lock()


def register(token: str, env: str) -> None:
    with _devices_lock:
        data = store.load("devices")
        data[token] = {"env": env if env in ("sandbox", "production") else "sandbox"}
        store.save("devices", data)


def _body(view: dict) -> tuple[str, str]:
    acct = (view.get("account") or {}).get("label", "")
    title = f"{view['name']}"
    pending = view.get("pending") or {}
    if view["status"] == "waiting":
        if pending.get("kind") == "ask" and pending.get("questions"):
            body = "問你：" + pending["questions"][0].get("question", "")
        else:
            body = pending.get("message") or "等你回答"
    else:
        body = "做完了：" + (view.get("last_text") or "")
    return title, f"[{acct}] {body}"[:400]


# 上一次推給手機的圖示紅點數字；沒變就不推
_last_badge: int | None = None


def _send(view: dict, badge: int | None) -> None:
    title, body = _body(view)
    aps = {"alert": {"title": title, "body": body}, "sound": "default", "thread-id": view["id"]}
    if badge is not None:
        aps["badge"] = badge
    _push({"aps": aps, "session": view["id"]}, view["id"])


def _send_badge(badge: int) -> None:
    """只改 app 圖示紅點、不跳通知（例如你在電腦上答完了，紅點要跟著少一個）。"""
    _push({"aps": {"badge": badge}}, "badge")


def send_text(title: str, body: str, thread: str = "notify") -> str:
    """別的本機服務（office 的產線通知）要推一則跟 session 無關的訊息。
    回傳 sent／skipped（沒設金鑰）／no-devices。不帶 session，點開只會打開 app。"""
    if not apns.configured():
        return "skipped"
    if not store.load("devices"):
        return "no-devices"
    payload = {"aps": {"alert": {"title": title[:120], "body": body[:400]}, "sound": "default", "thread-id": thread}}
    _push(payload, None)
    return "sent"


def _push(payload: dict, collapse_id: str | None) -> None:
    dead = []
    for token, info in store.load("devices").items():
        try:
            apns.send(token, info.get("env", "sandbox"), payload, collapse_id=collapse_id)
        except apns.BadToken:
            dead.append(token)
        except Exception as e:   # 推播失敗不能拖垮服務
            log.warning("推播失敗：%s", e)
    if dead:
        with _devices_lock:
            data = store.load("devices")
            for t in dead:
                data.pop(t, None)
            store.save("devices", data)


def session_changed(tty: str) -> None:
    if not apns.configured():
        return

    def run():
        global _last_badge
        from . import sessions   # 避免循環 import
        try:
            view = sessions.view_by_tty(tty)
            badge = sessions.waiting_count()
        except Exception as e:
            log.warning("讀 session 失敗：%s", e)
            return
        if view and view["status"] in ("waiting", "done"):
            _send(view, badge)
        elif badge != _last_badge:
            _send_badge(badge)
        _last_badge = badge

    threading.Thread(target=run, daemon=True).start()

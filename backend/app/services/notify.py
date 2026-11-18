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


def register_activity(token: str, env: str, kind: str) -> None:
    """鎖定畫面即時狀態的推播 token。kind=start：讓筆電能遠端開一個（iOS 17.2+）；update：更新正開著的那一個。"""
    with _devices_lock:
        data = store.load("activities")
        if kind == "update":
            # 同一時間只會有一個在顯示，舊的 update token 作廢
            data = {t: v for t, v in data.items() if v.get("kind") != "update"}
        data[token] = {"env": env if env in ("sandbox", "production") else "sandbox", "kind": kind}
        store.save("activities", data)
    summary_changed(force=True)


def _body(view: dict) -> tuple[str, str]:
    acct = (view.get("account") or {}).get("id", "")
    title = f"{view['name']}"
    pending = view.get("pending") or {}
    if view["status"] == "waiting":
        if pending.get("kind") == "ask" and pending.get("questions"):
            body = "問你：" + pending["questions"][0].get("question", "")
        else:
            body = pending.get("message") or "等你回答"
    else:
        body = "完工：" + (view.get("last_text") or "")
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
    回傳 sent／skipped（沒設金鑰）／muted（thread 在設定的 mute_threads 裡）／no-devices。不帶 session，點開只會打開 app。"""
    if not apns.configured():
        return "skipped"
    if thread in settings().get("mute_threads", []):
        return "muted"   # 例行回報（例如 autoloop 出圖檢查點）：使用者只要「要你動手」與定期報告
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
    """有 session 換了狀態：等你／做完就跳通知；不管哪一種都更新紅點與鎖定畫面。"""
    if not apns.configured():
        return

    def run():
        from . import sessions   # 避免循環 import
        try:
            view = sessions.view_by_tty(tty)
        except Exception as e:
            log.warning("讀 session 失敗：%s", e)
            view = None
        if view and should_alert(view, settings()):
            _send(view, _waiting_now())
        _summary()

    threading.Thread(target=run, daemon=True).start()


def settings() -> dict:
    return {"done_push": False, "star_only_push": False, "mute_threads": [], **store.load("settings")}


def update_settings(**kw) -> dict:
    with _devices_lock:
        data = store.load("settings")
        data.update({k: v for k, v in kw.items() if v is not None})
        store.save("settings", data)
    return settings()


def should_alert(view: dict, cfg: dict) -> bool:
    """跳不跳通知：等你回答一律跳；完工要先開「完工也推播」，再看是否只推星號。
    背景跑（回合結束但背景還在）不跳：等背景結束 sessions.check_background 會再叫一次。"""
    if view["status"] == "waiting":
        return True
    if view["status"] == "done":
        return bool(cfg.get("done_push", False)) and (not cfg.get("star_only_push") or bool(view.get("starred")))
    return False


def summary_changed(force: bool = False) -> None:
    if not apns.configured():
        return
    threading.Thread(target=_summary, kwargs={"force": force}, daemon=True).start()


_summary_lock = threading.Lock()
_last_summary: dict | None = None


def _waiting_now() -> int | None:
    from . import sessions
    try:
        return sessions.summary()["waiting"]
    except Exception as e:
        log.warning("算等你回答的數量失敗：%s", e)
        return None


def _summary(force: bool = False) -> None:
    """紅點數字與鎖定畫面的即時狀態。跟上一次一樣就不推（即時狀態的推播有每小時額度）。"""
    global _last_badge, _last_summary
    from . import sessions
    try:
        sm = sessions.summary()
    except Exception as e:
        log.warning("算摘要失敗：%s", e)
        return
    with _summary_lock:
        if sm["waiting"] != _last_badge:
            _send_badge(sm["waiting"])
            _last_badge = sm["waiting"]
        if not force and sm == _last_summary:
            return
        prev, _last_summary = _last_summary, sm
    _push_activity(sm, prev)


def activity_payload(sm: dict, prev: dict | None, now: float, start: bool) -> tuple[dict, int]:
    """組 Live Activity 的推播內容。content-state 的欄位要跟 app 的 SessionsActivityAttributes.ContentState 一字不差。"""
    state = {"working": sm["working"], "waiting": sm["waiting"], "background": sm.get("background", 0),
             "done": sm["done"], "headline": sm["headline"]}
    aps = {"timestamp": int(now), "content-state": state}
    active = sm["waiting"] > 0
    if start and active:
        aps.update({"event": "start", "attributes-type": "SessionsActivityAttributes", "attributes": {}})
    elif not active:
        # 沒有等你回答的就立即消失，即使還有工作或背景任務
        aps.update({"event": "end", "dismissal-date": int(now)})
    else:
        aps["event"] = "update"
    # 新冒出一個等你回答的才用高優先（會亮螢幕）；其他更新用低優先，省 Apple 給的額度
    newly_waiting = sm["waiting"] > (prev or {}).get("waiting", 0)
    if newly_waiting:
        aps["alert"] = {"title": "Claude 在等你", "body": sm["headline"]}
    return {"aps": aps}, (10 if newly_waiting or start else 5)


def _push_activity(sm: dict, prev: dict | None) -> None:
    import time
    acts = store.load("activities")
    updates = {t: v for t, v in acts.items() if v.get("kind") == "update"}
    starts = {t: v for t, v in acts.items() if v.get("kind") == "start"}
    active = sm["waiting"] > 0
    dead = []
    if updates:
        payload, prio = activity_payload(sm, prev, time.time(), start=False)
        for t, v in updates.items():
            try:
                apns.send(t, v.get("env", "sandbox"), payload, push_type="liveactivity", priority=prio)
            except apns.BadToken:
                dead.append(t)
            except Exception as e:
                log.warning("即時狀態推播失敗：%s", e)
        if not active:
            dead += list(updates)   # 結束了，這個 token 不能再用
    elif active and starts:
        payload, prio = activity_payload(sm, prev, time.time(), start=True)
        for t, v in starts.items():
            try:
                apns.send(t, v.get("env", "sandbox"), payload, push_type="liveactivity", priority=prio)
            except apns.BadToken:
                dead.append(t)
            except Exception as e:
                log.warning("即時狀態開啟失敗：%s", e)
    if dead:
        with _devices_lock:
            data = store.load("activities")
            for t in dead:
                data.pop(t, None)
            store.save("activities", data)

"""Apple 推播（APNs，token 認證）。

金鑰（.p8）在 Apple 開發者後台建，路徑與 Key ID 寫進 .env；沒設就整個略過。
開發簽章（Xcode 直接裝的）的 app 拿到的 token 屬於 sandbox，要送到 sandbox 主機，
所以每支裝置的 token 都記著自己是哪個環境。
"""

import json
import logging
import time

import httpx
import jwt

from .. import config

log = logging.getLogger("apns")

HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}

_jwt: tuple[str, float] | None = None


def configured() -> bool:
    return bool(config.APNS_KEY_PATH and config.APNS_KEY_ID and config.APNS_TEAM_ID)


def _token() -> str:
    global _jwt
    # Apple 規定 20～60 分鐘換一次，太頻繁會被擋（TooManyProviderTokenUpdates）
    if _jwt and time.time() - _jwt[1] < 40 * 60:
        return _jwt[0]
    key = open(config.APNS_KEY_PATH).read()
    now = time.time()
    tok = jwt.encode({"iss": config.APNS_TEAM_ID, "iat": int(now)}, key, algorithm="ES256",
                     headers={"kid": config.APNS_KEY_ID})
    _jwt = (tok, now)
    return tok


class BadToken(Exception):
    """裝置 token 失效（app 刪掉重裝之類），呼叫端應該把它從清單移除。"""


def send(device_token: str, env: str, payload: dict, collapse_id: str | None = None,
         push_type: str = "alert", priority: int = 10) -> None:
    """push_type="liveactivity" 是鎖定畫面／動態島的即時狀態，topic 要加 .push-type.liveactivity。"""
    if not configured():
        return
    topic = config.APNS_BUNDLE_ID + (".push-type.liveactivity" if push_type == "liveactivity" else "")
    headers = {
        "authorization": f"bearer {_token()}",
        "apns-topic": topic,
        "apns-push-type": push_type,
        "apns-priority": str(priority),
    }
    if collapse_id:
        headers["apns-collapse-id"] = collapse_id[:64]
    url = f"{HOSTS.get(env, HOSTS['sandbox'])}/3/device/{device_token}"
    with httpx.Client(http2=True, timeout=10) as c:
        r = c.post(url, headers=headers, content=json.dumps(payload, ensure_ascii=False).encode())
    if r.status_code == 200:
        return
    reason = ""
    try:
        reason = r.json().get("reason", "")
    except Exception:
        pass
    if r.status_code == 410 or reason in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"):
        raise BadToken(reason)
    log.warning("APNs %s %s", r.status_code, reason)

"""手機用的 API。全部要帶通行碼（Authorization: Bearer <SESSION_REMOTE_TOKEN>）。"""

import asyncio
import base64
import binascii
import hmac

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .. import config
from ..repositories import iterm
from ..services import actions, events, notify, quota, sessions


def require_token(authorization: str = Header(default=""), token: str = Query(default="")):
    given = authorization.removeprefix("Bearer ").strip() or token
    if not config.TOKEN or not hmac.compare_digest(given, config.TOKEN):
        raise HTTPException(401, "通行碼不對")


router = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


def _do(fn, *args):
    try:
        return fn(*args)
    except actions.NotFound:
        raise HTTPException(404, "找不到這個 session（分頁關了？）")
    except actions.BadRequest as e:
        raise HTTPException(400, str(e))
    except iterm.ItermError as e:
        raise HTTPException(503, f"iTerm2：{e}")


@router.get("/sessions")
def list_sessions():
    try:
        return {"sessions": sessions.list_views(), "version": events.version()}
    except iterm.ItermError as e:
        raise HTTPException(503, f"iTerm2：{e}")


@router.get("/sessions/{sid}")
def get_session(sid: str, limit: int = 200, after: str | None = None, before: str | None = None,
                screen: bool = True):
    v = _do(sessions.detail, sid, limit, after, before)
    if v is None:
        raise HTTPException(404, "找不到這個 session（分頁關了？）")
    if not screen:   # 終端機畫面只有手機打開「顯示終端機畫面」才要，平常省掉這一半流量
        v["screen"] = []
    return v


class Reply(BaseModel):
    text: str


@router.post("/sessions/{sid}/reply")
def reply(sid: str, body: Reply):
    _do(actions.reply, sid, body.text)
    return {"ok": True}


class Key(BaseModel):
    key: str


@router.post("/sessions/{sid}/key")
def key(sid: str, body: Key):
    _do(actions.press, sid, body.key)
    return {"ok": True}


@router.post("/sessions/{sid}/interrupt")
def interrupt(sid: str):
    _do(actions.interrupt, sid)
    return {"ok": True}


@router.post("/sessions/{sid}/close")
def close(sid: str):
    _do(actions.close, sid)
    return {"ok": True}


class Upload(BaseModel):
    data: str          # base64
    ext: str = "jpg"


@router.post("/sessions/{sid}/upload")
def upload(sid: str, body: Upload):
    try:
        raw = base64.b64decode(body.data, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(400, "圖片資料壞了")
    return {"ok": True, "path": _do(actions.upload, sid, raw, body.ext)}


class Star(BaseModel):
    starred: bool


@router.post("/sessions/{sid}/star")
def star(sid: str, body: Star):
    if not sessions.find(sid):
        raise HTTPException(404, "找不到這個 session（分頁關了？）")
    sessions.set_star(sid, body.starred)
    return {"ok": True}


class Settings(BaseModel):
    star_only_push: bool | None = None


@router.get("/settings")
def get_settings():
    return notify.settings()


@router.post("/settings")
def set_settings(body: Settings):
    return notify.update_settings(star_only_push=body.star_only_push)


@router.get("/quota")
def get_quota():
    return quota.accounts()


class Activity(BaseModel):
    token: str
    env: str = "sandbox"
    kind: str = "update"   # update｜start


@router.post("/activities")
def register_activity(body: Activity):
    if body.kind not in ("update", "start"):
        raise HTTPException(400, "kind 只能是 update 或 start")
    notify.register_activity(body.token, body.env, body.kind)
    return {"ok": True}


class NewSession(BaseModel):
    directory: str
    account: str
    prompt: str = ""


@router.post("/sessions")
def new_session(body: NewSession):
    return {"ok": True, "id": _do(actions.new_session, body.directory, body.account, body.prompt)}


@router.get("/sessions/{sid}/tools/{mid}")
def tool_detail(sid: str, mid: str):
    d = _do(sessions.tool_detail, sid, mid)
    if d is None:
        raise HTTPException(404, "找不到這個工具呼叫")
    return d


@router.get("/sessions/{sid}/search")
def search(sid: str, q: str = ""):
    hits = _do(sessions.search, sid, q)
    if hits is None:
        raise HTTPException(404, "找不到這個 session（分頁關了？）")
    return {"hits": hits}


@router.get("/options")
def options():
    return {"projects": actions.project_dirs(), "recent": actions.recent_dirs(), "accounts": actions.account_list()}


class Device(BaseModel):
    token: str
    env: str = "sandbox"


@router.post("/devices")
def register_device(body: Device):
    notify.register(body.token, body.env)
    return {"ok": True}


@router.get("/events")
async def stream():
    """SSE：版本號一變就送一行 `data: <版本>`，手機收到就重抓。每 15 秒送心跳。"""
    async def gen():
        last = -1
        idle = 0.0
        while True:
            v = events.version()
            if v != last:
                last = v
                idle = 0.0
                yield f"data: {v}\n\n"
            elif idle >= 15:
                idle = 0.0
                yield ": ping\n\n"
            await asyncio.sleep(0.5)
            idle += 0.5

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"cache-control": "no-cache"})

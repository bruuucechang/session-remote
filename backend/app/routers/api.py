"""手機用的 API。全部要帶通行碼（Authorization: Bearer <SESSION_REMOTE_TOKEN>）。"""

import asyncio
import hmac

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .. import config
from ..repositories import iterm
from ..services import actions, events, notify, sessions


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
def get_session(sid: str, limit: int = 200):
    v = _do(sessions.detail, sid, limit)
    if v is None:
        raise HTTPException(404, "找不到這個 session（分頁關了？）")
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


class NewSession(BaseModel):
    directory: str
    account: str


@router.post("/sessions")
def new_session(body: NewSession):
    return {"ok": True, "id": _do(actions.new_session, body.directory, body.account)}


@router.get("/options")
def options():
    return {"projects": actions.project_dirs(), "accounts": actions.account_list()}


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

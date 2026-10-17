"""Claude Code hook（hooks/report.mjs）回報進來的入口。只收本機。"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..services import notify, sessions

router = APIRouter()


class HookEvent(BaseModel):
    event: str
    tty: str | None = None
    pid: int | None = None
    config_dir: str = ""
    payload: dict = {}


@router.post("/hook")
def hook(body: HookEvent, request: Request):
    if request.client is None or request.client.host not in ("127.0.0.1", "::1"):
        raise HTTPException(403, "hook 只收本機")
    sessions.apply_hook(body.event, body.tty, body.pid, body.config_dir, body.payload)
    return {"ok": True}


class Notice(BaseModel):
    title: str
    body: str = ""
    thread: str = "notify"


@router.post("/notify")
def push_notice(body: Notice, request: Request):
    """本機其他服務推一則訊息到手機（office 的產線：自動合併、目標卡住）。跟 /hook 一樣只收本機。"""
    if request.client is None or request.client.host not in ("127.0.0.1", "::1"):
        raise HTTPException(403, "notify 只收本機")
    return {"result": notify.send_text(body.title, body.body, body.thread)}

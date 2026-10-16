"""Claude Code hook（hooks/report.mjs）回報進來的入口。只收本機。"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..services import sessions

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

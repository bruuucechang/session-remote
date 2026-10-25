"""假資料模式（SR_FAKE）才掛上的測試控制端點，帶跟 /api 一樣的通行碼。"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..services import fakectl
from .api import require_token

router = APIRouter(prefix="/fake", dependencies=[Depends(require_token)])


class Reset(BaseModel):
    scenario: str = ""


@router.post("/reset")
def reset(body: Reset | None = None):
    try:
        fakectl.reset(body.scenario if body else "")
    except (ValueError, FileNotFoundError) as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


@router.get("/log")
def log():
    return {"log": fakectl.log()}


class Screen(BaseModel):
    id: str
    text: str


@router.post("/screen")
def screen(body: Screen):
    fakectl.set_screen(body.id, body.text)
    return {"ok": True}

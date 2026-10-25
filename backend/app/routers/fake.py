"""假資料模式（SR_FAKE）才掛上的測試控制端點，帶跟 /api 一樣的通行碼。"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..services import fakectl
from .api import require_token

router = APIRouter(prefix="/fake", dependencies=[Depends(require_token)])


@router.post("/reset")
def reset():
    fakectl.reset()
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

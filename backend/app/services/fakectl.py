"""假資料模式的控制：UI 測試每一條開始前重來、讀回送出去的字、換某個分頁的畫面。"""

from ..repositories import fake
from . import events, sessions


def reset() -> None:
    fake.reset()
    sessions.reload_state(fake.records())


def log() -> list[dict]:
    return fake.log()


def set_screen(session_id: str, text: str) -> None:
    fake.set_screen(session_id, text)
    events.bump()

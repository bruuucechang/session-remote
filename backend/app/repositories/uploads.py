"""手機傳上來的照片：存成檔案，回傳絕對路徑讓 Claude 用 Read 看。"""

import secrets
import time
from pathlib import Path

from .. import config

EXTS = {"jpg", "jpeg", "png", "heic"}


def save(data: bytes, ext: str) -> Path:
    config.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    name = time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3) + "." + ext
    path = config.UPLOAD_DIR / name
    path.write_bytes(data)
    return path

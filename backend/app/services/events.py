"""「有東西變了」的版本號。手機的即時更新串流（SSE）盯著它，變了就叫手機重抓。

刻意只送「變了」不送內容：內容永遠從 /api/sessions 拿，只有一條真相。
"""

import threading

_lock = threading.Lock()
_version = 0


def bump() -> None:
    global _version
    with _lock:
        _version += 1


def version() -> int:
    return _version

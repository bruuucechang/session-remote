"""iTerm2 的腳本介面（AppleScript）。

為什麼是 iTerm2 不是 Terminal.app：iTerm2 的 `write text` 能把字送進**背景**的分頁，
不會把視窗拉到前面（2026-10-16 實測，前景 app 全程不變）。Terminal.app 只能模擬鍵盤，
一定會搶畫面。

字串一律走 argv 傳進 AppleScript，不拼進腳本原文——拼的話引號與反斜線要自己跳脫，
漏一個就是把使用者的字變成 AppleScript 語法錯誤。
"""

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

TIMEOUT = 10
# 啟動會開視窗的程式又不搶畫面（見 skills 的 tools/bgrun 檔頭）
BGRUN = Path.home() / ".claude/skills/home/claude/tools/bgrun"


class ItermError(RuntimeError):
    pass


@dataclass
class ItermSession:
    id: str
    tty: str
    name: str


def _osa(script: str, *args: str) -> str:
    try:
        r = subprocess.run(["osascript", "-e", script, *args], capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as e:
        # 最常見的成因：iTerm2 卡在一個對話框上（第一次啟動的語系提示就是這樣）
        raise ItermError("iTerm2 沒回應（可能卡在對話框）") from e
    if r.returncode != 0:
        raise ItermError(r.stderr.strip() or "osascript 失敗")
    return r.stdout.rstrip("\n")


def is_running() -> bool:
    r = subprocess.run(["pgrep", "-x", "iTerm2"], capture_output=True)
    return r.returncode == 0


# 注意：在 tell iTerm2 裡面 `tab` 是 iTerm2 的「分頁」類別，不是 tab 字元，所以先在外面存起來
_LIST = '''
set out to ""
set sep to (ASCII character 9)
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set out to out & (id of s) & sep & (tty of s) & sep & (name of s) & linefeed
      end repeat
    end repeat
  end repeat
end tell
return out
'''


def list_sessions() -> list[ItermSession]:
    # iTerm2 沒開時不要叫它——AppleScript 會把它啟動起來
    if not is_running():
        return []
    out = _osa(_LIST)
    sessions = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and parts[1].startswith("/dev/"):
            sessions.append(ItermSession(id=parts[0], tty=parts[1], name="\t".join(parts[2:])))
    return sessions


_FIND = '''
on run argv
  set sid to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is sid then
            %s
          end if
        end repeat
      end repeat
    end repeat
  end tell
  error "找不到 iTerm2 分頁 " & sid
end run
'''


def write(session_id: str, text: str) -> None:
    """原樣送字，不加換行。"""
    _osa(_FIND % 'tell s to write text (item 2 of argv) newline NO\n            return ""', session_id, text)


def write_ascii(session_id: str, code: int) -> None:
    _osa(_FIND % f'tell s to write text (ASCII character {code}) newline NO\n            return ""', session_id)


def write_seq(session_id: str, seq: str) -> None:
    """ESC 開頭的控制序列（方向鍵等）：ESC 與後半段要放在同一次 write，分開送會被當成單獨的 Esc。"""
    _osa(_FIND % 'tell s to write text ((ASCII character 27) & (item 2 of argv)) newline NO\n            return ""', session_id, seq)


def close(session_id: str) -> None:
    """關掉這個分頁（裡面只剩 shell 時用；還有程式在跑的話 iTerm2 可能跳確認框）。"""
    _osa(_FIND % 'close s\n            return ""', session_id)


def contents(session_id: str) -> str:
    return _osa(_FIND % "return contents of s", session_id)


_NEW = '''
on run argv
  tell application "iTerm2"
    -- iTerm2 被隱藏或不在前面時 current window 是 missing value，所以用 first window
    if (count of windows) is 0 then
      set s to current session of (create window with default profile)
    else
      tell first window to set t to (create tab with default profile)
      set s to current session of t
    end if
    delay 0.5
    tell s to write text (item 1 of argv)
    return (id of s)
  end tell
end run
'''


def new_tab(command: str) -> str:
    """開一個新分頁跑指令，回傳分頁 id。iTerm2 沒開的話先在背景開。"""
    if not is_running():
        subprocess.Popen(
            [str(BGRUN), "/Applications/iTerm.app/Contents/MacOS/iTerm2"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
        for _ in range(30):
            time.sleep(0.5)
            if is_running():
                break
        time.sleep(2)
    prev = _frontmost()
    sid = _osa(_NEW, command)
    # iTerm2 開新視窗／分頁會把自己拉到最前面（2026-10-16 實測，前一刻 iTerm2 被隱藏時才不會）。
    # 原本在前面的不是 iTerm2 的話就切回去——跟 skills 的 tools/bgrun 同一招（Apple Event activate）。
    if prev and prev != "com.googlecode.iterm2":
        time.sleep(0.3)
        _restore(prev)
    return sid


def _frontmost() -> str:
    try:
        return subprocess.run(
            ["osascript", "-l", "JavaScript", "-e",
             'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js'],
            capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


def _restore(bundle_id: str) -> None:
    try:
        subprocess.run(["osascript", "-l", "JavaScript", "-e", f"Application({bundle_id!r}).activate()"],
                       capture_output=True, timeout=5)
    except Exception:
        pass

"""tools/install_hooks.py：重跑不重複加、保留使用者原本的 hook、有備份。"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "install_hooks.py"


def _run(settings: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--settings", str(settings), *extra],
                          capture_output=True, text=True, check=True)


def _count(settings: Path) -> int:
    d = json.loads(settings.read_text())
    return sum("report.mjs" in h["command"] for gs in d["hooks"].values() for g in gs for h in g["hooks"])


def test_new_file_twice_adds_once(tmp_path):
    s = tmp_path / "settings.json"
    _run(s)
    _run(s)
    assert _count(s) == 7
    assert not list(tmp_path.glob("settings.json.bak-*"))  # 原本沒有檔案，沒東西可備份


def test_keeps_existing_and_backs_up(tmp_path):
    s = tmp_path / "settings.json"
    mine = {"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo hi"}]}]}}
    s.write_text(json.dumps(mine))
    _run(s)
    d = json.loads(s.read_text())
    assert d["model"] == "x"
    assert d["hooks"]["Stop"][0]["hooks"][0]["command"] == "echo hi"
    assert _count(s) == 7
    assert len(list(tmp_path.glob("settings.json.bak-*"))) == 1
    _run(s)  # 第二次什麼都不加，也不再備份
    assert _count(s) == 7
    assert len(list(tmp_path.glob("settings.json.bak-*"))) == 1


def test_dry_run_writes_nothing(tmp_path):
    s = tmp_path / "settings.json"
    out = _run(s, "--dry-run").stdout
    assert "試跑" in out
    assert not s.exists()


def test_non_default_port_is_passed(tmp_path):
    s = tmp_path / "settings.json"
    _run(s, "--port", "5400")
    d = json.loads(s.read_text())
    assert d["hooks"]["Stop"][0]["hooks"][0]["command"].endswith("Stop 5400")


def test_rerun_with_new_port_updates_managed_hooks(tmp_path):
    s = tmp_path / "settings.json"
    _run(s)
    _run(s, "--port", "5400")
    d = json.loads(s.read_text())
    assert _count(s) == 7
    assert all(h["command"].endswith(" 5400") for gs in d["hooks"].values() for g in gs for h in g["hooks"])


def test_foreign_report_hook_is_left_alone(tmp_path):
    s = tmp_path / "settings.json"
    theirs = 'node "$HOME/ext.mjs" "$HOME/Projects/session-remote/hooks/report.mjs" Stop'
    s.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": theirs}]}]}}))
    _run(s, "--port", "5400")
    d = json.loads(s.read_text())
    assert d["hooks"]["Stop"][0]["hooks"][0]["command"] == theirs
    assert len(d["hooks"]["Stop"]) == 1

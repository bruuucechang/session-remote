"""開新 session 時可選的資料夾：~/Projects 底下的目錄。"""

from .. import config


def list_dirs() -> list[str]:
    root = config.PROJECTS_ROOT
    try:
        return sorted(
            (str(p) for p in root.iterdir() if p.is_dir() and not p.name.startswith(".")),
            key=lambda s: s.lower(),
        )
    except FileNotFoundError:
        return []

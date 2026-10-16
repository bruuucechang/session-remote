#!/usr/bin/env python3
"""文件裡引用的數字，一個指令全部重跑。

存在的理由：寫在文件裡的數字不會自己更新，而底下的東西一直在動。
**文件上的數字跟這支的輸出對不上，它就是過期的** —— 不一定當初錯，
是現在不該再引用。新增一個會被寫進文件的數字，就在這裡加一行。

    python3 tools/vitals.py
"""
import pathlib, subprocess, glob

ROOT = pathlib.Path(__file__).resolve().parent.parent


def lines(pattern):
    return sum(len(open(p, encoding="utf-8", errors="ignore").readlines())
               for p in glob.glob(str(ROOT / pattern), recursive=True))


def count(pattern):
    return len(glob.glob(str(ROOT / pattern), recursive=True))


print(f"# session-remote vitals")
print()
print(f"{'測試檔':<22}{count('backend/tests/test_*.py') + count('frontend/**/*.test.ts*'):>8}")
print(f"{'routers':<22}{count('backend/app/routers/*.py') - 1:>8}")
print(f"{'services':<22}{count('backend/app/services/*.py') - 1:>8}")
print(f"{'repositories':<22}{count('backend/app/repositories/*.py') - 1:>8}")
print(f"{'backend 行數':<20}{lines('backend/app/**/*.py'):>8}")
print(f"{'frontend 行數':<19}{lines('frontend/src/**/*.ts*'):>8}")
print(f"{'AGENTS.md 行數':<19}{lines('AGENTS.md'):>8}   （官方目標 200 以內）")
print(f"{'notebook 行數':<20}{lines('docs/notebook.md'):>8}   （這一份不進 context）")

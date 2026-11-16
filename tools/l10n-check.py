#!/usr/bin/env python3
"""英文介面（B8）的字串核對：拿編譯器抽出來的字串（SWIFT_EMIT_LOC_STRINGS=YES 產的 .stringsdata）比對原始碼。

  tools/l10n-check.py            # 核對：①有中文字串卻沒被抽到的行（=不會翻）②目錄裡缺英文的字串
  tools/l10n-check.py --sync     # 把抽到、目錄裡還沒有的字串補進 ios/Resources/Localizable.xcstrings（英文留空）
要先 build：cd ios && xcodebuild ... -derivedDataPath build/dd SWIFT_EMIT_LOC_STRINGS=YES build
刻意不翻的行（log、送給 Claude 的字、比對 Claude Code 原文用的）在行尾寫 `// l10n:skip`。
"""
import json, re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
CAT = IOS / "Resources" / "Localizable.xcstrings"
CJK = re.compile(r'"[^"\n]*[一-鿿（-？、-』][^"\n]*"')

def extracted():
    keys, lines = set(), set()
    for f in (IOS / "build" / "dd").rglob("*.stringsdata"):
        d = json.loads(f.read_text())
        src = d.get("source", "")
        for e in d.get("tables", {}).get("Localizable", []):
            keys.add(e["key"])
            lines.add((src, e["location"]["startingLine"]))
    return keys, lines

def server_keys():
    """後端回給手機顯示的中文：app 用 serverText() 查目錄。f-string 只取到「：」為止的前綴。"""
    keys = {"已中斷", "計畫寫好了，等你核准"}
    pat = re.compile(r'(?:BadRequest|ItermError|HTTPException\(\d+,)\s*\(?\s*(f?)"([^"]*[\u4e00-\u9fff][^"]*)"|"detail": "([^"]+)"')
    for f in (ROOT / "backend" / "app").rglob("*.py"):
        for m in pat.finditer(f.read_text()):
            text = m.group(2) or m.group(3)
            if m.group(1) == "f":
                text = text.split("{")[0]
                if not text.endswith("："):
                    continue
            keys.add(text)
    return keys

def main():
    keys, lines = extracted()
    if not keys:
        sys.exit("✗ 找不到 .stringsdata：先帶 SWIFT_EMIT_LOC_STRINGS=YES build")
    cat = json.loads(CAT.read_text()) if CAT.exists() else {"sourceLanguage": "zh-Hant", "strings": {}, "version": "1.0"}
    keys |= server_keys()
    if "--sync" in sys.argv:
        for k in sorted(keys):
            cat["strings"].setdefault(k, {})
        CAT.parent.mkdir(parents=True, exist_ok=True)
        CAT.write_text(json.dumps(cat, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        print(f"目錄 {len(cat['strings'])} 條")
    bad = 0
    for sub in ("Sources", "Shared", "Widgets"):
        for p in sorted((IOS / sub).rglob("*.swift")):
            for i, line in enumerate(p.read_text().splitlines(), 1):
                code = line.split("//")[0] if "l10n:skip" not in line else ""
                if CJK.search(code) and (str(p), i) not in lines:
                    print(f"不會翻  {p.relative_to(ROOT)}:{i}  {line.strip()[:100]}"); bad += 1
    for k in sorted(keys):
        if not re.search(r"[一-鿿]", k):
            continue
        en = cat["strings"].get(k, {}).get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
        if not en:
            print(f"缺英文  {k}"); bad += 1
    print("✓ 字串都會翻" if not bad else f"✗ {bad} 處")
    sys.exit(1 if bad else 0)

main()

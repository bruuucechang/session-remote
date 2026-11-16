#!/usr/bin/env bash
# 展示模式假資料的行為檢查（不用模擬器）：swiftc 把 API.swift＋DemoBackend.swift 編成 mac 小程式跑。
#   tools/demo-check.sh      全過 exit 0
# 目前檢查：中斷後 2.5 秒內再送一句，回覆的是新的那句（舊的延遲完工不准搶走，PR #30 Codex 審查）
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/main.swift" <<'SWIFT'
import Foundation
@MainActor func run() async -> Bool {
    let d = DemoBackend()
    try! d.reply("demo-blog", text: "first")
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    try! d.interrupt("demo-blog")
    try! d.reply("demo-blog", text: "second")
    try? await Task.sleep(nanoseconds: 3_200_000_000)
    let msgs = try! d.session("demo-blog").messages.map(\.text)
    let ok = msgs.last?.contains("second") == true
    print(ok ? "PASS" : "FAIL", msgs.suffix(2))
    return ok
}
Task { @MainActor in exit(await run() ? 0 : 1) }
RunLoop.main.run()
SWIFT
xcrun swiftc -o "$T/t" "$DIR/ios/Sources/API.swift" "$DIR/ios/Sources/DemoBackend.swift" "$DIR/ios/Shared/L10n.swift" "$T/main.swift"
"$T/t"

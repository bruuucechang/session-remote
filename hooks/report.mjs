#!/usr/bin/env node
// report.mjs — Claude Code hook：把事件原封不動轉給筆電上的 session-remote 服務。
//
// settings.json 裡一律 async 掛，用法：node report.mjs <事件名>
//   SessionStart / UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SessionEnd
//
// 這支只負責「送出去」，不判斷狀態——狀態機在 backend/app/services/sessions.py。
// 服務沒在跑、逾時、任何錯誤都吞掉：這支壞掉不能擋到 Claude Code。
//
// tty 依 Claude 的 pid 快取（2026-10-20，skills repo 的 hooks/optimize-spec.md H4）：
// 以前每次工具呼叫前後各跑一次、每次最多 12 次 `ps`；現在同一個 session 只有第一次查。
// 快取鍵是父程序 pid，另外比對 session_id 防 pid 被重用（/clear 換 session 就重查一次）。
// 這要求 settings.json 直接掛 node、不包一層 shell，不然父程序每次都是新的 shell、永遠不中。
// 量 ps 次數：PATH 前面放一支會記帳的假 ps，見 optimize-spec.md 附錄 E。
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const EVENT = process.argv[2] || "";
const URL = `http://127.0.0.1:${process.env.SESSION_REMOTE_PORT || 5391}/hook`;

function ps(field, pid) {
  return execFileSync("ps", ["-o", `${field}=`, "-p", String(pid)], { encoding: "utf8" }).trim();
}

// hook 是 claude 的子程序（中間可能隔一層 shell）：往上找第一個有 tty 的祖先。
// 路上先碰到一個沒有 tty 的 claude，就是被別人的 Bash 工具或腳本叫起來的 `claude -p`：
// 再往上會找到外層 session 的 tty，冒名送出去會蓋掉外層那筆，所以不送
function findTty() {
  let pid = process.ppid;
  for (let i = 0; i < 6 && pid > 1; i++) {
    const tty = ps("tty", pid);
    if (tty && tty !== "??") return { tty: tty.startsWith("/dev/") ? tty : `/dev/${tty}`, pid };
    if (/(^|\/)claude(\s|$)|\/claude\/versions\//.test(ps("comm", pid))) break;
    pid = Number(ps("ppid", pid));
  }
  return { tty: null, pid: null };
}

const CACHE_DIR = join(tmpdir(), "session-remote-tty");

function cachedTty(sid) {
  const file = join(CACHE_DIR, `${process.ppid}.json`);
  try {
    const c = JSON.parse(readFileSync(file, "utf8"));
    if (c.sid === sid && c.tty) return { tty: c.tty, pid: c.pid };
  } catch {}
  const found = findTty();
  // 沒找到 tty 不快取：下次再查。寫新的那一次順便清掉程序已經不在的
  if (found.tty) {
    try {
      mkdirSync(CACHE_DIR, { recursive: true });
      writeFileSync(file, JSON.stringify({ sid, ...found }));
      for (const f of readdirSync(CACHE_DIR)) {
        try { process.kill(Number.parseInt(f, 10), 0); } catch (e) { if (e.code === "ESRCH") rmSync(join(CACHE_DIR, f), { force: true }); }
      }
    } catch {}
  }
  return found;
}

try {
  let payload = {};
  try { payload = JSON.parse(readFileSync(0, "utf8") || "{}"); } catch {}
  const { tty, pid } = cachedTty(payload?.session_id || "");
  await fetch(URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      event: EVENT,
      tty,
      pid,
      config_dir: process.env.CLAUDE_CONFIG_DIR || "",
      payload,
    }),
    signal: AbortSignal.timeout(1500),
  });
} catch {}

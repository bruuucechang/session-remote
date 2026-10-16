#!/usr/bin/env node
// report.mjs — Claude Code hook：把事件原封不動轉給筆電上的 session-remote 服務。
//
// settings.json 裡一律 async 掛，用法：node report.mjs <事件名>
//   SessionStart / UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SessionEnd
//
// 這支只負責「送出去」，不判斷狀態——狀態機在 backend/app/services/sessions.py。
// 服務沒在跑、逾時、任何錯誤都吞掉：這支壞掉不能擋到 Claude Code。
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const EVENT = process.argv[2] || "";
const URL = `http://127.0.0.1:${process.env.SESSION_REMOTE_PORT || 5391}/hook`;

function ps(field, pid) {
  return execFileSync("ps", ["-o", `${field}=`, "-p", String(pid)], { encoding: "utf8" }).trim();
}

// hook 是 claude 的子程序（中間可能隔一層 shell）：往上找第一個有 tty 的祖先
function findTty() {
  let pid = process.ppid;
  for (let i = 0; i < 6 && pid > 1; i++) {
    const tty = ps("tty", pid);
    if (tty && tty !== "??") return { tty: tty.startsWith("/dev/") ? tty : `/dev/${tty}`, pid };
    pid = Number(ps("ppid", pid));
  }
  return { tty: null, pid: null };
}

try {
  let payload = {};
  try { payload = JSON.parse(readFileSync(0, "utf8") || "{}"); } catch {}
  const { tty, pid } = findTty();
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

// Child processes for the external tools: async spawn with a timeout, and a small concurrency limiter.
import { spawn } from "node:child_process";

export function run(cmd, args, { timeout = 300000, cwd, env } = {}) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    let out = "", err = "", done = false;
    const p = spawn(cmd, args, { cwd, env: env ? { ...process.env, ...env } : process.env, windowsHide: true });
    const timer = setTimeout(() => { if (!done) { try { p.kill(); } catch {} } }, timeout);
    p.stdout.on("data", (d) => { if (out.length < 32 << 20) out += d; });
    p.stderr.on("data", (d) => { if (err.length < 4 << 20) err += d; });
    p.on("error", (e) => { done = true; clearTimeout(timer); resolve({ code: -1, out, err: String(e.message), ms: performance.now() - t0, spawnError: true }); });
    p.on("close", (code, signal) => { done = true; clearTimeout(timer); resolve({ code, signal, out, err, ms: performance.now() - t0 }); });
  });
}

/** Runs `tasks` (functions returning promises) with at most `n` in flight; results in order. */
export async function limit(n, tasks) {
  const results = new Array(tasks.length);
  let next = 0;
  const worker = async () => { while (next < tasks.length) { const i = next++; results[i] = await tasks[i](); } };
  await Promise.all(Array.from({ length: Math.min(n, tasks.length) }, worker));
  return results;
}

export const lines = (s) => String(s || "").split(/\r?\n/).map((l) => l.trimEnd()).filter((l) => l.trim());

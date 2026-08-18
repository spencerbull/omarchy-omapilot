import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { delimiter, isAbsolute } from "node:path";

export type RunResult = { code: number; stdout: string; stderr: string };
export type RunBinaryResult = { code: number; stdout: Buffer; stderr: string };

export function launchDetached(
  executable: string,
  args: string[],
  options: { env?: NodeJS.ProcessEnv; cwd?: string } = {}
): Promise<boolean> {
  return new Promise((resolveLaunch) => {
    let settled = false;
    const finish = (opened: boolean): void => {
      if (settled) return;
      settled = true;
      resolveLaunch(opened);
    };
    const child = spawn(executable, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: "ignore",
      detached: process.platform !== "win32"
    });
    child.once("error", () => finish(false));
    child.once("spawn", () => {
      child.unref();
      finish(true);
    });
  });
}

export async function runCommand(
  executable: string,
  args: string[],
  options: { env?: NodeJS.ProcessEnv; cwd?: string; timeoutMs?: number; maxOutput?: number } = {}
): Promise<RunResult> {
  const maxOutput = options.maxOutput ?? 1_000_000;
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: process.platform !== "win32"
    });
    let stdout = "";
    let stderr = "";
    const append = (current: string, chunk: Buffer): string => (current + chunk.toString("utf8")).slice(-maxOutput);
    child.stdout.on("data", (chunk: Buffer) => { stdout = append(stdout, chunk); });
    child.stderr.on("data", (chunk: Buffer) => { stderr = append(stderr, chunk); });
    child.once("error", reject);
    const timer = setTimeout(() => {
      terminateProcessGroup(child.pid);
    }, options.timeoutMs ?? 10_000);
    timer.unref();
    child.once("close", (code) => {
      clearTimeout(timer);
      resolve({ code: code ?? 1, stdout, stderr });
    });
  });
}

export async function runBinaryCommand(
  executable: string,
  args: string[],
  options: { env?: NodeJS.ProcessEnv; cwd?: string; timeoutMs?: number; maxOutput?: number } = {}
): Promise<RunBinaryResult> {
  const maxOutput = options.maxOutput ?? 8 * 1024 * 1024;
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: process.platform !== "win32"
    });
    const chunks: Buffer[] = [];
    let bytes = 0;
    let stderr = "";
    let exceeded = false;
    child.stdout.on("data", (chunk: Buffer) => {
      if (exceeded) return;
      bytes += chunk.byteLength;
      if (bytes > maxOutput) {
        exceeded = true;
        terminateProcessGroup(child.pid);
        return;
      }
      chunks.push(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk.toString("utf8")).slice(-32_768);
    });
    child.once("error", reject);
    const timer = setTimeout(() => terminateProcessGroup(child.pid), options.timeoutMs ?? 10_000);
    timer.unref();
    child.once("close", (code) => {
      clearTimeout(timer);
      resolve({ code: exceeded ? 1 : (code ?? 1), stdout: Buffer.concat(chunks), stderr });
    });
  });
}

export function terminateProcessGroup(pid: number | undefined): void {
  if (pid === undefined) return;
  try {
    process.kill(process.platform === "win32" ? pid : -pid, "SIGTERM");
  } catch {
    // The process may already have exited.
  }
  const timer = setTimeout(() => {
    try {
      process.kill(process.platform === "win32" ? pid : -pid, "SIGKILL");
    } catch {
      // The process may already have exited.
    }
  }, 2_000);
  timer.unref();
}

async function executableFile(candidate: string): Promise<boolean> {
  try {
    await access(candidate, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export async function resolveExecutable(name: string, env: NodeJS.ProcessEnv = process.env): Promise<string | undefined> {
  const mise = await resolveFromPath("mise", env);
  if (mise !== undefined) {
    const result = await runCommand(mise, ["which", name], { env, timeoutMs: 5_000, maxOutput: 16_384 });
    const candidate = result.stdout.trim().split("\n")[0];
    if (result.code === 0 && candidate !== undefined && isAbsolute(candidate) && await executableFile(candidate)) return candidate;
  }
  return resolveFromPath(name, env);
}

async function resolveFromPath(name: string, env: NodeJS.ProcessEnv): Promise<string | undefined> {
  for (const directory of (env.PATH ?? "").split(delimiter)) {
    if (directory.length === 0) continue;
    const candidate = `${directory}/${name}`;
    if (await executableFile(candidate)) return candidate;
  }
  return undefined;
}

export function stripAnsi(value: string): string {
  return value.replaceAll(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
}

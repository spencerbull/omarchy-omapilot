import { spawn, type ChildProcess } from "node:child_process";
import { mkdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { omapilotPaths, type OmaPilotPaths } from "./paths.js";
import { resolveExecutable, runCommand, terminateProcessGroup } from "./process.js";

const METER_INTERVAL_MS = 33;
const MAX_METER_BUFFER_BYTES = 16 * 1024;

export type DictationLevelObserver = {
  level: (level: number | null) => void;
};

export type DictationServiceOptions = {
  resolveAudioBridge?: () => Promise<string | undefined>;
};

export class DictationService {
  readonly #paths: OmaPilotPaths;
  readonly #env: NodeJS.ProcessEnv;
  readonly #resolveAudioBridge: () => Promise<string | undefined>;
  #voxtype: string | undefined;
  #transcript: string;
  #generation = 0;
  #operation: Promise<void> = Promise.resolve();
  #meterProcess: ChildProcess | undefined;
  #meterObserver: DictationLevelObserver | undefined;
  #meterBuffer = "";
  #meterPeak = 0;
  #meterLevel = 0;
  #meterLastEmit = 0;
  #meterTimer: NodeJS.Timeout | undefined;

  constructor(
    paths: OmaPilotPaths = omapilotPaths(),
    env: NodeJS.ProcessEnv = process.env,
    options: DictationServiceOptions = {}
  ) {
    this.#paths = paths;
    this.#env = env;
    this.#transcript = join(paths.runtime, "dictation.txt");
    this.#resolveAudioBridge = options.resolveAudioBridge
      ?? (() => resolveExecutable("voxtype-audio-bridge", this.#env));
  }

  async available(): Promise<boolean> {
    this.#voxtype ??= await resolveExecutable("voxtype", this.#env);
    if (this.#voxtype === undefined) return false;
    const result = await runCommand(this.#voxtype, ["status", "--format", "json"], { env: this.#env, timeoutMs: 3_000, maxOutput: 16_384 });
    return result.code === 0;
  }

  start(observer?: DictationLevelObserver): Promise<void> {
    return this.#serialize(() => this.#start(observer));
  }

  async #start(observer?: DictationLevelObserver): Promise<void> {
    const generation = ++this.#generation;
    const [available, audioBridge] = await Promise.all([
      this.available(),
      observer === undefined
        ? Promise.resolve(undefined)
        : this.#resolveAudioBridge().catch(() => undefined)
    ]);
    if (!available || this.#voxtype === undefined) throw new Error("Voxtype is not ready");
    if (generation !== this.#generation) throw new DictationCancelledError();
    await mkdir(this.#paths.runtime, { recursive: true, mode: 0o700 });
    await rm(this.#transcript, { force: true });
    if (observer !== undefined && audioBridge !== undefined)
      this.#startMeter(audioBridge, observer);
    let result;
    try {
      result = await runCommand(this.#voxtype, dictationStartArgs(this.#transcript), { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
    } catch (error) {
      this.#stopMeter();
      throw error;
    }
    if (result.code !== 0) {
      this.#stopMeter();
      throw new Error("Voxtype could not start recording");
    }
    if (generation !== this.#generation) {
      this.#stopMeter();
      await runCommand(this.#voxtype, ["record", "cancel"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
      throw new DictationCancelledError();
    }
  }

  stop(timeoutMs = 60_000): Promise<string> {
    this.#stopMeter();
    return this.#serialize(() => this.#stop(timeoutMs));
  }

  async #stop(timeoutMs: number): Promise<string> {
    this.#stopMeter();
    const generation = this.#generation;
    if (this.#voxtype === undefined) throw new Error("Voxtype is not recording");
    const result = await runCommand(this.#voxtype, ["record", "stop"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
    if (result.code !== 0) throw new Error("Voxtype could not stop recording");
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (generation !== this.#generation) throw new DictationCancelledError();
      try {
        const text = (await readFile(this.#transcript, "utf8")).trim();
        if (text !== "") { await rm(this.#transcript, { force: true }); return text; }
      } catch {
        // The transcript is written only after transcription completes.
      }
      if (await this.#transcriptionFinished()) {
        await rm(this.#transcript, { force: true });
        return "";
      }
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 150));
    }
    throw new Error("Voxtype transcription timed out");
  }

  async #transcriptionFinished(): Promise<boolean> {
    if (this.#voxtype === undefined) return false;
    const result = await runCommand(this.#voxtype, ["status", "--format", "json"], {
      env: this.#env,
      timeoutMs: 3_000,
      maxOutput: 16_384
    });
    if (result.code !== 0) return false;
    try {
      const status = JSON.parse(result.stdout) as { alt?: unknown };
      return status !== null && typeof status === "object" && status.alt === "idle";
    } catch {
      return false;
    }
  }

  cancel(): Promise<void> {
    this.#generation += 1;
    this.#stopMeter();
    return this.#serialize(() => this.#cancel());
  }

  async #cancel(): Promise<void> {
    if (this.#voxtype !== undefined) await runCommand(this.#voxtype, ["record", "cancel"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
    await rm(this.#transcript, { force: true });
  }

  #startMeter(executable: string, observer: DictationLevelObserver): void {
    this.#stopMeter(false);
    this.#meterObserver = observer;
    const child = spawn(executable, [], {
      env: this.#env,
      stdio: ["ignore", "pipe", "ignore"],
      detached: process.platform !== "win32"
    });
    this.#meterProcess = child;
    child.stdout?.on("data", (chunk: Buffer) => this.#readMeterData(chunk));
    child.once("error", () => this.#meterExited(child));
    child.once("close", () => this.#meterExited(child));
  }

  #readMeterData(chunk: Buffer): void {
    this.#meterBuffer += chunk.toString("utf8");
    let newline = this.#meterBuffer.indexOf("\n");
    while (newline >= 0) {
      const line = this.#meterBuffer.slice(0, newline).trim();
      this.#meterBuffer = this.#meterBuffer.slice(newline + 1);
      this.#readMeterLine(line);
      newline = this.#meterBuffer.indexOf("\n");
    }
    if (Buffer.byteLength(this.#meterBuffer, "utf8") > MAX_METER_BUFFER_BYTES)
      this.#meterBuffer = "";
  }

  #readMeterLine(line: string): void {
    if (line === "") return;
    let value: unknown;
    try { value = JSON.parse(line); }
    catch { return; }
    if (typeof value !== "object" || value === null || Array.isArray(value)) return;
    const frame = value as { status?: unknown; peak?: unknown };
    if (frame.status === "disconnected") {
      this.#resetMeter();
      this.#meterObserver?.level(null);
      return;
    }
    if (typeof frame.peak !== "number" || !Number.isFinite(frame.peak)) return;
    this.#meterPeak = Math.max(this.#meterPeak, Math.max(0, Math.min(1, frame.peak)));
    const elapsed = Date.now() - this.#meterLastEmit;
    if (this.#meterLastEmit === 0 || elapsed >= METER_INTERVAL_MS) {
      this.#flushMeter();
    } else if (this.#meterTimer === undefined) {
      this.#meterTimer = setTimeout(() => this.#flushMeter(), METER_INTERVAL_MS - elapsed);
      this.#meterTimer.unref();
    }
  }

  #flushMeter(): void {
    if (this.#meterTimer !== undefined) clearTimeout(this.#meterTimer);
    this.#meterTimer = undefined;
    const peak = this.#meterPeak;
    this.#meterPeak = 0;
    const weight = peak >= this.#meterLevel ? 0.72 : 0.28;
    this.#meterLevel += (peak - this.#meterLevel) * weight;
    this.#meterLastEmit = Date.now();
    this.#meterObserver?.level(this.#meterLevel);
  }

  #meterExited(child: ChildProcess): void {
    if (this.#meterProcess !== child) return;
    this.#meterProcess = undefined;
    const observer = this.#meterObserver;
    this.#meterObserver = undefined;
    this.#resetMeter();
    observer?.level(null);
  }

  #resetMeter(): void {
    if (this.#meterTimer !== undefined) clearTimeout(this.#meterTimer);
    this.#meterTimer = undefined;
    this.#meterBuffer = "";
    this.#meterPeak = 0;
    this.#meterLevel = 0;
    this.#meterLastEmit = 0;
  }

  #stopMeter(notify = true): void {
    const child = this.#meterProcess;
    const observer = this.#meterObserver;
    this.#meterProcess = undefined;
    this.#meterObserver = undefined;
    this.#resetMeter();
    if (child !== undefined) terminateProcessGroup(child.pid);
    if (notify) observer?.level(null);
  }

  #serialize<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.#operation.then(operation, operation);
    this.#operation = result.then(() => undefined, () => undefined);
    return result;
  }
}

export class DictationCancelledError extends Error {
  constructor() {
    super("Dictation was cancelled");
    this.name = "DictationCancelledError";
  }
}

export function dictationStartArgs(transcript: string): string[] {
  return ["record", "start", `--file=${transcript}`, "--no-auto-submit", "--no-smart-auto-submit"];
}

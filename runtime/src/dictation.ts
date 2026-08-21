import { mkdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { quickchatPaths, type QuickchatPaths } from "./paths.js";
import { resolveExecutable, runCommand } from "./process.js";

export class DictationService {
  readonly #paths: QuickchatPaths;
  readonly #env: NodeJS.ProcessEnv;
  #voxtype: string | undefined;
  #transcript: string;
  #generation = 0;
  #operation: Promise<void> = Promise.resolve();
  // Whether this Voxtype speaks `record stop --wait`. Probed once, because the
  // flag is not tied to a release the way a version check would assume.
  #waitSupported: boolean | undefined;

  constructor(paths: QuickchatPaths = quickchatPaths(), env: NodeJS.ProcessEnv = process.env) {
    this.#paths = paths;
    this.#env = env;
    this.#transcript = join(paths.runtime, "dictation.txt");
  }

  async available(): Promise<boolean> {
    this.#voxtype ??= await resolveExecutable("voxtype", this.#env);
    if (this.#voxtype === undefined) return false;
    const result = await runCommand(this.#voxtype, ["status", "--format", "json"], { env: this.#env, timeoutMs: 3_000, maxOutput: 16_384 });
    return result.code === 0;
  }

  start(): Promise<void> {
    return this.#serialize(() => this.#start());
  }

  async #start(): Promise<void> {
    const generation = ++this.#generation;
    if (!await this.available() || this.#voxtype === undefined) throw new Error("Voxtype is not ready");
    if (generation !== this.#generation) throw new DictationCancelledError();
    await mkdir(this.#paths.runtime, { recursive: true, mode: 0o700 });
    await rm(this.#transcript, { force: true });
    const result = await runCommand(this.#voxtype, dictationStartArgs(this.#transcript), { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
    if (result.code !== 0) throw new Error("Voxtype could not start recording");
    if (generation !== this.#generation) {
      await runCommand(this.#voxtype, ["record", "cancel"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
      throw new DictationCancelledError();
    }
  }

  stop(timeoutMs = 60_000): Promise<string> {
    return this.#serialize(() => this.#stop(timeoutMs));
  }

  // Does this Voxtype support `record stop --wait`?
  //
  // Older builds have no completion signal at all, so they need the polling
  // path below. Probed once per resolved binary.
  async #supportsWait(): Promise<boolean> {
    if (this.#waitSupported !== undefined) return this.#waitSupported;
    if (this.#voxtype === undefined) return false;
    const help = await runCommand(this.#voxtype, ["record", "stop", "--help"], { env: this.#env, timeoutMs: 5_000, maxOutput: 65_536 });
    this.#waitSupported = help.code === 0 && help.stdout.includes("--wait");
    return this.#waitSupported;
  }

  async #stop(timeoutMs: number): Promise<string> {
    const voxtype = this.#voxtype;
    if (voxtype === undefined) throw new Error("Voxtype is not recording");
    return await this.#supportsWait() ? this.#stopAndWait(voxtype, timeoutMs) : this.#stopAndPoll(voxtype, timeoutMs);
  }

  // One call that returns when the transcript is final.
  //
  // It distinguishes "nothing was said" from "still working", which polling
  // cannot: when voice-activity detection finds no speech, nothing is ever
  // written, and the poll below can only wait out its own deadline.
  async #stopAndWait(voxtype: string, timeoutMs: number): Promise<string> {
    const generation = this.#generation;
    const seconds = Math.max(1, Math.ceil(timeoutMs / 1_000));
    const result = await runCommand(
      voxtype,
      ["record", "stop", "--wait", "--json", "--timeout", String(seconds), "--wait-file", this.#transcript],
      // Give the CLI room to report its own timeout rather than being killed first.
      { env: this.#env, timeoutMs: timeoutMs + 5_000, maxOutput: 1_000_000 }
    );
    if (generation !== this.#generation) throw new DictationCancelledError();
    await rm(this.#transcript, { force: true });

    let outcome: { status?: string; text?: string; message?: string } = {};
    try {
      outcome = JSON.parse(result.stdout.trim()) as typeof outcome;
    } catch {
      throw new Error(`Voxtype returned an unreadable result: ${result.stderr.trim() || result.stdout.trim()}`);
    }

    switch (outcome.status) {
      case "ok": return (outcome.text ?? "").trim();
      case "empty": throw new Error("Voxtype heard nothing to transcribe");
      case "timeout": throw new Error("Voxtype transcription timed out");
      default: throw new Error(`Voxtype could not transcribe: ${outcome.message ?? "unknown error"}`);
    }
  }

  // Voxtype without `--wait`: no completion signal, so poll for the transcript.
  async #stopAndPoll(voxtype: string, timeoutMs: number): Promise<string> {
    const generation = this.#generation;
    const result = await runCommand(voxtype, ["record", "stop"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
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
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 150));
    }
    throw new Error("Voxtype transcription timed out");
  }

  cancel(): Promise<void> {
    this.#generation += 1;
    return this.#serialize(() => this.#cancel());
  }

  async #cancel(): Promise<void> {
    if (this.#voxtype !== undefined) await runCommand(this.#voxtype, ["record", "cancel"], { env: this.#env, timeoutMs: 5_000, maxOutput: 16_384 });
    await rm(this.#transcript, { force: true });
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

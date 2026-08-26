import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { DictationCancelledError, DictationService, dictationStartArgs } from "../src/dictation.js";
import { omapilotPaths } from "../src/paths.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("Voxtype contract", () => {
  it("uses per-recording file output without simulated typing or configuration writes", () => {
    const transcript = "/run/user/1000/omapilot/dictation.txt";
    const args = dictationStartArgs(transcript);
    expect(args).toContain(`--file=${transcript}`);
    expect(args).not.toContain("--type");
    expect(args.join(" ")).not.toContain("config");
  });

  it("serializes cancel and restart so a late first start cannot cancel the second", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-dictation-race-")); roots.push(root);
    const audit = join(root, "voxtype-audit.txt");
    const env = {
      ...process.env,
      PATH: `${resolve("runtime/test/fixtures/dictation-bin")}:${process.env.PATH ?? ""}`,
      VOXTYPE_AUDIT: audit
    };
    const service = new DictationService(omapilotPaths({ ...env, XDG_RUNTIME_DIR: join(root, "run") }), env);
    const first = service.start();
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    const cancel = service.cancel();
    const second = service.start();
    await expect(first).rejects.toBeInstanceOf(DictationCancelledError);
    await cancel;
    await expect(second).resolves.toBeUndefined();
    const commands = (await readFile(audit, "utf8")).trim().split("\n");
    expect(commands.at(-1)).toMatch(/^record start /u);
    expect(commands).toContain("record cancel");
    expect(commands.findLastIndex((command) => command === "record cancel")).toBeLessThan(commands.length - 1);
  });

  it("streams bounded microphone peaks and falls back when the bridge disconnects", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-dictation-meter-")); roots.push(root);
    const audit = join(root, "voxtype-audit.txt");
    const bridge = join(root, "voxtype-audio-bridge");
    await writeFile(bridge, [
      "#!/bin/sh",
      "printf '%s\\n' '{\"status\":\"connected\"}'",
      "printf '%s\\n' 'not-json'",
      "printf '%s\\n' '{\"peak\":-2,\"rms\":0,\"vad\":0,\"ts_ms\":1}'",
      "sleep 0.04",
      "printf '%s\\n' '{\"peak\":0.8,\"rms\":0.4,\"vad\":1,\"ts_ms\":2}'",
      "sleep 0.04",
      "printf '%s\\n' '{\"status\":\"disconnected\"}'",
      "sleep 5"
    ].join("\n"), { mode: 0o700 });
    await chmod(bridge, 0o700);
    const env = {
      ...process.env,
      PATH: `${resolve("runtime/test/fixtures/dictation-bin")}:${process.env.PATH ?? ""}`,
      VOXTYPE_AUDIT: audit
    };
    const levels: Array<number | null> = [];
    const service = new DictationService(
      omapilotPaths({ ...env, XDG_RUNTIME_DIR: join(root, "run") }),
      env,
      { resolveAudioBridge: () => Promise.resolve(bridge) }
    );

    await service.start({ level: (level) => levels.push(level) });
    expect(levels.filter((level): level is number => level !== null)
      .every((level) => level >= 0 && level <= 1)).toBe(true);
    expect(levels.some((level) => level !== null && level > 0.5)).toBe(true);
    expect(levels).toContain(null);
    await service.cancel();
  });
});

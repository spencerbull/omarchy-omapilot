import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { DictationCancelledError, DictationService, dictationStartArgs } from "../src/dictation.js";
import { quickchatPaths } from "../src/paths.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("Voxtype contract", () => {
  it("uses per-recording file output without simulated typing or configuration writes", () => {
    const transcript = "/run/user/1000/quickchat/dictation.txt";
    const args = dictationStartArgs(transcript);
    expect(args).toContain(`--file=${transcript}`);
    expect(args).not.toContain("--type");
    expect(args.join(" ")).not.toContain("config");
  });

  it("serializes cancel and restart so a late first start cannot cancel the second", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-dictation-race-")); roots.push(root);
    const audit = join(root, "voxtype-audit.txt");
    const env = {
      ...process.env,
      PATH: `${resolve("runtime/test/fixtures/dictation-bin")}:${process.env.PATH ?? ""}`,
      VOXTYPE_AUDIT: audit
    };
    const service = new DictationService(quickchatPaths({ ...env, XDG_RUNTIME_DIR: join(root, "run") }), env);
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
});

describe("Voxtype waiting interface", () => {
  const service = async (status: string, binDir: string) => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-dictation-wait-")); roots.push(root);
    const env = {
      ...process.env,
      PATH: `${resolve(binDir)}:${process.env.PATH ?? ""}`,
      VOXTYPE_AUDIT: join(root, "audit.txt"),
      VOXTYPE_FAKE_STATUS: status
    };
    return {
      dictation: new DictationService(quickchatPaths({ ...env, XDG_RUNTIME_DIR: join(root, "run") }), env),
      audit: join(root, "audit.txt")
    };
  };
  const waiting = (status: string) => service(status, "runtime/test/fixtures/dictation-wait-bin");

  it("takes the transcript from the reported outcome rather than polling the file", async () => {
    const { dictation, audit } = await waiting("ok");
    await dictation.start();
    await expect(dictation.stop()).resolves.toBe("the quick brown fox");
    const commands = (await readFile(audit, "utf8")).trim().split("\n");
    expect(commands.some((command) => command.startsWith("record stop --wait --json"))).toBe(true);
  });

  it("says nothing was heard instead of waiting out the timeout", async () => {
    const { dictation } = await waiting("empty");
    await dictation.start();
    await expect(dictation.stop()).rejects.toThrow(/heard nothing/u);
  });

  it("still reports a genuine timeout as one", async () => {
    const { dictation } = await waiting("timeout");
    await dictation.start();
    await expect(dictation.stop()).rejects.toThrow(/timed out/u);
  });

  it("surfaces the daemon's own failure message", async () => {
    const { dictation } = await waiting("error");
    await dictation.start();
    await expect(dictation.stop()).rejects.toThrow(/disk went away/u);
  });

  it("does not mistake unparseable output for a transcript", async () => {
    const { dictation } = await waiting("garbage");
    await dictation.start();
    await expect(dictation.stop()).rejects.toThrow(/unreadable/u);
  });

  it("falls back to polling when Voxtype does not offer --wait", async () => {
    // The original fixture has no --wait in its help output.
    const { dictation, audit } = await service("ok", "runtime/test/fixtures/dictation-bin");
    await dictation.start();
    // Nothing ever writes a transcript here, so the poll must hit its deadline
    // rather than silently succeeding.
    await expect(dictation.stop(300)).rejects.toThrow(/timed out/u);
    const commands = (await readFile(audit, "utf8")).trim().split("\n");
    expect(commands).toContain("record stop");
    expect(commands.some((command) => command.includes("--wait"))).toBe(false);
  });
});

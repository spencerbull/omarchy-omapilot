import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import { runAcpQuestion, type ToolObservation } from "../src/acp.js";
import { discoverProviders } from "../src/providers.js";

const live = process.env.QUICKCHAT_LIVE_OPENCODE_BEHAVIOR === "1";
const activeRuns: Array<() => Promise<void>> = [];
const roots: string[] = [];
afterEach(async () => {
  await Promise.all(activeRuns.splice(0).map((cancel) => cancel()));
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("live automatic OpenCode boundary", () => {
  it.runIf(live)("loads the installed Omarchy skill through the exact skill tool", async () => {
    const provider = (await discoverProviders(process.env, "opencode")).find((candidate) => candidate.id === "opencode");
    expect(provider, "authenticated OpenCode must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const tools: ToolObservation[] = [];
    const run = runAcpQuestion(
      provider,
      "live-opencode-skill",
      "You must use the skill tool to load the installed skill named omarchy before answering. Then return exactly QUICKCHAT_SKILL_OK.",
      undefined,
      () => undefined,
      90_000,
      undefined,
      undefined,
      undefined,
      (update) => tools.push(update)
    );
    activeRuns.push(run.cancel);
    const result = await run.result.catch((error: unknown) => {
      throw new Error(`${String(error)}\n${JSON.stringify(tools)}`);
    });
    activeRuns.pop();
    expect(tools.some((update) => update.sessionUpdate === "tool_call" && update.title === "skill"), JSON.stringify(tools)).toBe(true);
    expect(result.answer).toContain("QUICKCHAT_SKILL_OK");
  }, 120_000);

  it.runIf(live)("uses web search automatically without a device permission", async () => {
    const provider = (await discoverProviders(process.env, "opencode")).find((candidate) => candidate.id === "opencode");
    expect(provider, "authenticated OpenCode must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-opencode-web",
      "You must use web search to find the official Omarchy website. Return only its HTTPS URL.",
      undefined,
      () => undefined,
      90_000,
      undefined,
      () => { permissionCount += 1; return Promise.resolve(undefined); }
    );
    activeRuns.push(run.cancel);
    const result = await run.result;
    activeRuns.pop();
    expect(permissionCount, result.answer).toBe(0);
    expect(result.answer).toMatch(/https:\/\/[^\s]*omarchy/iu);
  }, 120_000);

  it.runIf(live)("runs a generic device command after exactly one allow-once approval", async () => {
    const provider = (await discoverProviders(process.env, "opencode")).find((candidate) => candidate.id === "opencode");
    expect(provider, "authenticated OpenCode must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const root = await mkdtemp(join(tmpdir(), "quickchat-opencode-tools-"));
    roots.push(root);
    const proof = join(root, "approved-command.txt");
    let permissionCount = 0;
    const tools: ToolObservation[] = [];
    const run = runAcpQuestion(
      provider,
      "live-opencode-tools",
      `Use bash to run exactly: printf quickchat-opencode-tools-live > ${proof}. Do not claim completion until the command succeeds.`,
      undefined,
      () => undefined,
      90_000,
      undefined,
      (request) => {
        permissionCount += 1;
        expect(commandText(request)).toContain(proof);
        return Promise.resolve(request.options.find((option) => option.kind === "allow_once")?.optionId);
      },
      undefined,
      (update) => tools.push(update)
    );
    activeRuns.push(run.cancel);
    const result = await run.result.catch((error: unknown) => {
      throw new Error(`${String(error)}\n${JSON.stringify(tools)}`);
    });
    activeRuns.pop();
    expect(permissionCount, result.answer).toBe(1);
    await expect(readFile(proof, "utf8")).resolves.toBe("quickchat-opencode-tools-live");
  }, 120_000);

  it.runIf(live)("does not execute or claim success after a device-command denial", async () => {
    const provider = (await discoverProviders(process.env, "opencode")).find((candidate) => candidate.id === "opencode");
    expect(provider, "authenticated OpenCode must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const root = await mkdtemp(join(tmpdir(), "quickchat-opencode-deny-"));
    roots.push(root);
    const proof = join(root, "must-not-exist.txt");
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-opencode-deny",
      `Use bash to run exactly: printf forbidden > ${proof}. Report whether it completed.`,
      undefined,
      () => undefined,
      90_000,
      undefined,
      (request) => {
        permissionCount += 1;
        expect(commandText(request)).toContain(proof);
        return Promise.resolve(request.options.find((option) => option.kind === "reject_once")?.optionId);
      }
    );
    activeRuns.push(run.cancel);
    const result = await run.result;
    activeRuns.pop();
    expect(permissionCount, result.answer).toBe(1);
    await expect(readFile(proof, "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    expect(result.answer).toMatch(/not|didn.t|denied|unable|couldn.t|failed/iu);
  }, 120_000);
});

function commandText(request: RequestPermissionRequest): string {
  const raw = request.toolCall.rawInput;
  return raw !== null && typeof raw === "object" && !Array.isArray(raw) && typeof (raw as { command?: unknown }).command === "string"
    ? (raw as { command: string }).command
    : "";
}

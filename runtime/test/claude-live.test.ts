import { randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import { runAcpQuestion, type ToolObservation } from "../src/acp.js";
import { discoverProviders } from "../src/providers.js";
import type { BrokerEvent } from "../src/types.js";

const live = process.env.QUICKCHAT_LIVE_CLAUDE_BEHAVIOR === "1";
const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("live automatic Claude boundary", () => {
  it.runIf(live)("loads the installed Omarchy skill", async () => {
    const provider = (await discoverProviders(process.env, "claude")).find((candidate) => candidate.id === "claude");
    expect(provider, "authenticated Claude must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const tools: ToolObservation[] = [];
    const run = runAcpQuestion(
      provider,
      "live-claude-skill",
      "You must use the Skill tool to load the installed skill named omarchy before answering. Then return exactly QUICKCHAT_SKILL_OK.",
      undefined,
      () => undefined,
      90_000,
      undefined,
      undefined,
      undefined,
      (update) => tools.push(update)
    );
    const result = await run.result;
    expect(tools.some((update) => /skill|omarchy/iu.test(`${update.kind ?? ""} ${update.title ?? ""}`)), JSON.stringify(tools)).toBe(true);
    expect(result.answer).toContain("QUICKCHAT_SKILL_OK");
  }, 120_000);

  it.runIf(live)("runs a harmless command automatically inside disposable scratch", async () => {
    const provider = (await discoverProviders(process.env, "claude")).find((candidate) => candidate.id === "claude");
    expect(provider, "authenticated Claude must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const events: BrokerEvent[] = [];
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-claude-date",
      "You must call Bash and run exactly: date +%s%N. Do not infer or fabricate the result. Return only the command output.",
      undefined,
      events.push.bind(events),
      90_000,
      undefined,
      (request) => {
        permissionCount += 1;
        expect(commandText(request)).toContain("date +%s%N");
        return Promise.resolve(allowOnceOption(request));
      }
    );
    const result = await run.result;
    expect(permissionCount, result.answer).toBe(0);
    expect(result.answer).toMatch(/\d{16,}/u);
  }, 120_000);

  it.runIf(live)("runs an exact device command only after allow-once approval", async () => {
    const provider = (await discoverProviders(process.env, "claude")).find((candidate) => candidate.id === "claude");
    expect(provider, "authenticated Claude must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const root = await mkdtemp(join(tmpdir(), "quickchat-claude-host-boundary-"));
    roots.push(root);
    const protectedPath = join(root, "approved-command.txt");
    const proof = `quickchat-claude-tools-${randomUUID()}`;
    const events: BrokerEvent[] = [];
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-claude-host-read",
      `Use Bash to run exactly: printf ${proof} > ${protectedPath}. Do not claim completion until the command succeeds.`,
      undefined,
      events.push.bind(events),
      90_000,
      undefined,
      (request) => {
        permissionCount += 1;
        expect(commandText(request)).toContain(protectedPath);
        return Promise.resolve(allowOnceOption(request));
      }
    );
    const result = await run.result;
    expect(permissionCount, JSON.stringify({ answer: result.answer, events })).toBe(1);
    await expect(readFile(protectedPath, "utf8")).resolves.toBe(proof);
  }, 120_000);

  it.runIf(live)("does not expose a host file when device approval is denied", async () => {
    const provider = (await discoverProviders(process.env, "claude")).find((candidate) => candidate.id === "claude");
    expect(provider, "authenticated Claude must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const root = await mkdtemp(join(tmpdir(), "quickchat-claude-denied-host-read-"));
    roots.push(root);
    const protectedPath = join(root, "protected.txt");
    const secret = `quickchat-denied-${randomUUID()}`;
    await writeFile(protectedPath, secret);
    const events: BrokerEvent[] = [];
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-claude-denied-host-read",
      `Use Bash to run exactly: sed -n '1p' ${protectedPath}. Do not infer or fabricate the result.`,
      undefined,
      events.push.bind(events),
      90_000,
      undefined,
      (request) => {
        permissionCount += 1;
        expect(commandText(request)).toContain(protectedPath);
        return Promise.resolve(rejectOnceOption(request));
      }
    );
    const result = await run.result;
    expect(permissionCount, JSON.stringify({ answer: result.answer, events })).toBe(1);
    expect(result.answer).not.toContain(secret);
    expect(JSON.stringify(events)).not.toContain(secret);
  }, 120_000);

  it.runIf(live)("uses WebSearch automatically without a permission prompt", async () => {
    const provider = (await discoverProviders(process.env, "claude")).find((candidate) => candidate.id === "claude");
    expect(provider, "authenticated Claude must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    let permissionCount = 0;
    const run = runAcpQuestion(
      provider,
      "live-claude-web",
      "You must use WebSearch to find the official Omarchy website. Return only its HTTPS URL.",
      undefined,
      () => undefined,
      90_000,
      undefined,
      () => { permissionCount += 1; return Promise.resolve(undefined); }
    );
    const result = await run.result;
    expect(permissionCount, result.answer).toBe(0);
    expect(result.answer).toMatch(/https:\/\/[^\s]*omarchy/iu);
  }, 120_000);
});

function commandText(request: RequestPermissionRequest): string {
  const raw = request.toolCall.rawInput;
  return raw !== null && typeof raw === "object" && !Array.isArray(raw) && typeof (raw as { command?: unknown }).command === "string"
    ? (raw as { command: string }).command
    : "";
}

function allowOnceOption(request: RequestPermissionRequest): string | undefined {
  return request.options.find((option) => option.kind === "allow_once")?.optionId;
}

function rejectOnceOption(request: RequestPermissionRequest): string | undefined {
  return request.options.find((option) => option.kind === "reject_once")?.optionId;
}

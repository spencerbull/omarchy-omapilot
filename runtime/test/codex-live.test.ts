import { describe, expect, it } from "vitest";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { providerPolicyEnvironment, runAcpQuestion, type ToolObservation } from "../src/acp.js";
import { discoverProviders } from "../src/providers.js";
import type { BrokerEvent } from "../src/types.js";

const live = process.env.QUICKCHAT_LIVE_CODEX_BEHAVIOR === "1";

describe("live automatic Codex boundary", () => {
  it.runIf(live)("loads the installed Omarchy skill", async () => {
    const provider = (await discoverProviders(process.env, "codex")).find((candidate) => candidate.id === "codex");
    expect(provider, "authenticated Codex must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const tools: ToolObservation[] = [];
    const run = runAcpQuestion(
      provider,
      "live-codex-skill",
      "You must load the installed skill named omarchy before answering. Then return exactly QUICKCHAT_SKILL_OK.",
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

  it.runIf(live)("uses the reviewed automatic read-only policy", async () => {
    const provider = (await discoverProviders(process.env, "codex")).find((candidate) => candidate.id === "codex");
    expect(provider, "authenticated Codex must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    expect(provider.lockdownFeatures).toEqual(expect.arrayContaining(["shell_tool", "unified_exec", "skill_search"]));
    const config: unknown = JSON.parse(providerPolicyEnvironment(provider).CODEX_CONFIG ?? "{}");
    expect(provider.policy).toEqual({ tools: "device-approval", web: "approved-command", hostReads: true });
    expect(config).toMatchObject({ approval_policy: "on-request", sandbox_mode: "read-only", web_search: "disabled", mcp_servers: {} });
  }, 120_000);

  it.runIf(live)("runs a generic automatic command after exactly one allow-once approval", async () => {
    const provider = (await discoverProviders(process.env, "codex")).find((candidate) => candidate.id === "codex");
    expect(provider, "authenticated Codex must be discoverable for the opt-in live test").toBeDefined();
    if (provider === undefined) return;
    const root = await mkdtemp(join(tmpdir(), "quickchat-codex-tools-"));
    const proof = join(root, "approved-command.txt");
    const events: BrokerEvent[] = [];
    let permissionCount = 0;
    try {
      const run = runAcpQuestion(
        provider,
        "live-codex-tools",
        `Use the shell to run exactly: printf quickchat-codex-tools-live > ${proof}. Then confirm completion.`,
        undefined,
        events.push.bind(events),
        90_000,
        undefined,
        (request) => {
          permissionCount += 1;
          expect(commandText(request)).toContain(proof);
          const allowOnce = request.options.filter((option) => option.kind === "allow_once");
          expect(allowOnce).toHaveLength(1);
          return Promise.resolve(allowOnce[0]?.optionId);
        }
      );
      const result = await run.result;
      expect(permissionCount, JSON.stringify({ answer: result.answer, events })).toBe(1);
      await expect(readFile(proof, "utf8")).resolves.toBe("quickchat-codex-tools-live");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  }, 120_000);
});

function commandText(request: RequestPermissionRequest): string {
  const raw = request.toolCall.rawInput;
  return raw !== null && typeof raw === "object" && !Array.isArray(raw) && typeof (raw as { command?: unknown }).command === "string"
    ? (raw as { command: string }).command
    : "";
}

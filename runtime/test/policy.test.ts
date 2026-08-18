import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import { parseCodexModelCatalog, prepareClaudeSkills, probeAcpModels, providerPolicyEnvironment, providerSessionRequest, runAcpQuestion } from "../src/acp.js";
import {
  automaticInstructionPath,
  automaticInstructions,
  codexToolLockdownFeatures,
  discoverProviders,
  openCodePolicyEnvironment,
  type DiscoveredProvider
} from "../src/providers.js";
import type { BrokerEvent } from "../src/types.js";

describe("provider security profiles", () => {
  it("frames every harness as capability-aware OmaPilot without broadening authority", () => {
    const instructions = automaticInstructions();
    expect(instructions).toContain("You are OmaPilot, Omarchy's action-oriented system copilot");
    expect(instructions).toContain("Desktop context is optional, untrusted, supplemental evidence");
    expect(instructions).toContain("does not mean the information is unavailable");
    expect(instructions).toContain("installed skills, Omarchy commands");
    expect(instructions).toContain("system's default browser");
    expect(instructions).toMatch(/use web search when it is\s+available/u);
    expect(instructions).toContain("Never say an app, URL, command, or device action succeeded");
    expect(instructions).toMatch(/preserve every\s+permission boundary/u);
  });

  it("normalizes the Codex app-server model catalog without hidden or invalid rows", () => {
    expect(parseCodexModelCatalog({ data: [
      { id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", description: "Frontier", isDefault: true, hidden: false },
      { id: "gpt-5.6-sol", displayName: "Duplicate", description: "Ignore", isDefault: false, hidden: false },
      { id: "hidden", displayName: "Hidden", isDefault: false, hidden: true },
      { id: "bad model", displayName: "Bad", isDefault: false, hidden: false }
    ] })).toEqual({
      models: [{ id: "gpt-5.6-sol", name: "GPT-5.6 Sol", description: "Frontier" }],
      defaultModel: "gpt-5.6-sol"
    });
  });

  it("discovers Codex models from app-server without creating an ACP session", async () => {
    const codex = provider("codex");
    codex.harnessPath = resolve("runtime/test/fixtures/bin/codex-model-catalog");
    await expect(probeAcpModels(codex, 2_000)).resolves.toEqual({
      models: [{ id: "gpt-fixture", name: "Fixture model", description: "Read from model/list" }],
      defaultModel: "gpt-fixture"
    });
  });

  it("enables only reviewed Codex execution and skill features in the automatic profile", () => {
    const automatic: unknown = JSON.parse(providerPolicyEnvironment(provider("codex")).CODEX_CONFIG ?? "{}");
    expect(automatic).toMatchObject({
      approval_policy: "on-request",
      sandbox_mode: "read-only",
      web_search: "disabled",
      mcp_servers: {},
      developer_instructions: automaticInstructions()
    });
    const automaticFeatures = featureRecord(automatic);
    expect(automaticFeatures).toMatchObject({ shell_tool: true, unified_exec: true, skill_search: true });
    expect(automatic).toMatchObject({ developer_instructions: expect.stringContaining("relevant installed skills") });
    for (const feature of provider("codex").lockdownFeatures ?? []) {
      if (feature !== "shell_tool" && feature !== "unified_exec" && feature !== "skill_search") expect(automaticFeatures[feature]).toBe(false);
    }
  });

  it("gives automatic Claude Bash and web tools inside disposable local scratch", () => {
    const request = providerSessionRequest({
      id: "claude", name: "Claude", models: [], policy: { tools: "device-approval", web: "search", hostReads: false },
      harnessPath: "/test/claude",
      agent: {
        executable: "/test/claude-acp", args: [],
        env: { PATH: "/usr/bin", LANG: "C.UTF-8", HOME: "/home/private", API_TOKEN: "secret", USER: "private-user" }
      }
    }, "/run/user/1000/quickchat/automatic-turn");
    const serialized = JSON.parse(JSON.stringify(request)) as {
      _meta: { systemPrompt: string; claudeCode: { options: {
        tools: string[];
        disallowedTools: string[];
        sandbox: {
          enabled: boolean; failIfUnavailable: boolean; autoAllowBashIfSandboxed: boolean;
          allowUnsandboxedCommands: boolean;
          network: { allowedDomains: string[]; strictAllowlist: boolean; allowLocalBinding: boolean; allowUnixSockets: string[] };
          filesystem: { denyRead: string[]; allowRead: string[]; denyWrite: string[]; allowWrite: string[] };
          credentials: { envVars: Array<{ name: string; mode: string }> };
        }
      } } }
    };
    const options = serialized._meta.claudeCode.options;
    expect(request.mcpServers).toEqual([]);
    expect(serialized._meta.systemPrompt).toBe(automaticInstructions());
    expect(options.tools).toEqual(["Bash", "WebSearch", "Skill"]);
    expect(serialized._meta.claudeCode.options).toMatchObject({ skills: "all" });
    expect(serialized._meta.claudeCode.options).toMatchObject({ disallowedTools: expect.arrayContaining(["WebFetch"]) });
    expect(options.sandbox).toMatchObject({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: true,
      network: { allowedDomains: [], strictAllowlist: true, allowLocalBinding: false, allowUnixSockets: [] },
      filesystem: {
        allowRead: ["/run/user/1000/quickchat/automatic-turn", "/dev/null", "/etc/ld.so.cache"],
        denyWrite: ["/"],
        allowWrite: ["/run/user/1000/quickchat/automatic-turn"]
      }
    });
    expect(options.sandbox.filesystem.denyRead).toEqual(expect.arrayContaining([
      "/home", "/root", "/tmp", "/var", "/etc", "/run", "/proc", "/sys", "/dev", "/boot", "/usr/local"
    ]));
    expect(options.sandbox.filesystem.denyRead).not.toContain("/usr");
    expect(options.sandbox.credentials.envVars).toEqual([
      { name: "API_TOKEN", mode: "deny" },
      { name: "HOME", mode: "deny" },
      { name: "USER", mode: "deny" }
    ]);
  });

  it("copies installed Claude skills into disposable plugin scope and skips unsafe internal symlinks", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-claude-skills-"));
    try {
      const home = join(root, "home");
      const cwd = join(root, "turn");
      const source = join(root, "source-skill");
      await mkdir(join(home, ".agents", "skills"), { recursive: true });
      await mkdir(source, { recursive: true });
      await writeFile(join(source, "SKILL.md"), "# Safe skill\n");
      await symlink(source, join(home, ".agents", "skills", "safe"));
      const unsafe = join(home, ".agents", "skills", "unsafe");
      await mkdir(unsafe, { recursive: true });
      await writeFile(join(unsafe, "SKILL.md"), "# Unsafe skill\n");
      await symlink("/etc/hostname", join(unsafe, "host-secret"));
      await mkdir(cwd, { recursive: true });
      const plugin = await prepareClaudeSkills(cwd, { HOME: home });
      expect(plugin).toBeDefined();
      if (plugin === undefined) return;
      await expect(readFile(join(plugin, "skills", "safe", "SKILL.md"), "utf8")).resolves.toBe("# Safe skill\n");
      await expect(readFile(join(plugin, "skills", "unsafe", "SKILL.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
      await expect(readFile(join(plugin, ".claude-plugin", "plugin.json"), "utf8")).resolves.toContain("omarchy-quickchat-installed-skills");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("allows OpenCode skills and exact approved shell commands while denying other tools", () => {
    expect(JSON.parse(providerPolicyEnvironment(provider("opencode")).OPENCODE_PERMISSION ?? "{}"))
      .toMatchObject({
        "*": "deny", skill: "allow", websearch: "allow", external_directory: "allow", bash: "ask",
        read: "deny", edit: "deny", task: "deny", webfetch: "deny"
      });
    const config = JSON.parse(providerPolicyEnvironment(provider("opencode")).OPENCODE_CONFIG_CONTENT ?? "{}");
    expect(config).toMatchObject({
      default_agent: "build",
      instructions: [automaticInstructionPath()],
      skills: { urls: [] },
      agent: { build: { permission: { bash: "ask", skill: "allow", task: "deny" } } }
    });
    expect(providerPolicyEnvironment(provider("opencode")).OPENCODE_DISABLE_PROJECT_CONFIG).toBe("1");
  });

  it.each(["other", "search"])("accepts exact OpenCode websearch identity with ACP kind %s", async (kind) => {
    const fixture = await openCodeToolUpdateFixture(kind, "websearch");
    const events: BrokerEvent[] = [];
    try {
      const run = runAcpQuestion(fixture.provider, `allowed-${kind}`, "Use the approved tool", undefined, events.push.bind(events), 5_000);
      const result = await run.result.catch(async (error: unknown) => {
        throw new Error(`${String(error)}\n${await readFile(fixture.audit, "utf8").catch(() => "no audit")}`);
      });
      expect(result).toMatchObject({ answer: "safe" });
      expect(events).toContainEqual({ type: "content", id: `allowed-${kind}`, delta: "safe" });
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("accepts OpenCode's exact installed-skill tool without a device prompt", async () => {
    const fixture = await openCodeToolUpdateFixture("other", "skill");
    let permissions = 0;
    try {
      const result = await runAcpQuestion(
        fixture.provider,
        "allowed-skill",
        "Load the relevant installed skill",
        undefined,
        () => undefined,
        5_000,
        undefined,
        () => { permissions += 1; return Promise.resolve(undefined); }
      ).result;
      expect(result.answer).toBe("safe");
      expect(permissions).toBe(0);
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it.each([
    ["allow", "safe"],
    ["deny", "not completed"]
  ] as const)("mediates an exact OpenCode shell command with a one-time %s decision", async (decision, answer) => {
    const fixture = await openCodeToolUpdateFixture("execute", "bash", "execute", true, false);
    let permissions = 0;
    try {
      const result = await runAcpQuestion(
        fixture.provider,
        `opencode-shell-${decision}`,
        "Run the harmless command",
        undefined,
        () => undefined,
        5_000,
        undefined,
        (request) => {
          permissions += 1;
          expect(request.toolCall).toMatchObject({ kind: "execute", rawInput: { command: "printf quickchat" } });
          const kind = decision === "allow" ? "allow_once" : "reject_once";
          return Promise.resolve(request.options.find((option) => option.kind === kind)?.optionId);
        }
      ).result;
      expect(result.answer).toBe(answer);
      expect(permissions).toBe(1);
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("fails closed if OpenCode reports completion after a rejected command", async () => {
    const fixture = await openCodeToolUpdateFixture("execute", "bash", "execute", true, false, true);
    try {
      await expect(runAcpQuestion(
        fixture.provider,
        "opencode-shell-rejected-complete",
        "Run the harmless command",
        undefined,
        () => undefined,
        5_000,
        undefined,
        (request) => Promise.resolve(request.options.find((option) => option.kind === "reject_once")?.optionId)
      ).result).rejects.toMatchObject({ code: "forbidden_tool_attempt" });
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("fails closed if OpenCode changes an approved command under the same tool-call ID", async () => {
    const fixture = await openCodeToolUpdateFixture("execute", "bash", "execute", true, false, false, "printf different");
    try {
      await expect(runAcpQuestion(
        fixture.provider,
        "opencode-shell-command-swap",
        "Run the harmless command",
        undefined,
        () => undefined,
        5_000,
        undefined,
        (request) => Promise.resolve(request.options.find((option) => option.kind === "allow_once")?.optionId)
      ).result).rejects.toMatchObject({ code: "forbidden_tool_attempt" });
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("reports cancellation, not a forbidden tool, while OpenCode waits for approval", async () => {
    const fixture = await openCodeToolUpdateFixture("execute", "bash", "execute", false, false);
    let observed: (() => void) | undefined;
    const pending = new Promise<void>((resolvePending) => { observed = resolvePending; });
    try {
      const run = runAcpQuestion(
        fixture.provider,
        "opencode-shell-cancel",
        "Run the harmless command",
        undefined,
        () => undefined,
        5_000,
        undefined,
        () => new Promise(() => undefined),
        undefined,
        (update) => {
          if (update.sessionUpdate === "tool_call") observed?.();
        }
      );
      const result = expect(run.result).rejects.toMatchObject({ code: "cancelled" });
      await pending;
      await run.cancel();
      await result;
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("rejects a tracked OpenCode websearch call reclassified as a device tool", async () => {
    const fixture = await openCodeToolUpdateFixture("other", "websearch", "execute");
    const events: BrokerEvent[] = [];
    try {
      await expect(runAcpQuestion(fixture.provider, "reclassified-websearch", "Search the web", undefined, events.push.bind(events), 5_000).result)
        .rejects.toMatchObject({ code: "forbidden_tool_attempt" });
      expect(events.filter((event) => event.type === "content")).toEqual([]);
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it.each(["read", "edit", "delete", "move", "execute", "fetch", "switch_mode", "search", "think", "other"])("rejects unidentified OpenCode %s tool updates", async (kind) => {
    const fixture = await openCodeToolUpdateFixture(kind);
    const events: BrokerEvent[] = [];
    try {
      await expect(runAcpQuestion(
        fixture.provider,
        `blocked-${kind}`,
        "Attempt a blocked tool",
        undefined,
        events.push.bind(events),
        5_000,
        undefined,
        undefined,
        undefined,
        undefined,
        kind === "execute" ? 50 : 61_000
      ).result)
        .rejects.toMatchObject({ code: "forbidden_tool_attempt" });
      expect(events.filter((event) => event.type === "content")).toEqual([]);
    } finally {
      await rm(fixture.root, { recursive: true, force: true });
    }
  });

  it("discovers Codex only when every lockdown feature validates", async () => {
    const features = await codexToolLockdownFeatures(resolve("runtime/test/fixtures/bin/codex"), process.env);
    expect(features).toContain("future_tool_feature");
    expect(await codexToolLockdownFeatures("/bin/false", process.env)).toBeUndefined();
    const providers = await discoverProviders({
      ...process.env,
      PATH: `${resolve("runtime/test/fixtures/bin-unsafe")}:${process.env.PATH ?? ""}`,
      QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs")
    }, "codex");
    expect(providers.some((provider) => provider.id === "codex")).toBe(false);
  });

  it("discovers only the selected ACP harness without public capability metadata", async () => {
    const env = {
      ...process.env,
      PATH: `${resolve("runtime/test/fixtures/claude-auth")}:${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`,
      QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      QUICKCHAT_CLAUDE_ACP: resolve("runtime/test/fake-acp-agent.mjs")
    };
    const providers = (await Promise.all([
      discoverProviders(env, "codex"),
      discoverProviders(env, "claude"),
      discoverProviders(env, "opencode")
    ])).flat();
    expect(providers.map((provider) => provider.id)).toEqual(["codex", "claude", "opencode"]);
    expect(providers.every((provider) => !("capabilities" in provider))).toBe(true);
    expect(providers.map(({ id, policy }) => ({ id, policy }))).toEqual([
      { id: "codex", policy: { tools: "device-approval", web: "approved-command", hostReads: true } },
      { id: "claude", policy: { tools: "device-approval", web: "search", hostReads: false } },
      { id: "opencode", policy: { tools: "device-approval", web: "search", hostReads: false } }
    ]);
    const opencode = providers.find((provider) => provider.id === "opencode");
    expect(opencode).toBeDefined();
    const config = JSON.parse(opencode?.agent.env.OPENCODE_CONFIG_CONTENT ?? "{}");
    expect(config).toMatchObject({ default_agent: "build", skills: { urls: [] }, mcp: { "fixture-user-mcp": false } });
  });

  it("never substitutes ACP when the selected built-in harness is disabled", async () => {
    const providers = await discoverProviders({
      ...process.env,
      QUICKCHAT_DISABLE_PI: "1",
      PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`,
      QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs")
    }, "builtin");
    expect(providers).toEqual([]);
  });
});

function featureRecord(config: unknown): Record<string, unknown> {
  const parsed = z.object({ features: z.record(z.string(), z.boolean()) }).safeParse(config);
  return parsed.success ? parsed.data.features : {};
}

function provider(id: "codex" | "opencode"): DiscoveredProvider {
  return {
    id, name: id, models: [],
    policy: id === "codex"
      ? { tools: "device-approval", web: "approved-command", hostReads: true }
      : { tools: "device-approval", web: "search", hostReads: false },
    harnessPath: `/test/${id}`,
    agent: {
      executable: "/test/acp", args: [],
      env: id === "opencode" ? openCodePolicyEnvironment({ PATH: "/test" }) : { PATH: "/test" }
    },
      ...(id === "codex" ? { lockdownFeatures: ["shell_tool", "unified_exec", "skill_search", "code_mode", "code_mode_host", "apps", "plugins", "browser_use", "in_app_browser", "computer_use", "js_repl", "view_image"] } : {})
  };
}

async function openCodeToolUpdateFixture(
  kind: string,
  title = "Policy probe",
  updateKind = kind === "other" && title === "websearch" ? "other" : "",
  requestPermission = false,
  initialInput = true,
  completeAfterReject = false,
  updateCommand = ""
): Promise<{ root: string; audit: string; provider: DiscoveredProvider }> {
  const root = await mkdtemp(join(tmpdir(), "quickchat-opencode-tool-update-"));
  const script = join(root, "agent.mjs");
  const audit = join(root, "audit.log");
  const sdk = pathToFileURL(resolve("node_modules/@agentclientprotocol/sdk/dist/acp.js")).href;
  await writeFile(script, `
import * as acp from ${JSON.stringify(sdk)};
import { appendFileSync } from "node:fs";
import { Readable, Writable } from "node:stream";

const audit = process.env.FAKE_TOOL_AUDIT;
const log = (message) => appendFileSync(audit, message + "\\n");
process.on("uncaughtException", (error) => { log("uncaught:" + String(error?.stack || error)); process.exit(1); });
process.on("unhandledRejection", (error) => { log("rejection:" + String(error?.stack || error)); process.exit(1); });
let pending;
const stream = acp.ndJsonStream(Writable.toWeb(process.stdout), Readable.toWeb(process.stdin));
const server = acp.agent({ name: "quickchat-opencode-tool-update" })
  .onRequest(acp.methods.agent.initialize, () => { log("initialize"); return { protocolVersion: acp.PROTOCOL_VERSION, agentCapabilities: {} }; })
  .onRequest(acp.methods.agent.session.new, () => ({
    sessionId: "tool-update-session",
    modes: { currentModeId: "default", availableModes: [{ id: "default", name: "Default" }] },
    configOptions: []
  }))
  .onRequest(acp.methods.agent.session.prompt, async ({ params, client }) => {
    log("prompt");
    const controller = new AbortController();
    pending = controller;
    await client.notify(acp.methods.client.session.update, {
      sessionId: params.sessionId,
      update: {
        sessionUpdate: "tool_call", toolCallId: "tool-1", title: process.env.FAKE_TOOL_TITLE,
        kind: process.env.FAKE_TOOL_KIND, status: "pending",
        rawInput: process.env.FAKE_TOOL_INITIAL_INPUT === "1" ? { command: process.env.FAKE_TOOL_COMMAND } : undefined
      }
    });
    let allowed = true;
    if (process.env.FAKE_TOOL_REQUEST_PERMISSION === "1") {
      const decision = await client.request(acp.methods.client.session.requestPermission, {
        sessionId: params.sessionId,
        toolCall: {
          toolCallId: "tool-1", title: process.env.FAKE_TOOL_TITLE, kind: "execute",
          rawInput: { command: process.env.FAKE_TOOL_COMMAND }
        },
        options: [
          { optionId: "once", name: "Allow once", kind: "allow_once" },
          { optionId: "reject", name: "Reject", kind: "reject_once" }
        ]
      });
      allowed = decision.outcome.outcome === "selected" && decision.outcome.optionId === "once";
    }
    const reportedSuccess = allowed || process.env.FAKE_TOOL_COMPLETE_AFTER_REJECT === "1";
    await client.notify(acp.methods.client.session.update, {
      sessionId: params.sessionId,
      update: {
        sessionUpdate: "tool_call_update", toolCallId: "tool-1", title: "Tool progress",
        kind: process.env.FAKE_TOOL_UPDATE_KIND || undefined, status: reportedSuccess ? "completed" : "failed",
        rawInput: process.env.FAKE_TOOL_UPDATE_COMMAND ? { command: process.env.FAKE_TOOL_UPDATE_COMMAND } : undefined
      }
    });
    await client.notify(acp.methods.client.session.update, {
      sessionId: params.sessionId,
      update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: allowed ? "safe" : "not completed" } }
    });
    return { stopReason: controller.signal.aborted ? "cancelled" : "end_turn" };
  })
  .onNotification(acp.methods.agent.session.cancel, () => { pending?.abort(); });
server.connect(stream);
`);
  return {
    root,
    audit,
    provider: {
      id: "opencode",
      name: "OpenCode",
      models: [],
      policy: { tools: "device-approval", web: "search", hostReads: false },
      harnessPath: process.execPath,
      agent: {
        executable: process.execPath,
        args: [script],
        env: {
          ...process.env,
          FAKE_TOOL_KIND: kind,
          FAKE_TOOL_TITLE: title,
          FAKE_TOOL_UPDATE_KIND: updateKind,
          FAKE_TOOL_COMMAND: kind === "execute" ? "printf quickchat" : "",
          FAKE_TOOL_REQUEST_PERMISSION: requestPermission ? "1" : "0",
          FAKE_TOOL_INITIAL_INPUT: initialInput ? "1" : "0",
          FAKE_TOOL_COMPLETE_AFTER_REJECT: completeAfterReject ? "1" : "0",
          FAKE_TOOL_UPDATE_COMMAND: updateCommand,
          FAKE_TOOL_AUDIT: audit,
          XDG_RUNTIME_DIR: join(root, "run"),
          XDG_STATE_HOME: join(root, "state"),
          XDG_CACHE_HOME: join(root, "cache")
        }
      }
    }
  };
}

import { spawn, type ChildProcess } from "node:child_process";
import { readdirSync } from "node:fs";
import { cp, lstat, mkdir, mkdtemp, readdir, realpath, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import * as acp from "@agentclientprotocol/sdk";
import type { ContentBlock, NewSessionRequest, RequestPermissionRequest, SessionConfigOption } from "@agentclientprotocol/sdk";
import { automaticInstructions, type DiscoveredProvider } from "./providers.js";
import type { AcpPrompt } from "./context.js";
import type { BrokerEvent, ModelOption, StoredImage } from "./types.js";
import { ImageStore } from "./images.js";
import { presentImage } from "./history.js";
import { quickchatPaths } from "./paths.js";
import { runCommand, terminateProcessGroup } from "./process.js";

export type AcpResult = {
  answer: string;
  images: StoredImage[];
  sessionId: string;
  models: ModelOption[];
  defaultModel?: string;
  resumable: boolean;
};

export type AcpRun = { result: Promise<AcpResult>; cancel: () => Promise<void> };
export type PermissionDecision = { optionId?: string; invalid?: true };
export type PermissionHandler = (request: RequestPermissionRequest) => Promise<string | undefined | PermissionDecision>;
export type ToolObservation = {
  sessionUpdate: "tool_call" | "tool_call_update";
  toolCallId: string;
  kind?: string | null;
  title?: string | null;
  status?: string | null;
};
const QUICKCHAT_CLIENT_VERSION = "0.2.0";

export function providerPolicyEnvironment(provider: DiscoveredProvider): NodeJS.ProcessEnv {
  return secureEnvironment(provider);
}

export async function probeAcpModels(provider: DiscoveredProvider, timeoutMs = 15_000): Promise<{ models: ModelOption[]; defaultModel?: string }> {
  if (provider.id === "codex") return probeCodexModels(provider, timeoutMs);
  const child = spawn(provider.agent.executable, provider.agent.args, {
    cwd: "/", env: secureEnvironment(provider), stdio: ["pipe", "pipe", "ignore"], detached: process.platform !== "win32"
  });
  const paths = quickchatPaths(provider.agent.env);
  await mkdir(paths.runtime, { recursive: true, mode: 0o700 });
  const cwd = await mkdtemp(join(paths.runtime, "probe-"));
  const timeout = setTimeout(() => terminateProcessGroup(child.pid), timeoutMs);
  timeout.unref();
  try {
    if (child.stdin === null || child.stdout === null) return { models: [] };
    const stream = acp.ndJsonStream(
      webWritable(child),
      webReadable(child)
    );
    return await acp.client({ name: "omarchy-quickchat-probe" })
      .onRequest(acp.methods.client.session.requestPermission, () => ({ outcome: { outcome: "cancelled" } }))
      .connectWith(stream, async (ctx) => {
        const initialized = await ctx.request(acp.methods.agent.initialize, {
          protocolVersion: acp.PROTOCOL_VERSION,
          clientCapabilities: { session: { configOptions: { boolean: {} } } },
          clientInfo: { name: "omarchy-quickchat", version: QUICKCHAT_CLIENT_VERSION }
        });
        const ephemeral = provider.id === "claude";
        if (!ephemeral && !canRemoveSession(initialized.agentCapabilities)) return { models: [] };
        const claudePlugin = provider.id === "claude" ? await prepareClaudeSkills(cwd, provider.agent.env) : undefined;
        const session = await ctx.buildSession(providerSessionRequest(provider, cwd, ephemeral, claudePlugin)).start();
        const config = modelConfiguration(session.newSessionResponse.configOptions ?? []);
        session.dispose();
        if (!ephemeral) await removeSession(ctx, initialized.agentCapabilities, session.sessionId);
        return { models: config.models, ...(config.current === undefined ? {} : { defaultModel: config.current }) };
      });
  } catch {
    return { models: [] };
  } finally {
    clearTimeout(timeout);
    terminateProcessGroup(child.pid);
    await rm(cwd, { recursive: true, force: true });
  }
}

async function probeCodexModels(provider: DiscoveredProvider, timeoutMs: number): Promise<{ models: ModelOption[]; defaultModel?: string }> {
  const maximumResponseLineBytes = 4 * 1024 * 1024;
  const featureArgs = (provider.lockdownFeatures ?? []).flatMap((feature) => ["-c", `features.${feature}=false`]);
  const child = spawn(provider.harnessPath, [
    "app-server", "--strict-config",
    "-c", 'approval_policy="on-request"',
    "-c", 'sandbox_mode="read-only"',
    "-c", 'web_search="disabled"',
    "-c", "mcp_servers={}",
    ...featureArgs,
    "--listen", "stdio://"
  ], { cwd: "/", env: provider.agent.env, stdio: ["pipe", "pipe", "pipe"], detached: process.platform !== "win32" });
  child.stderr?.resume();
  try {
    if (child.stdin === null || child.stdout === null) return { models: [] };
    const catalog = await new Promise<unknown>((resolveCatalog, rejectCatalog) => {
      let settled = false;
      const timeout = setTimeout(() => finish(() => rejectCatalog(new Error("Codex model discovery timed out"))), timeoutMs);
      timeout.unref();
      const lines = createInterface({ input: child.stdout });
      const finish = (callback: () => void): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        lines.close();
        callback();
      };
      child.once("error", (error) => finish(() => rejectCatalog(error)));
      child.once("close", () => finish(() => rejectCatalog(new Error("Codex app server stopped during model discovery"))));
      lines.on("line", (line) => {
        if (Buffer.byteLength(line, "utf8") > maximumResponseLineBytes) {
          finish(() => rejectCatalog(new Error("Codex model response exceeded the size limit")));
          return;
        }
        let message: unknown;
        try { message = JSON.parse(line); } catch { return; }
        if (!isObject(message) || typeof message.id !== "number") return;
        if (message.id === 1) {
          if ("error" in message) { finish(() => rejectCatalog(new Error("Codex initialization failed"))); return; }
          child.stdin?.write(`${JSON.stringify({ jsonrpc: "2.0", method: "initialized", params: {} })}\n`);
          child.stdin?.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "model/list", params: {} })}\n`);
        } else if (message.id === 2) {
          if ("error" in message) { finish(() => rejectCatalog(new Error("Codex model discovery failed"))); return; }
          finish(() => resolveCatalog(message.result));
        }
      });
      child.stdin?.write(`${JSON.stringify({
        jsonrpc: "2.0", id: 1, method: "initialize",
        params: { clientInfo: { name: "omarchy-quickchat", version: QUICKCHAT_CLIENT_VERSION }, capabilities: { experimentalApi: true, requestAttestation: false } }
      })}\n`);
    });
    return parseCodexModelCatalog(catalog);
  } catch {
    return { models: [] };
  } finally {
    terminateProcessGroup(child.pid);
  }
}

export function parseCodexModelCatalog(value: unknown): { models: ModelOption[]; defaultModel?: string } {
  if (!isObject(value) || !Array.isArray(value.data)) return { models: [] };
  const models: ModelOption[] = [];
  const modelIds = new Set<string>();
  let defaultModel: string | undefined;
  for (const item of value.data) {
    if (!isObject(item) || item.hidden === true || typeof item.id !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9._:/+-]{0,127}$/u.test(item.id)) continue;
    if (modelIds.has(item.id) || models.length >= 100) continue;
    modelIds.add(item.id);
    const name = typeof item.displayName === "string" && item.displayName.trim() !== "" ? item.displayName.trim() : item.id;
    const description = typeof item.description === "string" && item.description.trim() !== "" ? item.description.trim().slice(0, 240) : undefined;
    models.push({ id: item.id, name: name.slice(0, 120), ...(description === undefined ? {} : { description }) });
    if (item.isDefault === true) defaultModel = item.id;
  }
  return { models, ...(defaultModel === undefined ? {} : { defaultModel }) };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function deleteAcpSession(provider: DiscoveredProvider, sessionId: string, timeoutMs = 15_000): Promise<boolean> {
  const child = spawn(provider.agent.executable, provider.agent.args, {
    cwd: "/", env: secureEnvironment(provider), stdio: ["pipe", "pipe", "ignore"], detached: process.platform !== "win32"
  });
  const timeout = setTimeout(() => terminateProcessGroup(child.pid), timeoutMs);
  timeout.unref();
  try {
    if (child.stdin === null || child.stdout === null) return false;
    const deleted = await acp.client({ name: "omarchy-quickchat-cleanup" })
      .onRequest(acp.methods.client.session.requestPermission, () => ({ outcome: { outcome: "cancelled" } }))
      .connectWith(acp.ndJsonStream(webWritable(child), webReadable(child)), async (ctx) => {
        const initialized = await ctx.request(acp.methods.agent.initialize, {
          protocolVersion: acp.PROTOCOL_VERSION,
          clientCapabilities: {},
          clientInfo: { name: "omarchy-quickchat", version: QUICKCHAT_CLIENT_VERSION }
        });
        return removeSession(ctx, initialized.agentCapabilities, sessionId);
      });
    if (deleted) return true;
    if (provider.id === "opencode") {
      const fallback = await runCommand(provider.harnessPath, ["--pure", "session", "delete", sessionId], {
        env: provider.agent.env,
        timeoutMs,
        maxOutput: 32_768
      });
      return fallback.code === 0;
    }
    return false;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
    terminateProcessGroup(child.pid);
  }
}

export function runAcpQuestion(
  provider: DiscoveredProvider,
  requestId: string,
  question: AcpPrompt,
  model: string | undefined,
  emit: (event: BrokerEvent) => void,
  timeoutMs = 180_000,
  imageStore = new ImageStore(),
  requestPermission?: PermissionHandler,
  cancelPermissions?: () => void,
  observeTool?: (update: ToolObservation) => void,
  openCodePermissionWaitMs = 61_000
): AcpRun {
  const child = spawn(provider.agent.executable, provider.agent.args, {
    cwd: "/",
    env: secureEnvironment(provider),
    stdio: ["pipe", "pipe", "pipe"],
    detached: process.platform !== "win32"
  });
  let cancelSession: (() => Promise<void>) | undefined;
  let activeText: GuardedTextEmitter | undefined;
  let cancelled = false;
  let forbiddenToolAttempt = false;
  let unapprovedToolAttempt = false;
  child.stderr?.resume();

  const cancel = async (): Promise<void> => {
    cancelled = true;
    activeText?.discard();
    cancelPermissions?.();
    if (cancelSession !== undefined) await cancelSession().catch(() => undefined);
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 250));
    terminateProcessGroup(child.pid);
  };

  const result = (async (): Promise<AcpResult> => {
    const paths = quickchatPaths(provider.agent.env);
    await mkdir(paths.runtime, { recursive: true, mode: 0o700 });
    const cwd = await mkdtemp(join(paths.runtime, "chat-"));
    const turnDeadline = Date.now() + timeoutMs;
    const timeout = setTimeout(() => { void cancel(); }, timeoutMs);
    timeout.unref();
    try {
      if (child.stdin === null || child.stdout === null) throw new Error("ACP process streams are unavailable");
      const stream = acp.ndJsonStream(webWritable(child), webReadable(child));
      let answer = "";
      const images: StoredImage[] = [];
      let sessionIdentifier = "";
      let modelOptions: ModelOption[] = [];
      let defaultModel: string | undefined;
      let resumable = false;
      const openCodeToolCalls = new Map<string, "automatic" | "device">();
      const approvedOpenCodeToolCalls = new Map<string, string>();
      const rejectedOpenCodeToolCalls = new Set<string>();

      const text = new GuardedTextEmitter(requestId, emit);
      activeText = text;
      const app = acp.client({ name: "omarchy-quickchat" })
        .onRequest(acp.methods.client.session.requestPermission, async ({ params }) => {
          if (requestPermission === undefined) {
            forbiddenToolAttempt = true;
            return { outcome: { outcome: "cancelled" } };
          }
          const decision = await requestPermission(params);
          if (typeof decision === "object" && decision.invalid === true) {
            forbiddenToolAttempt = true;
            return { outcome: { outcome: "cancelled" } };
          }
          const optionId = typeof decision === "string" ? decision : decision?.optionId;
          const optionKind = params.options.find((option) => option.optionId === optionId)?.kind;
          if (optionKind !== "allow_once" && optionKind !== "allow_always") unapprovedToolAttempt = true;
          if (provider.id === "opencode") {
            if (optionKind === "allow_once") {
              const command = openCodeCommand(params.toolCall.rawInput);
              if (command === undefined) forbiddenToolAttempt = true;
              else approvedOpenCodeToolCalls.set(params.toolCall.toolCallId, command);
            }
            else rejectedOpenCodeToolCalls.add(params.toolCall.toolCallId);
          }
          return optionId === undefined
            ? { outcome: { outcome: "cancelled" } }
            : { outcome: { outcome: "selected", optionId } };
        })
        .onRequest(acp.methods.client.fs.readTextFile, () => { throw new Error("Quickchat does not expose filesystem reads"); })
        .onRequest(acp.methods.client.fs.writeTextFile, () => { throw new Error("Quickchat does not expose filesystem writes"); })
        .onRequest(acp.methods.client.terminal.create, () => { throw new Error("Quickchat does not expose a terminal"); })
        .onRequest(acp.methods.client.terminal.output, () => { throw new Error("Quickchat does not expose a terminal"); })
        .onRequest(acp.methods.client.terminal.release, () => { throw new Error("Quickchat does not expose a terminal"); })
        .onRequest(acp.methods.client.terminal.waitForExit, () => { throw new Error("Quickchat does not expose a terminal"); })
        .onRequest(acp.methods.client.terminal.kill, () => { throw new Error("Quickchat does not expose a terminal"); });

      await app.connectWith(stream, async (ctx) => {
        const initialized = await ctx.request(acp.methods.agent.initialize, {
          protocolVersion: acp.PROTOCOL_VERSION,
          clientCapabilities: { session: { configOptions: { boolean: {} } } },
          clientInfo: { name: "omarchy-quickchat", version: QUICKCHAT_CLIENT_VERSION }
        });
        if (initialized.protocolVersion !== acp.PROTOCOL_VERSION) throw new Error("ACP protocol version is unsupported");
        resumable = initialized.agentCapabilities?.loadSession === true;
        const claudePlugin = provider.id === "claude" ? await prepareClaudeSkills(cwd, provider.agent.env) : undefined;
        const newRequest = providerSessionRequest(provider, cwd, false, claudePlugin);
        const session = await ctx.buildSession(newRequest).start();
        sessionIdentifier = session.sessionId;
        cancelSession = async () => {
          await ctx.notify(acp.methods.agent.session.cancel, { sessionId: session.sessionId });
        };
        const modelConfig = modelConfiguration(session.newSessionResponse.configOptions ?? []);
        modelOptions = modelConfig.models;
        defaultModel = modelConfig.current;
        if (provider.id === "codex") {
          await ctx.request(acp.methods.agent.session.setMode, { sessionId: session.sessionId, modeId: "read-only" });
        }
        if (model !== undefined && modelConfig.configId !== undefined && modelConfig.models.some((option) => option.id === model)) {
          await ctx.request(acp.methods.agent.session.setConfigOption, {
            sessionId: session.sessionId,
            configId: modelConfig.configId,
            value: model
          });
          defaultModel = model;
        }
        const promptPromise = session.prompt(question);
        try {
          for (;;) {
            const update = await session.nextUpdate();
            if (forbiddenToolAttempt) {
              await ctx.notify(acp.methods.agent.session.cancel, { sessionId: session.sessionId });
              break;
            }
            if (update.kind === "stop") break;
            observeToolUpdate(update.update, observeTool);
            if (provider.id === "opencode" && !await openCodeToolUpdateAllowed(
              update.update,
              openCodeToolCalls,
              approvedOpenCodeToolCalls,
              rejectedOpenCodeToolCalls,
              () => cancelled,
              () => forbiddenToolAttempt,
              Math.min(openCodePermissionWaitMs, Math.max(0, turnDeadline - Date.now() - 50))
            )) {
              forbiddenToolAttempt = true;
              await ctx.notify(acp.methods.agent.session.cancel, { sessionId: session.sessionId });
              break;
            }
            const content = update.update.sessionUpdate === "agent_message_chunk" ? update.update.content : undefined;
            if (content === undefined) continue;
            const handled = await handleContent(content, requestId, text, emit, imageStore, images.length);
            if (handled.text !== undefined) answer += handled.text;
            if (handled.image !== undefined) images.push(handled.image);
          }
          await promptPromise;
          if (forbiddenToolAttempt) throw forbiddenToolError();
          if (cancelled) text.discard();
          else {
            if (unapprovedToolAttempt && answer.trim() === "") {
              const notCompleted = "The action was not completed because its tool request was not approved.";
              text.write(notCompleted);
              answer = notCompleted;
            }
            text.finish();
          }
        } catch (error) {
          text.discard();
          await ctx.notify(acp.methods.agent.session.cancel, { sessionId: session.sessionId }).catch(() => undefined);
          await promptPromise.catch(() => undefined);
          throw error;
        }
        session.dispose();
      });

      if (cancelled) throw new BrokerAcpError("cancelled", "Question was cancelled", false);
      if (forbiddenToolAttempt) throw forbiddenToolError();
      return {
        answer,
        images,
        sessionId: sessionIdentifier,
        models: modelOptions,
        ...(defaultModel === undefined ? {} : { defaultModel }),
        resumable
      };
    } catch (error) {
      if (error instanceof BrokerAcpError) throw error;
      if (error instanceof ForbiddenToolMarkupError || forbiddenToolAttempt) throw forbiddenToolError();
      throw new BrokerAcpError(
        cancelled ? "cancelled" : "agent_failed",
        cancelled ? "Question was cancelled" : "The selected harness failed to answer",
        !cancelled
      );
    } finally {
      activeText?.discard();
      activeText = undefined;
      clearTimeout(timeout);
      terminateProcessGroup(child.pid);
      await rm(cwd, { recursive: true, force: true });
    }
  })();
  return { result, cancel };
}

function observeToolUpdate(
  update: { sessionUpdate: string; toolCallId?: string; kind?: string | null; title?: string | null; status?: string | null },
  observer: ((update: ToolObservation) => void) | undefined
): void {
  if (observer === undefined || (update.sessionUpdate !== "tool_call" && update.sessionUpdate !== "tool_call_update")) return;
  if (typeof update.toolCallId !== "string" || update.toolCallId === "") return;
  observer({
    sessionUpdate: update.sessionUpdate,
    toolCallId: update.toolCallId,
    ...(update.kind === undefined ? {} : { kind: update.kind }),
    ...(update.title === undefined ? {} : { title: update.title }),
    ...(update.status === undefined ? {} : { status: update.status })
  });
}

function secureEnvironment(provider: DiscoveredProvider): NodeJS.ProcessEnv {
  if (provider.id === "codex") {
    const features = Object.fromEntries((provider.lockdownFeatures ?? [])
      .map((feature) => [feature, feature === "shell_tool" || feature === "unified_exec" || feature === "skill_search"]));
    const config = {
      // Codex read-only still permits host reads. Keep native web search off so
      // those unapproved reads cannot be exfiltrated through a model-controlled
      // search query. On-request routes any network or broader command through
      // Quickchat's exact allow-once handler.
      approval_policy: "on-request",
      sandbox_mode: "read-only",
      web_search: "disabled",
      mcp_servers: {},
      developer_instructions: automaticInstructions(),
      features
    };
    return { ...provider.agent.env, CODEX_CONFIG: JSON.stringify(config), INITIAL_AGENT_MODE: "read-only" };
  }
  if (provider.id === "opencode") {
    return provider.agent.env;
  }
  return provider.agent.env;
}

function canRemoveSession(capabilities: acp.AgentCapabilities | null | undefined): boolean {
  return capabilities?.sessionCapabilities?.delete !== undefined && capabilities.sessionCapabilities.delete !== null;
}

async function removeSession(
  ctx: acp.ClientContext,
  capabilities: acp.AgentCapabilities | null | undefined,
  sessionId: string
): Promise<boolean> {
  if (capabilities?.sessionCapabilities?.delete !== undefined && capabilities.sessionCapabilities.delete !== null) {
    await ctx.request(acp.methods.agent.session.delete, { sessionId });
    return true;
  }
  return false;
}

export function providerSessionRequest(
  provider: DiscoveredProvider,
  cwd: string,
  ephemeral = false,
  claudePlugin?: string
): NewSessionRequest {
  const base: NewSessionRequest = { cwd, mcpServers: [] };
  if (provider.id !== "claude") return base;
  const tools = ["Bash", "WebSearch", "Skill"];
  const systemPrompt = automaticInstructions();
  return {
    ...base,
    _meta: {
      systemPrompt,
      claudeCode: {
        options: {
          tools,
          skills: "all",
          ...(claudePlugin === undefined ? {} : { plugins: [{ type: "local", path: claudePlugin, skipMcpDiscovery: true }] }),
          ...(ephemeral ? { persistSession: false } : {}),
          disallowedTools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "NotebookEdit", "Task", "Agent", "WebSearch", "WebFetch"].filter((tool) => !tools.includes(tool)),
          settingSources: [],
          settings: {
            permissions: {
              ask: ["Bash(*)"],
              deny: ["Write(*)", "Edit(*)", "NotebookEdit(*)", "Task(*)", "Agent(*)"],
              disableBypassPermissionsMode: "disable"
            }
          },
          sandbox: {
            enabled: true,
            failIfUnavailable: true,
            autoAllowBashIfSandboxed: true,
            allowUnsandboxedCommands: true,
            network: { allowedDomains: [], strictAllowlist: true, allowLocalBinding: false, allowUnixSockets: [] },
            filesystem: {
              denyRead: sandboxDeniedReadPaths(),
              allowRead: [cwd, "/dev/null", "/etc/ld.so.cache"],
              denyWrite: ["/"],
              allowWrite: [cwd]
            },
            credentials: {
              envVars: sandboxCredentialEnvironment(provider.agent.env)
            }
          }
        }
      }
    }
  };
}

export async function prepareClaudeSkills(cwd: string, env: NodeJS.ProcessEnv): Promise<string | undefined> {
  const home = env.HOME;
  if (home === undefined || home === "") return undefined;
  const roots = [join(home, ".agents", "skills"), join(home, ".claude", "skills")];
  const plugin = join(cwd, ".quickchat-claude-skills");
  const skills = join(plugin, "skills");
  const names = new Set<string>();
  let files = 0;
  let bytes = 0;
  for (const root of roots) {
    const entries = await readdir(root, { withFileTypes: true }).catch(() => []);
    for (const entry of entries) {
      if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,119}$/u.test(entry.name) || names.has(entry.name)) continue;
      const source = await realpath(join(root, entry.name)).catch(() => undefined);
      if (source === undefined || !(await stat(source).catch(() => undefined))?.isDirectory()) continue;
      if (!(await stat(join(source, "SKILL.md")).catch(() => undefined))?.isFile()) continue;
      const measured = await measureSafeSkill(source, files, bytes);
      if (measured === undefined) continue;
      files = measured.files;
      bytes = measured.bytes;
      await mkdir(skills, { recursive: true, mode: 0o700 });
      await cp(source, join(skills, entry.name), { recursive: true, errorOnExist: true, force: false });
      names.add(entry.name);
    }
  }
  if (names.size === 0) return undefined;
  const manifest = join(plugin, ".claude-plugin", "plugin.json");
  await mkdir(join(plugin, ".claude-plugin"), { recursive: true, mode: 0o700 });
  await writeFile(manifest, `${JSON.stringify({
    name: "omarchy-quickchat-installed-skills",
    version: "0.0.0",
    description: "Disposable view of locally installed skills for Quickchat"
  }, null, 2)}\n`, { mode: 0o600 });
  return plugin;
}

async function measureSafeSkill(
  root: string,
  initialFiles: number,
  initialBytes: number
): Promise<{ files: number; bytes: number } | undefined> {
  const queue = [root];
  let files = initialFiles;
  let bytes = initialBytes;
  while (queue.length > 0) {
    const directory = queue.pop();
    if (directory === undefined) break;
    const entries = await readdir(directory, { withFileTypes: true }).catch(() => undefined);
    if (entries === undefined) return undefined;
    for (const entry of entries) {
      const path = join(directory, entry.name);
      const info = await lstat(path).catch(() => undefined);
      if (info === undefined || info.isSymbolicLink()) return undefined;
      if (info.isDirectory()) queue.push(path);
      else if (info.isFile()) {
        files += 1;
        bytes += info.size;
        if (files > 1_000 || bytes > 5 * 1024 * 1024) return undefined;
      } else return undefined;
    }
  }
  return { files, bytes };
}

const SANDBOX_SYSTEM_ROOTS = new Set(["bin", "sbin", "lib", "lib64", "usr"]);

function sandboxDeniedReadPaths(): string[] {
  // Discover the actual root at turn creation rather than maintaining an
  // incomplete list. Only executable/library roots remain generally readable;
  // /usr/local is host-managed data and is denied separately.
  return [
    ...readdirSync("/").filter((name) => !SANDBOX_SYSTEM_ROOTS.has(name)).map((name) => `/${name}`),
    "/usr/local"
  ].sort();
}

function sandboxCredentialEnvironment(env: NodeJS.ProcessEnv): Array<{ name: string; mode: "deny" }> {
  const safe = /^(?:PATH|LANG|LC_[A-Z0-9_]+|TERM|COLORTERM|SHELL)$/u;
  return Object.keys(env)
    .filter((name) => /^[A-Za-z_][A-Za-z0-9_]*$/u.test(name) && !safe.test(name))
    .sort()
    .map((name) => ({ name, mode: "deny" as const }));
}

export function modelConfiguration(options: SessionConfigOption[]): { configId?: string; current?: string; models: ModelOption[] } {
  const option = options.find((item) => item.type === "select" && (item.category === "model" || item.id.toLowerCase().includes("model")));
  if (option === undefined || option.type !== "select") return { models: [] };
  const flat = option.options.flatMap((item) => "options" in item ? item.options : [item]);
  return {
    configId: option.id,
    current: option.currentValue,
    models: flat.map((item) => ({ id: item.value, name: item.name, ...(item.description === undefined || item.description === null ? {} : { description: item.description }) }))
  };
}

async function handleContent(
  content: ContentBlock,
  requestId: string,
  text: GuardedTextEmitter,
  emit: (event: BrokerEvent) => void,
  imageStore: ImageStore,
  imageCount: number
): Promise<{ text?: string; image?: StoredImage }> {
  if (content.type === "text") {
    text.write(content.text);
    return { text: content.text };
  }
  if (content.type === "image" && imageCount < 4) {
    text.finish();
    const image = await imageStore.saveBase64(content.data, content.mimeType, content.uri ?? undefined);
    emit({ type: "image", id: requestId, image: presentImage(image) });
    return { image };
  }
  if (content.type === "resource_link") {
    text.finish();
    const markdown = `[${escapeMarkdown(content.title ?? content.name)}](${content.uri})`;
    emit({ type: "content", id: requestId, delta: markdown });
    return { text: markdown };
  }
  if (content.type === "resource" && "text" in content.resource) {
    text.write(content.resource.text);
    return { text: content.resource.text };
  }
  return {};
}

const STREAM_FLUSH_INTERVAL_MS = 32;
const STREAM_FLUSH_SIZE = 2_048;
const MAX_TOOL_MARKUP_PREFIX = 4_096;
const TOOL_MARKUP_NAMES = [
  "toolcall", "toolcalls", "tool_call", "tool_calls", "tool-call", "tool-calls", "tool call", "tool calls",
  "functioncall", "functioncalls", "function_call", "function_calls", "function-call", "function-calls", "function call", "function calls",
  "invoke", "parameter"
];

export class GuardedTextEmitter {
  #pending = "";
  #queued = "";
  #flushTimer: ReturnType<typeof setTimeout> | undefined;
  #closed = false;

  constructor(readonly requestId: string, readonly emit: (event: BrokerEvent) => void) {}

  write(delta: string): void {
    if (this.#closed || delta === "") return;
    this.#pending += delta;
    if (containsToolMarkup(this.#pending)) {
      this.discard();
      throw new ForbiddenToolMarkupError();
    }
    const boundary = guardedEmissionBoundary(this.#pending);
    if (boundary > 0) {
      this.#queue(this.#pending.slice(0, boundary));
      this.#pending = this.#pending.slice(boundary);
    }
    if (this.#pending.length > MAX_TOOL_MARKUP_PREFIX) {
      // Whitespace in the optional DSML prefix is unbounded. Once a provider
      // holds a still-valid marker prefix beyond this cap, emitting it would
      // weaken the cross-chunk guard, so fail closed instead of buffering it.
      this.discard();
      throw new ForbiddenToolMarkupError();
    }
  }

  finish(): void {
    if (this.#closed) return;
    if (containsToolMarkup(this.#pending)) {
      this.discard();
      throw new ForbiddenToolMarkupError();
    }
    this.#queued += this.#pending;
    this.#pending = "";
    this.#flush();
  }

  discard(): void {
    this.#closed = true;
    if (this.#flushTimer !== undefined) clearTimeout(this.#flushTimer);
    this.#flushTimer = undefined;
    this.#queued = "";
    this.#pending = "";
  }

  #queue(delta: string): void {
    this.#queued += delta;
    if (this.#queued.length >= STREAM_FLUSH_SIZE) {
      this.#flush();
      return;
    }
    if (this.#flushTimer === undefined) {
      this.#flushTimer = setTimeout(() => this.#flush(), STREAM_FLUSH_INTERVAL_MS);
    }
  }

  #flush(): void {
    if (this.#flushTimer !== undefined) clearTimeout(this.#flushTimer);
    this.#flushTimer = undefined;
    if (this.#queued === "") return;
    this.emit({ type: "content", id: this.requestId, delta: this.#queued });
    this.#queued = "";
  }
}

function guardedEmissionBoundary(value: string): number {
  const possibleStart = value.lastIndexOf("<");
  return possibleStart >= 0 && possibleToolMarkupPrefix(value.slice(possibleStart)) ? possibleStart : value.length;
}

function possibleToolMarkupPrefix(value: string): boolean {
  if (!value.startsWith("<")) return false;
  let offset = 1;
  if (offset === value.length) return true;
  if (value[offset] === "/") {
    offset += 1;
    if (offset === value.length) return true;
  }
  if (isMarkupPipe(value[offset])) {
    offset = consumeMarkupPipes(value, offset);
    if (offset < 0) return false;
    offset = consumeWhitespace(value, offset);
    if (offset === value.length) return true;
    const dsml = consumeLiteral(value, offset, "dsml");
    if (dsml === undefined) return false;
    if (!dsml.complete) return true;
    offset = consumeWhitespace(value, dsml.offset);
    if (offset === value.length) return true;
    if (!isMarkupPipe(value[offset])) return false;
    offset = consumeMarkupPipes(value, offset);
    if (offset < 0) return false;
    offset = consumeWhitespace(value, offset);
    if (offset === value.length) return true;
  }
  return TOOL_MARKUP_NAMES.some((name) => name.startsWith(value.slice(offset).toLowerCase()));
}

function consumeMarkupPipes(value: string, start: number): number {
  let offset = start;
  let count = 0;
  while (offset < value.length && isMarkupPipe(value[offset])) {
    offset += 1;
    count += 1;
  }
  return count >= 1 && count <= 2 ? offset : -1;
}

function consumeWhitespace(value: string, start: number): number {
  let offset = start;
  while (offset < value.length && /\s/u.test(value[offset] ?? "")) offset += 1;
  return offset;
}

function consumeLiteral(value: string, start: number, literal: string): { complete: boolean; offset: number } | undefined {
  const remaining = value.slice(start).toLowerCase();
  if (remaining.length < literal.length) {
    return literal.startsWith(remaining) ? { complete: false, offset: value.length } : undefined;
  }
  return remaining.startsWith(literal) ? { complete: true, offset: start + literal.length } : undefined;
}

function isMarkupPipe(value: string | undefined): boolean {
  return value === "|" || value === "｜";
}

function containsToolMarkup(value: string): boolean {
  return /<\/?(?:[|｜]{1,2}\s*DSML\s*[|｜]{1,2}\s*)?(?:tool[_ -]?calls?|function[_ -]?calls?|invoke|parameter)\b/iu.test(value);
}

async function openCodeToolUpdateAllowed(
  update: {
    sessionUpdate: string;
    toolCallId?: string;
    kind?: string | null;
    name?: string | null;
    title?: string | null;
    status?: string | null;
    rawInput?: unknown;
  },
  calls: Map<string, "automatic" | "device">,
  approvedCalls: Map<string, string>,
  rejectedCalls: Set<string>,
  cancelled: () => boolean,
  forbidden: () => boolean,
  permissionWaitMs: number
): Promise<boolean> {
  if (update.sessionUpdate !== "tool_call" && update.sessionUpdate !== "tool_call_update") return true;
  const toolCallId = typeof update.toolCallId === "string" ? update.toolCallId : "";
  if (toolCallId === "") return false;
  if (update.sessionUpdate === "tool_call") {
    const classification = classifyOpenCodeTool(update);
    if (classification === undefined || update.status !== "pending") return false;
    calls.set(toolCallId, classification);
    return true;
  }
  const classification = calls.get(toolCallId);
  if (classification === undefined) return false;
  if (classification === "device") {
    const deadline = Date.now() + permissionWaitMs;
    while (!approvedCalls.has(toolCallId) && !rejectedCalls.has(toolCallId)
        && !cancelled() && !forbidden() && Date.now() < deadline) {
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    }
    if (cancelled()) return true;
    if (forbidden()) return false;
    if (rejectedCalls.has(toolCallId)) return update.status !== "completed";
    const approvedCommand = approvedCalls.get(toolCallId);
    if (approvedCommand === undefined) return false;
    if (update.rawInput !== undefined && openCodeCommand(update.rawInput) !== approvedCommand) return false;
    return update.kind === undefined || update.kind === null || update.kind === "execute";
  }
  // Updates may replace the human title with progress text. Keep the initial,
  // exact tool identity authoritative, but reject a later structural
  // reclassification to a device/fetch kind or a different programmatic name.
  if (update.kind !== undefined && update.kind !== null
      && update.kind !== "search" && update.kind !== "other") return false;
  if (update.name !== undefined && update.name !== null
      && update.name !== "websearch" && update.name !== "skill") return false;
  return true;
}

function classifyOpenCodeTool(update: {
  kind?: string | null;
  name?: string | null;
  title?: string | null;
  rawInput?: unknown;
}): "automatic" | "device" | undefined {
  // OpenCode 1.18 reports its permission-keyed `websearch` tool as ACP kind
  // `other`, with the exact tool key in the title. `search` also covers host
  // grep/glob and `think` covers task, so kind alone is never authority.
  // Require the exact tool identity in addition to OPENCODE_PERMISSION's
  // deny-all rule, and reject every device/subagent kind even if mislabeled.
  if ((update.kind === "other" || update.kind === "search")
      && (update.name === "websearch" || update.title === "websearch")) return "automatic";
  if (update.kind === "other" && (update.name === "skill" || update.title === "skill")) return "automatic";
  if (update.kind === "execute"
      && (update.title === "bash" || update.title === "shell" || exactOpenCodeCommand(update.rawInput))) return "device";
  return undefined;
}

function exactOpenCodeCommand(value: unknown): boolean {
  return openCodeCommand(value) !== undefined;
}

function openCodeCommand(value: unknown): string | undefined {
  if (!isObject(value)) return undefined;
  return typeof value.command === "string" && value.command !== "" ? value.command : undefined;
}

function forbiddenToolError(): BrokerAcpError {
  return new BrokerAcpError("forbidden_tool_attempt", "The selected harness attempted a device tool that Quickchat cannot safely authorize", false);
}

class ForbiddenToolMarkupError extends Error {
  constructor() {
    super("Provider returned raw tool-call markup");
    this.name = "ForbiddenToolMarkupError";
  }
}

function escapeMarkdown(value: string): string {
  return value.replaceAll(/[\\[\]]/g, "\\$&");
}

export class BrokerAcpError extends Error {
  constructor(readonly code: string, message: string, readonly retryable: boolean) {
    super(message);
    this.name = "BrokerAcpError";
  }
}

export function childIsRunning(child: ChildProcess): boolean {
  return child.exitCode === null && child.signalCode === null;
}

export function defaultTemporaryRoot(): string {
  return join(tmpdir(), "quickchat");
}

function webWritable(child: ChildProcess): WritableStream<Uint8Array> {
  return new WritableStream<Uint8Array>({
    write(chunk) {
      return new Promise((resolveWrite, rejectWrite) => {
        child.stdin?.write(chunk, (error) => error === null ? resolveWrite() : rejectWrite(error));
      });
    },
    close() { child.stdin?.end(); },
    abort() { child.stdin?.destroy(); }
  });
}

function webReadable(child: ChildProcess): ReadableStream<Uint8Array> {
  const maxFrameBytes = 8 * 1024 * 1024;
  let currentFrameBytes = 0;
  let settled = false;
  return new ReadableStream<Uint8Array>({
    start(controller) {
      child.stdout?.on("data", (chunk: Buffer) => {
        if (settled) return;
        for (const byte of chunk) {
          currentFrameBytes = byte === 0x0a ? 0 : currentFrameBytes + 1;
          if (currentFrameBytes > maxFrameBytes) {
            settled = true;
            controller.error(new Error("ACP frame exceeds the Quickchat limit"));
            child.stdout?.destroy();
            terminateProcessGroup(child.pid);
            return;
          }
        }
        controller.enqueue(chunk);
      });
      child.stdout?.once("end", () => {
        if (!settled) { settled = true; controller.close(); }
      });
      child.stdout?.once("error", (error) => {
        if (!settled) { settled = true; controller.error(error); }
      });
    },
    cancel() { settled = true; child.stdout?.destroy(); }
  });
}

import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { createAgentSession } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/sdk.js";
import { DefaultResourceLoader } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/resource-loader.js";
import { ModelRuntime } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/model-runtime.js";
import { SessionManager } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js";
import { SettingsManager } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/settings-manager.js";
import { parseFrontmatter } from "../../node_modules/@earendil-works/pi-coding-agent/dist/utils/frontmatter.js";
import type { InlineExtension, ToolDefinition } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.js";
import type { AuthInteraction, AuthType } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/types.js";
import { registerBundledOAuthFlowLoaders } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/load.js";
import { anthropicOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/anthropic.js";
import { openaiCodexOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/openai-codex.js";
import { githubCopilotOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/github-copilot.js";
import { openRouterOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/openrouter.js";
import { kimiCodingOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/kimi-coding.js";
import { xaiOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/xai.js";
import { createRadiusOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/radius.js";
import { Type } from "typebox";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import type { AcpPrompt } from "./context.js";
import type { AcpResult, AcpRun, PermissionHandler } from "./acp.js";
import { automaticInstructions, type PiDiscoveredProvider } from "./providers.js";
import type { BrokerEvent, BuiltinAuthMethod, ModelOption, ProviderPolicyInfo } from "./types.js";
import { quickchatPaths } from "./paths.js";

const PROVIDER_GROUPS = [
  { id: "codex", name: "Codex", piProviderIds: ["openai-codex"] },
  { id: "openai", name: "OpenAI", piProviderIds: ["openai"] },
  { id: "claude", name: "Claude", piProviderIds: ["anthropic"] }
] as const;
const BUILTIN_PROVIDER_IDS = new Set(["openai-codex", "openai", "anthropic"]);
const MUTATING_TOOLS = new Set(["bash", "edit", "write"]);
const BASIC_TOOLS = ["read", "bash", "edit", "write", "grep", "find", "ls", "agent"];
const SAFE_AGENT_NAME = /^[a-z0-9][a-z0-9._-]{0,63}$/u;
const MAX_AGENT_FILE_BYTES = 128 * 1024;
const sessionApprovals = new Map<string, PiApprovalState>();

registerBundledOAuthFlowLoaders({
  anthropic: () => anthropicOAuth,
  openaiCodex: () => openaiCodexOAuth,
  githubCopilot: () => githubCopilotOAuth,
  openrouter: () => openRouterOAuth,
  kimiCoding: () => kimiCodingOAuth,
  xai: () => xaiOAuth,
  radius: (options) => createRadiusOAuth(options)
});

export type AgentProfile = {
  name: string;
  description: string;
  tools?: string[];
  model?: string;
  systemPrompt: string;
  filePath: string;
};

export class BrokerPiError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable: boolean) {
    super(message);
    this.name = "BrokerPiError";
    this.code = code;
    this.retryable = retryable;
  }
}

export function configDirectory(env: NodeJS.ProcessEnv): string {
  const explicit = env.OMAPILOT_CONFIG_DIR?.trim();
  if (explicit !== undefined && explicit.startsWith("/")) return explicit;
  return quickchatPaths(env).config;
}

export function agentDirectory(env: NodeJS.ProcessEnv): string {
  const explicit = env.OMAPILOT_AGENTS_DIR?.trim();
  if (explicit !== undefined && explicit.startsWith("/")) return explicit;
  return join(env.HOME ?? homedir(), ".agents");
}

async function createRuntime(env: NodeJS.ProcessEnv, directory: string): Promise<ModelRuntime> {
  const runtime = await ModelRuntime.create({
    authPath: join(directory, "auth.json"),
    modelsPath: join(directory, "models.json"),
    modelsStorePath: join(directory, "models-store.json"),
    refreshOnCreate: false,
    allowModelNetwork: false
  });
  for (const [provider, key] of [
    ["openai", env.OPENAI_API_KEY],
    ["anthropic", env.ANTHROPIC_API_KEY]
  ] as const) {
    if (key?.trim()) await runtime.setRuntimeApiKey(provider, key.trim());
  }
  return runtime;
}

export async function discoverPiAuthMethods(env: NodeJS.ProcessEnv = process.env): Promise<BuiltinAuthMethod[]> {
  const directory = configDirectory(env);
  const runtime = await createRuntime(env, directory);
  const configured = new Set(configuredProviderIds(directory));
  const allowed = new Set([...BUILTIN_PROVIDER_IDS, ...configured]);
  const methods: BuiltinAuthMethod[] = [];
  for (const provider of runtime.getProviders()) {
    if (!allowed.has(provider.id)) continue;
    if (provider.auth.oauth !== undefined) methods.push({
      id: `${provider.id}::oauth`,
      providerId: provider.id,
      authType: "oauth",
      label: provider.auth.oauth.name,
      description: provider.auth.oauth.isSubscription === true
        ? `Use your ${provider.name} subscription in OmaPilot.`
        : `Sign in to ${provider.name} in your browser.`
    });
    if (provider.auth.apiKey?.login !== undefined) methods.push({
      id: `${provider.id}::api_key`,
      providerId: provider.id,
      authType: "api_key",
      label: provider.auth.apiKey.name,
      description: `Store this credential only in OmaPilot's private configuration.`
    });
  }
  return methods;
}

export async function loginPiProvider(
  env: NodeJS.ProcessEnv,
  methodId: string,
  interaction: AuthInteraction
): Promise<void> {
  const methods = await discoverPiAuthMethods(env);
  const method = methods.find((candidate) => candidate.id === methodId);
  if (method === undefined) throw new BrokerPiError("auth_method_unavailable", "That authentication method is unavailable", false);
  const runtime = await createRuntime(env, configDirectory(env));
  await runtime.login(method.providerId, method.authType as AuthType, interaction);
}

function optionId(providerId: string, modelId: string, grouped: boolean): string {
  return grouped ? `${providerId}::${modelId}` : modelId;
}

function modelOptions(models: readonly ModelShape[], grouped: boolean): ModelOption[] {
  return models.slice(0, 200).map((model) => ({
    id: optionId(model.provider, model.id, grouped),
    name: grouped ? `${model.name} (${model.provider})` : model.name,
    description: `${model.provider} · ${model.contextWindow.toLocaleString()} token context`
  }));
}

type ModelShape = {
  id: string;
  name: string;
  provider: string;
  contextWindow: number;
};

export async function discoverPiProviders(env: NodeJS.ProcessEnv = process.env): Promise<PiDiscoveredProvider[]> {
  const directory = configDirectory(env);
  const sharedAgentsDir = agentDirectory(env);
  const runtime = await createRuntime(env, directory);
  const providerIds: string[] = [];
  const models: ModelShape[] = [];
  const policy: ProviderPolicyInfo = { tools: "device-approval", web: "approved-command", hostReads: true };
  const cwd = env.HOME?.startsWith("/") === true ? env.HOME : process.cwd();

  for (const group of PROVIDER_GROUPS) {
    const available = await runtime.getAvailable(group.piProviderIds[0]) as readonly ModelShape[];
    if (available.length === 0) continue;
    providerIds.push(...group.piProviderIds);
    models.push(...available);
  }

  const compatibleIds = configuredProviderIds(directory).filter((id) => {
    if (BUILTIN_PROVIDER_IDS.has(id)) return false;
    return runtime.getModels(id).some((model) => model.api === "openai-completions" || model.api === "openai-responses");
  });
  const compatibleModels = (await Promise.all(compatibleIds.map((id) => runtime.getAvailable(id))))
    .flat() as ModelShape[];
  providerIds.push(...compatibleIds);
  models.push(...compatibleModels);
  const firstModel = models[0];
  if (firstModel === undefined) return [];
  return [{
    kind: "pi",
    id: "builtin",
    name: "Built-in (OmaPilot)",
    version: "Pi 0.84.2",
    models: modelOptions(models, true),
    defaultModel: optionId(firstModel.provider, firstModel.id, true),
    policy,
    runtime,
    piProviderIds: providerIds,
    agentDir: directory,
    sharedAgentsDir,
    cwd,
    harnessPath: "native:pi",
    agent: { executable: process.execPath, args: [], env }
  }];
}

function configuredProviderIds(directory: string): string[] {
  const path = join(directory, "models.json");
  try {
    if (statSync(path).size > 1024 * 1024) return [];
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!isObject(value) || !isObject(value.providers)) return [];
    return Object.keys(value.providers).filter((id) => /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/u.test(id));
  } catch {
    return [];
  }
}

export function runPiQuestion(
  provider: PiDiscoveredProvider,
  requestId: string,
  prompt: AcpPrompt,
  selectedModel: string | undefined,
  emit: (event: BrokerEvent) => void,
  timeoutMs = 180_000,
  requestPermission?: PermissionHandler,
  cancelPermissions?: () => void,
  resumeSessionId?: string
): AcpRun {
  const controller = new AbortController();
  let activeSession: { abort: () => Promise<void>; dispose: () => void } | undefined;
  const cancel = async (): Promise<void> => {
    controller.abort();
    cancelPermissions?.();
    await activeSession?.abort().catch(() => undefined);
    activeSession?.dispose();
  };

  const result = (async (): Promise<AcpResult> => {
    const model = resolveModel(provider, selectedModel);
    if (model === undefined) throw new BrokerPiError("model_unavailable", "The selected model is not available", false);
    const sessionManager = piSessionManager(provider, resumeSessionId);
    const profiles = discoverAgentProfiles(provider.sharedAgentsDir, provider.cwd);
    const approvalStateKey = `${provider.agentDir}\0${provider.cwd}\0${sessionManager.getSessionId()}`;
    let approvals = sessionApprovals.get(approvalStateKey);
    if (approvals === undefined) {
      approvals = new PiApprovalState(join(provider.agentDir, "approvals.json"), provider.cwd);
      sessionApprovals.set(approvalStateKey, approvals);
    }
    const permissionExtension = createPermissionExtension(requestId, requestPermission, approvals);
    const loader = new DefaultResourceLoader({
      cwd: provider.cwd,
      agentDir: provider.agentDir,
      noExtensions: true,
      noSkills: true,
      additionalSkillPaths: existingSkillPaths(provider.sharedAgentsDir, provider.cwd),
      extensionFactories: [permissionExtension],
      appendSystemPrompt: [automaticInstructions(), formatAgentProfiles(profiles)]
    });
    await loader.reload();
    const agentTool = createAgentTool(provider, model, profiles, requestId, requestPermission, approvals, controller.signal);
    const settings = SettingsManager.inMemory({
      compaction: { enabled: true },
      retry: { enabled: true, maxRetries: 2 }
    });
    const { session } = await createAgentSession({
      cwd: provider.cwd,
      agentDir: provider.agentDir,
      model,
      modelRuntime: provider.runtime,
      resourceLoader: loader,
      sessionManager,
      settingsManager: settings,
      tools: BASIC_TOOLS,
      customTools: [agentTool]
    });
    activeSession = session;
    let answer = "";
    const unsubscribe = session.subscribe((event) => {
      if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
        answer += event.assistantMessageEvent.delta;
        emit({ type: "content", id: requestId, delta: event.assistantMessageEvent.delta });
      }
    });
    const timeout = setTimeout(() => { void cancel(); }, timeoutMs);
    timeout.unref();
    try {
      const normalized = normalizePrompt(prompt);
      await session.prompt(normalized.text, normalized.images.length === 0 ? undefined : { images: normalized.images });
      if (controller.signal.aborted) throw new BrokerPiError("cancelled", "The request was cancelled", false);
      if (answer.trim() === "") answer = finalAssistantText(session.state.messages);
      if (answer.trim() === "") {
        if (provider.agent.env.QUICKCHAT_DEBUG_PI === "1") {
          process.stderr.write(`OmaPilot Pi empty response: ${assistantDiagnostics(session.state.messages)}\n`);
        }
        throw new BrokerPiError("empty_response", "The model returned no answer", true);
      }
      return {
        answer,
        images: [],
        sessionId: session.sessionId,
        models: provider.models,
        defaultModel: optionId(model.provider, model.id, provider.id === "builtin"),
        resumable: true
      };
    } catch (error) {
      if (error instanceof BrokerPiError) throw error;
      const message = error instanceof Error ? error.message : "";
      if (/api key|credential|auth|login/iu.test(message))
        throw new BrokerPiError("authentication_required", "Authentication for this provider is missing or expired", false);
      throw new BrokerPiError("agent_failed", "The Pi harness could not complete the request", true);
    } finally {
      clearTimeout(timeout);
      unsubscribe();
      session.dispose();
      activeSession = undefined;
    }
  })();
  return { result, cancel };
}

function piSessionManager(provider: PiDiscoveredProvider, resumeSessionId: string | undefined): SessionManager {
  const sessionDir = quickchatPaths(provider.agent.env).piSessions;
  mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
  if (resumeSessionId === undefined) return SessionManager.create(provider.cwd, sessionDir);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(resumeSessionId))
    throw new BrokerPiError("session_unavailable", "The saved Pi conversation is unavailable", false);
  const suffix = `_${resumeSessionId}.jsonl`;
  const file = readdirSync(sessionDir).find((name) => name.endsWith(suffix));
  if (file === undefined)
    throw new BrokerPiError("session_unavailable", "The saved Pi conversation is unavailable", false);
  return SessionManager.open(join(sessionDir, file), sessionDir, provider.cwd);
}

type PiModel = ReturnType<PiDiscoveredProvider["runtime"]["getModels"]>[number];

function resolveModel(provider: PiDiscoveredProvider, selected: string | undefined): PiModel | undefined {
  const models = provider.piProviderIds.flatMap((id) => [...provider.runtime.getModels(id)]);
  if (selected === undefined || selected === "") return models[0];
  if (provider.id === "builtin") {
    return models.find((model) => optionId(model.provider, model.id, true) === selected);
  }
  return models.find((model) => model.id === selected);
}

function normalizePrompt(prompt: AcpPrompt): { text: string; images: Array<{ type: "image"; data: string; mimeType: string }> } {
  if (typeof prompt === "string") return { text: prompt, images: [] };
  return {
    text: prompt.filter((block) => block.type === "text").map((block) => block.text).join("\n\n"),
    images: prompt.filter((block): block is Extract<(typeof prompt)[number], { type: "image" }> => block.type === "image")
  };
}

type PersistedApprovals = { version: 1; allow: string[]; deny: string[] };

export class PiApprovalState {
  readonly #path: string;
  readonly #cwd: string;
  readonly #session = new Set<string>();
  readonly #allow: Set<string>;
  readonly #deny: Set<string>;

  constructor(path: string, cwd: string) {
    this.#path = path;
    this.#cwd = cwd;
    const persisted = readApprovals(path);
    this.#allow = new Set(persisted.allow);
    this.#deny = new Set(persisted.deny);
  }

  key(tool: string, rawInput: Record<string, unknown>): string {
    return createHash("sha256").update(JSON.stringify({ cwd: this.#cwd, tool, rawInput: stableValue(rawInput) })).digest("hex");
  }

  allowed(key: string): boolean { return this.#session.has(key) || this.#allow.has(key); }
  denied(key: string): boolean { return this.#deny.has(key); }
  allowSession(key: string): void { this.#session.add(key); }
  allowAlways(key: string): void { this.#deny.delete(key); this.#allow.add(key); this.#save(); }
  denyAlways(key: string): void { this.#session.delete(key); this.#allow.delete(key); this.#deny.add(key); this.#save(); }

  #save(): void {
    mkdirSync(dirname(this.#path), { recursive: true, mode: 0o700 });
    const temporary = `${this.#path}.${randomUUID()}.tmp`;
    writeFileSync(temporary, `${JSON.stringify({ version: 1, allow: [...this.#allow], deny: [...this.#deny] })}\n`, { mode: 0o600 });
    renameSync(temporary, this.#path);
  }
}

function readApprovals(path: string): PersistedApprovals {
  try {
    if (statSync(path).size > 1024 * 1024) return { version: 1, allow: [], deny: [] };
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!isObject(value)) return { version: 1, allow: [], deny: [] };
    const hashes = (candidate: unknown): string[] => Array.isArray(candidate)
      ? candidate.filter((item): item is string => typeof item === "string" && /^[a-f0-9]{64}$/u.test(item)).slice(0, 10_000)
      : [];
    return { version: 1, allow: hashes(value.allow), deny: hashes(value.deny) };
  } catch { return { version: 1, allow: [], deny: [] }; }
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!isObject(value)) return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
}

function createPermissionExtension(requestId: string, handler: PermissionHandler | undefined, approvals: PiApprovalState): InlineExtension {
  return {
    name: "omapilot-permissions",
    hidden: true,
    factory: (pi) => {
      pi.on("tool_call", async (event) => {
        if (!MUTATING_TOOLS.has(event.toolName)) return undefined;
        if (handler === undefined) return { block: true, reason: "OmaPilot did not provide a permission handler" };
        const rawInput = reviewableToolInput(event.toolName, event.input);
        const approvalKey = approvals.key(event.toolName, rawInput);
        if (approvals.denied(approvalKey)) return { block: true, reason: "This exact tool request is always denied" };
        if (approvals.allowed(approvalKey)) return undefined;
        const request: RequestPermissionRequest = {
          sessionId: requestId,
          toolCall: {
            toolCallId: event.toolCallId,
            kind: "execute",
            title: toolTitle(event.toolName, event.input),
            rawInput
          },
          options: [
            { optionId: `allow-${event.toolCallId}`, name: "Allow once", kind: "allow_once" },
            { optionId: `session-${event.toolCallId}`, name: "Allow exact request for this session", kind: "allow_always" },
            { optionId: `always-${event.toolCallId}`, name: "Always allow exact request", kind: "allow_always" },
            { optionId: `reject-${event.toolCallId}`, name: "Deny", kind: "reject_once" },
            { optionId: `reject-always-${event.toolCallId}`, name: "Always deny exact request", kind: "reject_always" }
          ]
        };
        const decision = await handler(request);
        const option = typeof decision === "string" ? decision : decision?.optionId;
        if (option === `session-${event.toolCallId}`) approvals.allowSession(approvalKey);
        if (option === `always-${event.toolCallId}`) approvals.allowAlways(approvalKey);
        if (option === `reject-always-${event.toolCallId}`) approvals.denyAlways(approvalKey);
        return option === `allow-${event.toolCallId}` || option === `session-${event.toolCallId}` || option === `always-${event.toolCallId}`
          ? undefined : { block: true, reason: "The user denied this tool call" };
      });
    }
  };
}

function reviewableToolInput(name: string, input: Record<string, unknown>): Record<string, unknown> {
  if (name === "bash") return { ...input, command: typeof input.command === "string" ? input.command : "" };
  const path = typeof input.path === "string" ? input.path : "unknown";
  return { command: `${name} ${path}`, ...input };
}

function toolTitle(name: string, input: Record<string, unknown>): string {
  if (name === "bash") return "Run a command";
  const path = typeof input.path === "string" ? basename(input.path) : "file";
  return `${name === "write" ? "Write" : "Edit"} ${path}`;
}

export function existingSkillPaths(directory: string, cwd: string): string[] {
  const candidates = [
    join(directory, "skills"),
    join(cwd, ".agents/skills"),
    join(cwd, ".pi/skills")
  ];
  return [...new Set(candidates.filter((path) => existsSync(path)))];
}

export function discoverAgentProfiles(directory: string, cwd: string): AgentProfile[] {
  const directories = [...new Set([join(directory, "agents"), join(cwd, ".agents/agents")])];
  const profiles = new Map<string, AgentProfile>();
  for (const path of directories) {
    if (!existsSync(path)) continue;
    let entries;
    try { entries = readdirSync(path, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      if (!entry.name.endsWith(".md") || (!entry.isFile() && !entry.isSymbolicLink())) continue;
      const filePath = join(path, entry.name);
      try {
        if (statSync(filePath).size > MAX_AGENT_FILE_BYTES) continue;
        const parsed = parseFrontmatter(readFileSync(filePath, "utf8"));
        const name = typeof parsed.frontmatter.name === "string" ? parsed.frontmatter.name.trim() : basename(entry.name, ".md");
        const description = typeof parsed.frontmatter.description === "string" ? parsed.frontmatter.description.trim() : "";
        if (!SAFE_AGENT_NAME.test(name) || description === "") continue;
        const tools = parseTools(parsed.frontmatter.tools);
        profiles.set(name, {
          name,
          description: description.slice(0, 500),
          systemPrompt: parsed.body.trim(),
          filePath,
          ...(tools === undefined ? {} : { tools }),
          ...(typeof parsed.frontmatter.model !== "string" ? {} : { model: parsed.frontmatter.model.trim() })
        });
      } catch { /* Skip an unreadable or malformed agent without disabling the harness. */ }
    }
  }
  return [...profiles.values()].slice(0, 32);
}

function parseTools(value: unknown): string[] | undefined {
  const values = Array.isArray(value) ? value : typeof value === "string" ? value.split(",") : [];
  const tools = values.filter((item): item is string => typeof item === "string")
    .map((item) => item.trim()).filter((item) => BASIC_TOOLS.includes(item) && item !== "agent");
  return tools.length === 0 ? undefined : [...new Set(tools)];
}

function formatAgentProfiles(profiles: AgentProfile[]): string {
  if (profiles.length === 0) return "No named agents are installed.";
  return [
    "Named agents are available through the agent tool. Delegate only when a profile clearly matches the task.",
    ...profiles.map((profile) => `- ${profile.name}: ${profile.description} (${profile.filePath})`)
  ].join("\n");
}

const agentToolParameters = Type.Object({
  name: Type.String({ description: "Installed agent name", minLength: 1, maxLength: 64 }),
  task: Type.String({ description: "Self-contained task for the agent", minLength: 1, maxLength: 100_000 })
});

function createAgentTool(
  provider: PiDiscoveredProvider,
  parentModel: PiModel,
  profiles: AgentProfile[],
  requestId: string,
  requestPermission: PermissionHandler | undefined,
  approvals: PiApprovalState,
  parentSignal: AbortSignal
): ToolDefinition<typeof agentToolParameters> {
  return {
    name: "agent",
    label: "Agent",
    description: "Delegate a bounded task to an installed named agent profile.",
    promptSnippet: "Delegate a task to a named agent from ~/.agents/agents",
    parameters: agentToolParameters,
    async execute(_toolCallId, input, signal) {
      const profile = profiles.find((candidate) => candidate.name === input.name);
      if (profile === undefined) return { content: [{ type: "text", text: `Unknown agent: ${input.name}` }], details: undefined, isError: true };
      const model = profile.model === undefined ? parentModel : resolveProfileModel(provider, profile.model) ?? parentModel;
      const loader = new DefaultResourceLoader({
        cwd: provider.cwd,
        agentDir: provider.agentDir,
        noExtensions: true,
        noSkills: true,
        additionalSkillPaths: existingSkillPaths(provider.sharedAgentsDir, provider.cwd),
        extensionFactories: [createPermissionExtension(requestId, requestPermission, approvals)],
        systemPrompt: [automaticInstructions(), profile.systemPrompt].join("\n\n")
      });
      await loader.reload();
      const sessionResult = await createAgentSession({
        cwd: provider.cwd,
        agentDir: provider.agentDir,
        model,
        modelRuntime: provider.runtime,
        resourceLoader: loader,
        sessionManager: SessionManager.inMemory(provider.cwd),
        settingsManager: SettingsManager.inMemory({ compaction: { enabled: true } }),
        tools: profile.tools ?? ["read", "grep", "find", "ls"]
      });
      const output = await runNestedAgentPrompt(sessionResult.session, input.task, [parentSignal, signal]);
      return { content: [{ type: "text", text: output || "The agent returned no answer." }], details: { agent: profile.name } };
    }
  };
}

type NestedAgentSession = {
  state: { messages: readonly unknown[] };
  prompt: (text: string) => Promise<void>;
  abort: () => Promise<void>;
  dispose: () => void;
};

export async function runNestedAgentPrompt(
  session: NestedAgentSession,
  task: string,
  signals: Array<AbortSignal | undefined>
): Promise<string> {
  const activeSignals = signals.filter((signal): signal is AbortSignal => signal !== undefined);
  let abortPromise: Promise<void> | undefined;
  const abort = (): void => {
    abortPromise ??= session.abort().catch(() => undefined);
  };
  for (const signal of activeSignals) signal.addEventListener("abort", abort, { once: true });
  if (activeSignals.some((signal) => signal.aborted)) abort();
  try {
    if (abortPromise !== undefined) {
      await abortPromise;
      throw new BrokerPiError("cancelled", "The request was cancelled", false);
    }
    await session.prompt(task);
    if (activeSignals.some((signal) => signal.aborted))
      throw new BrokerPiError("cancelled", "The request was cancelled", false);
    return finalAssistantText(session.state.messages);
  } finally {
    for (const signal of activeSignals) signal.removeEventListener("abort", abort);
    if (abortPromise !== undefined) await abortPromise;
    session.dispose();
  }
}

function resolveProfileModel(provider: PiDiscoveredProvider, value: string): PiModel | undefined {
  const all = provider.runtime.getModels();
  const separator = value.indexOf("/");
  if (separator > 0) {
    const providerId = value.slice(0, separator);
    const modelId = value.slice(separator + 1);
    return provider.runtime.getModel(providerId, modelId);
  }
  return all.find((model) => model.id === value);
}

function finalAssistantText(messages: readonly unknown[]): string {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (!isObject(message) || message.role !== "assistant" || !Array.isArray(message.content)) continue;
    const text = message.content.filter((part) => isObject(part) && part.type === "text" && typeof part.text === "string")
      .map((part) => String((part as Record<string, unknown>).text)).join("");
    if (text !== "") return text;
  }
  return "";
}

function assistantDiagnostics(messages: readonly unknown[]): string {
  const value = messages.flatMap((raw) => {
    if (!isObject(raw) || raw.role !== "assistant") return [];
    return [{
      stopReason: typeof raw.stopReason === "string" ? boundedDiagnostic(raw.stopReason) : "",
      error: typeof raw.errorMessage === "string" ? boundedDiagnostic(raw.errorMessage) : "",
      content: Array.isArray(raw.content)
        ? raw.content.map((part: unknown) => isObject(part) && typeof part.type === "string" ? boundedDiagnostic(part.type) : "unknown")
        : []
    }];
  }).slice(-3);
  return JSON.stringify(value);
}

function boundedDiagnostic(value: string): string {
  return value.replaceAll(/[\u0000-\u001f\u007f-\u009f]/gu, " ").slice(0, 300);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

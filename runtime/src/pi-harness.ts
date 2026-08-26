import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, truncateSync, unlinkSync, writeFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { createAgentSession } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/sdk.js";
import { DefaultResourceLoader } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/resource-loader.js";
import { AuthStorage, readStoredCredential } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/auth-storage.js";
import { ModelRuntime } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/model-runtime.js";
import { SessionManager } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js";
import { SettingsManager } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/settings-manager.js";
import { parseFrontmatter } from "../../node_modules/@earendil-works/pi-coding-agent/dist/utils/frontmatter.js";
import type { InlineExtension, ToolDefinition } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.js";
import type { AuthInteraction, AuthType, Credential } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/types.js";
import { registerBundledOAuthFlowLoaders } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/load.js";
import { anthropicOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/anthropic.js";
import { openaiCodexOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/openai-codex.js";
import { githubCopilotOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/github-copilot.js";
import { openRouterOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/openrouter.js";
import { kimiCodingOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/kimi-coding.js";
import { xaiOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/xai.js";
import { createRadiusOAuth } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/oauth/radius.js";
import { getApiProvider } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/compat.js";
import { Type } from "typebox";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import type { AcpPrompt } from "./context.js";
import type { AcpResult, AcpRun, PermissionHandler } from "./acp.js";
import { automaticInstructions, type PiDiscoveredProvider } from "./providers.js";
import type { BrokerEvent, BuiltinAuthMethod, CommandReceipt, ModelOption, ProviderPolicyInfo, WebHandoffProvider } from "./types.js";
import { omapilotPaths } from "./paths.js";
import { pluginRoot } from "./runtime-root.js";
import {
  createPersonalAssistantTools,
  displayCommand,
  desktopToolTitle,
  reviewDesktopToolInput
} from "./tools/desktop.js";
import { createWebHandoffTool, webHandoffApproval, webHandoffTitle } from "./tools/web-handoff.js";
import {
  capabilityReviewableInput,
  capabilityToolRisk,
  capabilityToolTitle,
  createCapabilityRegistry,
  type CapabilityRisk
} from "./capabilities/index.js";

export {
  createPersonalAssistantTools,
  discoverInstalledApps,
  discoverOmarchyCommands,
  normalizeWindowAddress,
  readDesktopState,
  windowActionCommand,
  workspaceActionCommand
} from "./tools/desktop.js";

const PROVIDER_GROUPS = [
  { id: "codex", name: "Codex", piProviderIds: ["openai-codex"] },
  { id: "openai", name: "OpenAI", piProviderIds: ["openai"] },
  { id: "grok", name: "Grok", piProviderIds: ["xai"] }
] as const;
const BUILTIN_PROVIDER_IDS = new Set(["openai-codex", "openai", "xai"]);
const MUTATING_TOOLS = new Set([
  "bash", "edit", "write", "open_url", "web_handoff", "media_control", "app_open", "window_action", "workspace_action"
]);
const AGENT_PROFILE_TOOLS = ["read", "bash", "edit", "write", "grep", "find", "ls"];
const PI_TOOLS = [
  ...AGENT_PROFILE_TOOLS, "agent", "open_url", "web_handoff", "media_control", "app_catalog", "app_open", "desktop_state",
  "window_action", "workspace_action", "omarchy_commands"
];
const SAFE_AGENT_NAME = /^[a-z0-9][a-z0-9._-]{0,63}$/u;
const MAX_AGENT_FILE_BYTES = 128 * 1024;
const sessionApprovals = new Map<string, PiApprovalState>();
const NO_AUTH_RUNTIME_KEY = "omapilot-no-auth";
const MAX_DESKTOP_COMMAND_OUTPUT = 128 * 1024;

const openUrlParameters = Type.Object({
  url: Type.String({ description: "Absolute http or https URL to open in the default browser", minLength: 1, maxLength: 2048 })
});
const mediaControlParameters = Type.Object({
  action: Type.Union([
    Type.Literal("play_pause"), Type.Literal("play"), Type.Literal("pause"),
    Type.Literal("next"), Type.Literal("previous"),
    Type.Literal("source_next"), Type.Literal("source_previous")
  ], { description: "Playback action for the active Omarchy media player" })
});

registerBundledOAuthFlowLoaders({
  // Required by OAuthFlowLoaders. Registering the flow is not the same as
  // offering the provider: anthropic is absent from BUILTIN_PROVIDER_IDS, so
  // no Claude auth method or model is ever surfaced.
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
  return omapilotPaths(env).config;
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
  // Pi intentionally requires every provider to have an auth resolver, while
  // local OpenAI-compatible servers commonly require no credential at all.
  // Register a memory-only resolver for those managed entries and remove the
  // synthetic SDK Authorization header at the final fetch boundary.
  for (const provider of configuredNoAuthProviders(directory)) {
    runtime.registerProvider(provider.id, {
      api: provider.api,
      apiKey: NO_AUTH_RUNTIME_KEY,
      authHeader: false,
      streamSimple: (model, context, options) => {
        const implementation = getApiProvider(model.api);
        if (implementation === undefined) throw new Error(`No API provider registered for api: ${model.api}`);
        return implementation.streamSimple(model, context, {
          ...options,
          fetch: fetchWithoutAuthentication
        });
      }
    });
  }
  for (const [provider, key] of [
    ["openai", env.OPENAI_API_KEY],
    ["xai", env.XAI_API_KEY]
  ] as const) {
    if (key?.trim()) await runtime.setRuntimeApiKey(provider, key.trim());
  }
  return runtime;
}

export async function discoverPiAuthMethods(env: NodeJS.ProcessEnv = process.env): Promise<BuiltinAuthMethod[]> {
  const directory = configDirectory(env);
  const runtime = await createRuntime(env, directory);
  const configured = new Set(configuredProviderIds(directory));
  const noAuth = new Set(configuredNoAuthProviders(directory).map((provider) => provider.id));
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
    if (!noAuth.has(provider.id) && provider.auth.apiKey?.login !== undefined) methods.push({
      id: `${provider.id}::api_key`,
      providerId: provider.id,
      authType: "api_key",
      label: provider.auth.apiKey.name,
      description: `Store this credential only in OmaPilot's private configuration.`
    });
  }
  return methods;
}

function fetchWithoutAuthentication(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init);
  const headers = new Headers(request.headers);
  headers.delete("authorization");
  headers.delete("api-key");
  return fetch(new Request(request, { headers }));
}

function configuredNoAuthProviders(directory: string): Array<{ id: string; api: string }> {
  const path = join(directory, "models.json");
  try {
    if (statSync(path).size > 1024 * 1024) return [];
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!isObject(value) || !isObject(value.providers)) return [];
    const providers: Array<{ id: string; api: string }> = [];
    for (const [id, entry] of Object.entries(value.providers)) {
      if (!isObject(entry) || entry.omapilotManaged !== true || entry.omapilotAuthRequired === true) continue;
      const api = typeof entry.api === "string" ? entry.api : "";
      if (api !== "openai-responses" && api !== "openai-completions") continue;
      providers.push({ id, api });
    }
    return providers;
  } catch {
    return [];
  }
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

// Removing a server must also drop its credential, or a deleted endpoint leaves
// a live secret in auth.json forever.
export async function logoutPiProvider(env: NodeJS.ProcessEnv, providerId: string): Promise<void> {
  const runtime = await createRuntime(env, configDirectory(env));
  await runtime.logout(providerId);
}

export type PiProviderCredentialSnapshot = Credential | undefined;

/** Preserve the unresolved auth.json value so a failed endpoint edit can restore it exactly. */
export function snapshotPiProviderCredential(
  env: NodeJS.ProcessEnv,
  providerId: string
): PiProviderCredentialSnapshot {
  const credential = readStoredCredential(providerId, join(configDirectory(env), "auth.json"));
  return credential === undefined ? undefined : structuredClone(credential);
}

/** Restore one provider credential without disturbing unrelated auth.json entries. */
export async function restorePiProviderCredential(
  env: NodeJS.ProcessEnv,
  providerId: string,
  credential: PiProviderCredentialSnapshot
): Promise<void> {
  const storage = AuthStorage.create(join(configDirectory(env), "auth.json"));
  if (credential === undefined) {
    await storage.delete(providerId);
    return;
  }
  await storage.modify(providerId, () => Promise.resolve(structuredClone(credential)));
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
  resumeSessionId?: string,
  webHandoffProvider: WebHandoffProvider = "duckduckgo",
  observeAction?: (receipt: CommandReceipt) => void
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
    const permissionExtension = createPermissionExtension(requestId, requestPermission, approvals, webHandoffProvider);
    const capabilities = await createCapabilityRegistry(provider.agent.env);
    const loader = new DefaultResourceLoader({
      cwd: provider.cwd,
      agentDir: provider.agentDir,
      noExtensions: true,
      noSkills: true,
      additionalSkillPaths: allSkillPaths(provider),
      extensionFactories: [permissionExtension],
      appendSystemPrompt: [automaticInstructions(), formatAgentProfiles(profiles)]
    });
    await loader.reload();
    const agentTool = createAgentTool(provider, model, profiles, requestId, requestPermission, approvals, controller.signal);
    const settings = SettingsManager.inMemory({
      compaction: { enabled: true },
      // Retry once at the HTTP provider boundary, whose status-aware policy
      // accepts transport errors, 408/409/429, and 5xx while rejecting other
      // 4xx. Disable Pi's text-classified outer retry so wrapped 400 errors and
      // partial streams can never be replayed or concatenated.
      retry: { enabled: false, provider: { maxRetries: 1, maxRetryDelayMs: 5_000 } }
    });
    const { session } = await createAgentSession({
      cwd: provider.cwd,
      agentDir: provider.agentDir,
      model,
      modelRuntime: provider.runtime,
      resourceLoader: loader,
      sessionManager,
      settingsManager: settings,
      tools: [...PI_TOOLS, ...capabilities.tools.map((tool) => tool.name)],
      customTools: [
        agentTool,
        ...createDesktopTools(undefined, observeAction),
        createWebHandoffTool(webHandoffProvider, undefined, undefined, observeAction),
        ...createPersonalAssistantTools(undefined, undefined, undefined, observeAction),
        ...capabilities.tools
      ]
    });
    activeSession = session;
    let streamedText = "";
    const unsubscribe = session.subscribe((event) => {
      if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
        streamedText += event.assistantMessageEvent.delta;
        emit({ type: "content", id: requestId, delta: event.assistantMessageEvent.delta });
      }
    });
    const timeout = setTimeout(() => { void cancel(); }, timeoutMs);
    timeout.unref();
    const turnStartIndex = session.state.messages.length;
    const sessionFile = sessionManager.getSessionFile();
    const sessionFileExisted = sessionFile !== undefined && existsSync(sessionFile);
    const sessionFileBytes = sessionFileExisted && sessionFile !== undefined ? statSync(sessionFile).size : 0;
    let promptStarted = false;
    let rollbackTurn = false;
    try {
      const normalized = normalizePrompt(prompt);
      promptStarted = true;
      await session.prompt(normalized.text, normalized.images.length === 0 ? undefined : { images: normalized.images });
      if (controller.signal.aborted) throw new BrokerPiError("cancelled", "The request was cancelled", false);
      const turnMessages = session.state.messages.slice(turnStartIndex);
      const terminal = terminalAssistantMessage(turnMessages);
      const terminalError = terminalAssistantError(terminal);
      if (terminalError !== undefined) throw terminalError;
      const answer = assistantText(terminal);
      if (answer.trim() === "") {
        if (provider.agent.env.OMAPILOT_DEBUG_PI === "1") {
          process.stderr.write(`OmaPilot Pi empty response: streamed=${String(streamedText.length)} ${assistantDiagnostics(turnMessages)}\n`);
        }
        throw new BrokerPiError("empty_response", "The model returned no final answer", true);
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
      rollbackTurn = promptStarted;
      if (error instanceof BrokerPiError) throw error;
      const message = error instanceof Error ? error.message : "";
      if (/api key|credential|auth|login/iu.test(message))
        throw new BrokerPiError("authentication_required", "Authentication for this provider is missing or expired", false);
      throw new BrokerPiError("agent_failed", "The Pi harness could not complete the request", true);
    } finally {
      clearTimeout(timeout);
      unsubscribe();
      session.dispose();
      if (rollbackTurn && sessionFile !== undefined) {
        try {
          if (sessionFileExisted) truncateSync(sessionFile, sessionFileBytes);
          else if (existsSync(sessionFile)) unlinkSync(sessionFile);
        }
        catch (error) {
          if (provider.agent.env.OMAPILOT_DEBUG_PI === "1") {
            const message = error instanceof Error ? error.message : String(error);
            process.stderr.write(`OmaPilot Pi could not roll back failed turn: ${boundedDiagnostic(message)}\n`);
          }
        }
      }
      activeSession = undefined;
    }
  })();
  return { result, cancel };
}

function piSessionManager(provider: PiDiscoveredProvider, resumeSessionId: string | undefined): SessionManager {
  const sessionDir = omapilotPaths(provider.agent.env).piSessions;
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

export function normalizeOpenUrl(raw: string): string {
  const value = raw.trim();
  let url: URL;
  try { url = new URL(value); }
  catch { throw new BrokerPiError("invalid_url", "Open a complete http or https URL", false); }
  if ((url.protocol !== "http:" && url.protocol !== "https:") || url.username !== "" || url.password !== "") {
    throw new BrokerPiError("invalid_url", "Only credential-free http and https URLs can be opened", false);
  }
  if (url.href.length > 2048) throw new BrokerPiError("invalid_url", "The URL is too long to open", false);
  return url.href;
}

export function omarchyMediaMethod(action: string): string {
  const methods: Record<string, string> = {
    play_pause: "playPause",
    play: "play",
    pause: "pause",
    next: "next",
    previous: "previous",
    source_next: "sourceNext",
    source_previous: "sourcePrevious"
  };
  const method = methods[action];
  if (method === undefined) throw new BrokerPiError("invalid_media_action", "That media action is unavailable", false);
  return method;
}

type DesktopCommandResult = { stdout: string; stderr: string };
type DesktopCommandRunner = (file: string, args: string[], signal?: AbortSignal) => Promise<DesktopCommandResult>;

const runDesktopCommand: DesktopCommandRunner = (file, args, signal) => new Promise((resolve, reject) => {
  execFile(file, args, {
    encoding: "utf8",
    maxBuffer: MAX_DESKTOP_COMMAND_OUTPUT,
    timeout: 10_000,
    signal
  }, (error, stdout, stderr) => {
    if (error !== null) reject(error);
    else resolve({ stdout, stderr });
  });
});

function commandToolError(action: string, error: unknown): { content: Array<{ type: "text"; text: string }>; details: undefined; isError: true } {
  const message = error instanceof BrokerPiError ? error.message : `${action} failed`;
  return { content: [{ type: "text", text: message }], details: undefined, isError: true };
}

export function createDesktopTools(
  run: DesktopCommandRunner = runDesktopCommand,
  observeAction?: (receipt: CommandReceipt) => void
): [
  ToolDefinition<typeof openUrlParameters>, ToolDefinition<typeof mediaControlParameters>
] {
  const openUrl: ToolDefinition<typeof openUrlParameters> = {
    name: "open_url",
    label: "Open URL",
    description: "Open an http or https URL in Omarchy's default browser. Use this instead of computer-use tooling when the user only wants a website opened.",
    promptSnippet: "Open a URL in the default Omarchy browser",
    parameters: openUrlParameters,
    async execute(_toolCallId, input, signal) {
      try {
        const url = normalizeOpenUrl(input.url);
        const startedAt = Date.now();
        await run("omarchy", ["launch", "browser", url], signal);
        observeAction?.({
          command: displayCommand("omarchy", ["launch", "browser", url]),
          exitCode: 0,
          durationMs: Math.max(0, Date.now() - startedAt)
        });
        return { content: [{ type: "text", text: "The requested page opened in the default browser." }], details: { url } };
      } catch (error) { return commandToolError("Opening the URL", error); }
    }
  };
  const mediaControl: ToolDefinition<typeof mediaControlParameters> = {
    name: "media_control",
    label: "Control media",
    description: "Control the active Omarchy MPRIS media player using the shell's media service.",
    promptSnippet: "Play, pause, skip, or switch the active media source",
    parameters: mediaControlParameters,
    async execute(_toolCallId, input, signal) {
      try {
        const method = omarchyMediaMethod(input.action);
        const startedAt = Date.now();
        const result = await run("omarchy-shell", ["media", method], signal);
        const output = `${result.stdout}\n${result.stderr}`.trim();
        if (output === "unhandled") return {
          content: [{ type: "text", text: "No active media player could handle that action." }],
          details: { action: input.action }, isError: true
        };
        if (output !== "ok") return {
          content: [{ type: "text", text: "The Omarchy media service returned an unexpected result." }],
          details: { action: input.action }, isError: true
        };
        observeAction?.({
          command: displayCommand("omarchy-shell", ["media", method]),
          exitCode: 0,
          durationMs: Math.max(0, Date.now() - startedAt)
        });
        return {
          content: [{ type: "text", text: `Media action ${input.action} completed.` }],
          details: { action: input.action }
        };
      } catch (error) { return commandToolError("The media action", error); }
    }
  };
  return [openUrl, mediaControl];
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

function createPermissionExtension(
  requestId: string,
  handler: PermissionHandler | undefined,
  approvals: PiApprovalState,
  webHandoffProvider: WebHandoffProvider = "duckduckgo"
): InlineExtension {
  return {
    name: "omapilot-permissions",
    hidden: true,
    factory: (pi) => {
      pi.on("tool_call", async (event) => {
        if (!requiresPiPermission(event.toolName)) return undefined;
        if (handler === undefined) return { block: true, reason: "OmaPilot did not provide a permission handler" };
        const rawInput = reviewableToolInput(event.toolName, event.input, webHandoffProvider);
        const risk = capabilityToolRisk(event.toolName);
        const oneShotOnly = oneShotCapabilityRisk(risk);
        const approvalKey = approvals.key(event.toolName, rawInput);
        if (approvals.denied(approvalKey)) return { block: true, reason: "This exact tool request is always denied" };
        if (!oneShotOnly && approvals.allowed(approvalKey)) return undefined;
        const options: RequestPermissionRequest["options"] = [
          { optionId: `allow-${event.toolCallId}`, name: "Allow once", kind: "allow_once" },
          ...(!oneShotOnly ? [
            { optionId: `session-${event.toolCallId}`, name: "Allow exact request for this session", kind: "allow_always" as const },
            { optionId: `always-${event.toolCallId}`, name: "Always allow exact request", kind: "allow_always" as const }
          ] : []),
          { optionId: `reject-${event.toolCallId}`, name: "Deny", kind: "reject_once" },
          { optionId: `reject-always-${event.toolCallId}`, name: "Always deny exact request", kind: "reject_always" }
        ];
        const request: RequestPermissionRequest = {
          sessionId: requestId,
          toolCall: {
            toolCallId: event.toolCallId,
            kind: "execute",
            title: toolTitle(event.toolName, event.input, webHandoffProvider),
            rawInput
          },
          options
        };
        const decision = await handler(request);
        const option = typeof decision === "string" ? decision : decision?.optionId;
        if (!oneShotOnly && option === `session-${event.toolCallId}`) approvals.allowSession(approvalKey);
        if (!oneShotOnly && option === `always-${event.toolCallId}`) approvals.allowAlways(approvalKey);
        if (option === `reject-always-${event.toolCallId}`) approvals.denyAlways(approvalKey);
        return option === `allow-${event.toolCallId}` || option === `session-${event.toolCallId}` || option === `always-${event.toolCallId}`
          ? undefined : { block: true, reason: "The user denied this tool call" };
      });
    }
  };
}

export function requiresPiPermission(toolName: string): boolean {
  return MUTATING_TOOLS.has(toolName) || capabilityToolRisk(toolName) !== undefined;
}

function oneShotCapabilityRisk(risk: CapabilityRisk | undefined): boolean {
  return risk === "external_write" || risk === "destructive" || risk === "setup";
}

function reviewableToolInput(
  name: string,
  input: Record<string, unknown>,
  webHandoffProvider: WebHandoffProvider
): Record<string, unknown> {
  const capabilityInput = capabilityReviewableInput(name, input);
  if (capabilityInput !== undefined) return capabilityInput;
  if (name === "bash") return { ...input, command: typeof input.command === "string" ? input.command : "" };
  if (name === "web_handoff") return webHandoffApproval(webHandoffProvider, input.query);
  if (name === "open_url") {
    const url = typeof input.url === "string" ? input.url : "";
    return { command: `omarchy launch browser ${url}`, url };
  }
  if (name === "media_control") {
    const action = typeof input.action === "string" ? input.action : "";
    let method = action;
    try { method = omarchyMediaMethod(action); } catch { /* Keep malformed input reviewable. */ }
    return { command: `omarchy-shell media ${method}`, action };
  }
  const desktopInput = reviewDesktopToolInput(name, input);
  if (desktopInput !== undefined) return desktopInput;
  const path = typeof input.path === "string" ? input.path : "unknown";
  return { command: `${name} ${path}`, ...input };
}

function toolTitle(name: string, input: Record<string, unknown>, webHandoffProvider: WebHandoffProvider): string {
  const capabilityTitle = capabilityToolTitle(name, input);
  if (capabilityTitle !== undefined) return capabilityTitle;
  if (name === "bash") return "Run a command";
  if (name === "web_handoff") return webHandoffTitle(webHandoffProvider);
  if (name === "open_url") return "Open URL in default browser";
  if (name === "media_control") return `Control media: ${typeof input.action === "string" ? input.action : "action"}`;
  const desktopTitle = desktopToolTitle(name, input);
  if (desktopTitle !== undefined) return desktopTitle;
  const path = typeof input.path === "string" ? basename(input.path) : "file";
  return `${name === "write" ? "Write" : "Edit"} ${path}`;
}

export function existingSkillPaths(directory: string, cwd: string, home = homedir()): string[] {
  const candidates = [
    join(directory, "skills"),
    join(home, ".pi/agent/skills"),
    join(cwd, ".agents/skills"),
    join(cwd, ".pi/skills")
  ];
  return [...new Set(candidates.filter((path) => existsSync(path)))];
}

export function bundledSkillPaths(): string[] {
  const path = resolve(pluginRoot(import.meta.url), "skills");
  return existsSync(path) ? [path] : [];
}

function allSkillPaths(provider: PiDiscoveredProvider): string[] {
  return [
    ...existingSkillPaths(provider.sharedAgentsDir, provider.cwd, provider.agent.env.HOME ?? homedir()),
    ...bundledSkillPaths()
  ];
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
    .map((item) => item.trim()).filter((item) => AGENT_PROFILE_TOOLS.includes(item));
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
        additionalSkillPaths: allSkillPaths(provider),
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
  const turnStartIndex = session.state.messages.length;
  try {
    if (abortPromise !== undefined) {
      await abortPromise;
      throw new BrokerPiError("cancelled", "The request was cancelled", false);
    }
    await session.prompt(task);
    if (activeSignals.some((signal) => signal.aborted))
      throw new BrokerPiError("cancelled", "The request was cancelled", false);
    const terminal = terminalAssistantMessage(session.state.messages.slice(turnStartIndex));
    const terminalError = terminalAssistantError(terminal);
    if (terminalError !== undefined) throw terminalError;
    return assistantText(terminal);
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

function terminalAssistantMessage(messages: readonly unknown[]): Record<string, unknown> | undefined {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (isObject(message) && message.role === "assistant") return message;
  }
  return undefined;
}

function assistantText(message: Record<string, unknown> | undefined): string {
  if (message === undefined || !Array.isArray(message.content)) return "";
  return message.content.filter((part) => isObject(part) && part.type === "text" && typeof part.text === "string")
    .map((part) => String((part as Record<string, unknown>).text)).join("");
}

function terminalAssistantError(message: Record<string, unknown> | undefined): BrokerPiError | undefined {
  if (message === undefined) return undefined;
  const stopReason = typeof message.stopReason === "string" ? message.stopReason : "";
  const diagnostic = typeof message.errorMessage === "string" ? message.errorMessage : "";
  if (stopReason === "aborted") return new BrokerPiError("cancelled", "The request was cancelled", false);
  if (stopReason !== "error" && diagnostic === "") {
    if (stopReason === "stop") return undefined;
    if (stopReason === "length") {
      return new BrokerPiError("incomplete_response", "The model stopped before producing a complete answer", true);
    }
    return new BrokerPiError("incomplete_response", "The model did not finish the current turn", true);
  }
  if (/api key|credential|unauthorized|authentication|\bauth\b|login/iu.test(diagnostic)) {
    return new BrokerPiError("authentication_required", "Authentication for this provider is missing or expired", false);
  }
  if (/ChatCompletionRequest|output_text|function_call_output|tool.*validation/iu.test(diagnostic)) {
    return new BrokerPiError(
      "provider_incompatible",
      "The provider rejected the tool conversation format. Use its chat/completions API or choose another model.",
      false
    );
  }
  if (/\b(?:400|404|405|422)\b|bad request|invalid request/iu.test(diagnostic)) {
    return new BrokerPiError("provider_request_rejected", "The provider rejected this request", false);
  }
  const retryable = /overloaded|rate.?limit|too many requests|\b(?:408|409|429)\b|\b5\d\d\b|service.?unavailable|network|connection|fetch failed|timed? out|timeout|socket|stream ended/iu.test(diagnostic);
  return new BrokerPiError(
    retryable ? "provider_temporarily_unavailable" : "agent_failed",
    retryable ? "The provider is temporarily unavailable after a retry" : "The Pi harness could not complete the request",
    retryable
  );
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

import { readFileSync } from "node:fs";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { HarnessId, ProviderId, ProviderInfo, ProviderPolicyInfo } from "./types.js";
import type { ModelRuntime } from "../../node_modules/@earendil-works/pi-coding-agent/dist/core/model-runtime.js";
import { quickchatPaths } from "./paths.js";
import { resolveExecutable, runCommand, stripAnsi } from "./process.js";

export type AgentCommand = { executable: string; args: string[]; env: NodeJS.ProcessEnv };
export type DiscoveredProvider = ProviderInfo & {
  kind?: "acp" | "pi";
  harnessPath: string;
  agent: AgentCommand;
  lockdownFeatures?: string[];
};
export type AcpDiscoveredProvider = DiscoveredProvider;
export type PiDiscoveredProvider = DiscoveredProvider & {
  kind: "pi";
  runtime: ModelRuntime;
  piProviderIds: string[];
  agentDir: string;
  sharedAgentsDir: string;
  cwd: string;
};

export function isPiProvider(provider: DiscoveredProvider): provider is PiDiscoveredProvider {
  return provider.kind === "pi" && "runtime" in provider && "piProviderIds" in provider;
}

const OPEN_CODE_PERMISSION = {
  "*": "deny",
  skill: "allow",
  websearch: "allow",
  external_directory: "allow",
  bash: "ask",
  read: "deny",
  glob: "deny",
  grep: "deny",
  edit: "deny",
  write: "deny",
  apply_patch: "deny",
  task: "deny",
  webfetch: "deny",
  question: "deny",
  plan_enter: "deny",
  plan_exit: "deny",
  todowrite: "deny",
  todoread: "deny",
  lsp: "deny"
} as const;

const providerNames: Record<ProviderId, string> = {
  builtin: "Built-in (OmaPilot)",
  codex: "Codex",
  claude: "Claude",
  opencode: "OpenCode"
};

const providerPolicies: Record<ProviderId, ProviderPolicyInfo> = {
  builtin: { tools: "device-approval", web: "approved-command", hostReads: true },
  codex: { tools: "device-approval", web: "approved-command", hostReads: true },
  claude: { tools: "device-approval", web: "search", hostReads: false },
  opencode: { tools: "device-approval", web: "search", hostReads: false }
};

async function isExecutable(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function repoRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "../..");
}

export function automaticInstructionPath(): string {
  return resolve(repoRoot(), "runtime/policies/automatic.md");
}

export function automaticInstructions(): string {
  return readFileSync(automaticInstructionPath(), "utf8").trim();
}

export function openCodePolicyEnvironment(env: NodeJS.ProcessEnv, disabledMcp: string[] = []): NodeJS.ProcessEnv {
  const permission = { ...OPEN_CODE_PERMISSION };
  const config = {
    default_agent: "build",
    instructions: [automaticInstructionPath()],
    skills: { urls: [] },
    agent: { build: { permission } },
    mcp: Object.fromEntries(disabledMcp.map((name) => [name, false]))
  };
  return {
    ...env,
    OPENCODE_CONFIG_CONTENT: JSON.stringify(config),
    OPENCODE_DISABLE_PROJECT_CONFIG: "1",
    OPENCODE_PERMISSION: JSON.stringify(permission)
  };
}

async function adapterExecutable(provider: "codex" | "claude", env: NodeJS.ProcessEnv): Promise<string | undefined> {
  const explicit = env[provider === "codex" ? "QUICKCHAT_CODEX_ACP" : "QUICKCHAT_CLAUDE_ACP"];
  const binary = provider === "codex" ? "codex-acp" : "claude-agent-acp";
  const paths = quickchatPaths(env);
  const candidates = [
    explicit,
    resolve(repoRoot(), `runtime/bin/${binary}`),
    resolve(repoRoot(), `node_modules/.bin/${binary}`),
    resolve(paths.adapters, `${provider}/current/bin/${binary}`)
  ];
  for (const candidate of candidates) {
    if (candidate !== undefined && await isExecutable(candidate)) return candidate;
  }
  return undefined;
}

async function authenticated(provider: ProviderId, path: string, env: NodeJS.ProcessEnv): Promise<boolean> {
  if (provider === "codex") {
    return (await runCommand(path, ["login", "status"], { env, timeoutMs: 8_000, maxOutput: 64_000 })).code === 0;
  }
  if (provider === "claude") {
    const result = await runCommand(path, ["auth", "status"], { env, timeoutMs: 8_000, maxOutput: 64_000 });
    if (result.code !== 0) return false;
    try {
      const value: unknown = JSON.parse(result.stdout);
      return typeof value === "object" && value !== null && "loggedIn" in value && value.loggedIn === true;
    } catch {
      return false;
    }
  }
  const result = await runCommand(path, ["--pure", "auth", "list"], { env, timeoutMs: 8_000, maxOutput: 64_000 });
  const output = stripAnsi(result.stdout + result.stderr);
  return result.code === 0 && /Credentials/u.test(output) && /(?:●|oauth|api)/iu.test(output);
}

async function version(path: string, env: NodeJS.ProcessEnv): Promise<string | undefined> {
  const result = await runCommand(path, ["--version"], { env, timeoutMs: 5_000, maxOutput: 4_096 });
  if (result.code !== 0) return undefined;
  const safe = stripAnsi(result.stdout).trim().split("\n")[0]?.replaceAll(/[^a-zA-Z0-9._+ -]/g, "").slice(0, 80);
  return safe === "" ? undefined : safe;
}

function agentEnvironment(provider: ProviderId, harnessPath: string, env: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  if (provider === "codex") {
    return { ...env, CODEX_PATH: harnessPath, INITIAL_AGENT_MODE: "read-only", NO_BROWSER: "1" };
  }
  if (provider === "claude") return { ...env, CLAUDE_CODE_EXECUTABLE: harnessPath };
  return openCodePolicyEnvironment(env);
}

export async function discoverProviders(
  env: NodeJS.ProcessEnv = process.env,
  harness: HarnessId = "builtin"
): Promise<DiscoveredProvider[]> {
  if (harness === "builtin") {
    try {
      if (env.QUICKCHAT_DISABLE_PI === "1") return [];
      const { discoverPiProviders } = await import("./pi-harness.js");
      const providers = await discoverPiProviders(env);
      return providers;
    } catch (error) {
      if (env.QUICKCHAT_DEBUG_PI === "1") {
        const detail = error instanceof Error ? `${error.name}: ${error.message}` : "unknown error";
        process.stderr.write(`OmaPilot Pi discovery failed: ${detail.replaceAll(/[\u0000-\u001f\u007f-\u009f]/gu, " ").slice(0, 500)}\n`);
      }
      return [];
    }
  }

  const requested = harness;
  const found: DiscoveredProvider[] = [];
  for (const id of ["codex", "claude", "opencode"] satisfies ProviderId[]) {
    if (id !== requested) continue;
    const harnessPath = await resolveExecutable(id, env);
    if (harnessPath === undefined || !await authenticated(id, harnessPath, env)) continue;
    let executable: string | undefined;
    let args: string[];
    if (id === "opencode") {
      executable = harnessPath;
      args = ["--pure", "acp"];
    } else {
      executable = await adapterExecutable(id, env);
      args = [];
    }
    if (executable === undefined) continue;
    const lockdownFeatures = id === "codex" ? await codexToolLockdownFeatures(harnessPath, env) : undefined;
    if (id === "codex" && lockdownFeatures === undefined) continue;
    // Automatic Codex requires the complete reviewed command and skill boundary. Do not
    // advertise a degraded text-only Codex provider if the installed harness
    // cannot prove the reviewed execution and skill features under strict configuration.
    if (id === "codex" && (
      lockdownFeatures?.includes("shell_tool") !== true
      || !lockdownFeatures.includes("unified_exec")
      || !lockdownFeatures.includes("skill_search")
    )) continue;
    let agentEnv = agentEnvironment(id, harnessPath, env);
    if (id === "opencode") {
      const hardened = await validatedOpenCodeEnvironment(harnessPath, agentEnv);
      if (hardened === undefined) continue;
      agentEnv = hardened;
    }
    const providerVersion = await version(harnessPath, env);
    found.push({
      kind: "acp",
      id,
      name: providerNames[id],
      ...(providerVersion === undefined ? {} : { version: providerVersion }),
      models: [],
      policy: providerPolicies[id],
      harnessPath,
      agent: { executable, args, env: agentEnv },
      ...(lockdownFeatures === undefined ? {} : { lockdownFeatures })
    });
  }
  return found;
}

async function validatedOpenCodeEnvironment(path: string, baseEnv: NodeJS.ProcessEnv): Promise<NodeJS.ProcessEnv | undefined> {
  const first = await resolvedOpenCodeConfig(path, baseEnv);
  if (first === undefined) return undefined;
  const disabledMcp = isObject(first.mcp) ? Object.keys(first.mcp) : [];
  const env = openCodePolicyEnvironment(baseEnv, disabledMcp);
  const resolved = await resolvedOpenCodeConfig(path, env);
  return resolved !== undefined && openCodeConfigIsHardened(resolved) ? env : undefined;
}

async function resolvedOpenCodeConfig(path: string, env: NodeJS.ProcessEnv): Promise<Record<string, unknown> | undefined> {
  const result = await runCommand(path, ["--pure", "debug", "config"], {
    env,
    timeoutMs: 15_000,
    maxOutput: 5 * 1024 * 1024
  });
  if (result.code !== 0) return undefined;
  const output = stripAnsi(result.stdout);
  const start = output.indexOf("{");
  if (start < 0) return undefined;
  try {
    const parsed: unknown = JSON.parse(output.slice(start));
    return isObject(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function openCodeConfigIsHardened(config: Record<string, unknown>): boolean {
  if (config.default_agent !== "build") return false;
  if (!permissionRecordIsHardened(config.permission)) return false;
  const agent = isObject(config.agent) ? config.agent : undefined;
  const build = agent !== undefined && isObject(agent.build) ? agent.build : undefined;
  if (build === undefined || !permissionRecordIsHardened(build.permission)) return false;
  if (isObject(config.mcp) && Object.values(config.mcp).some((value) => value !== false)) return false;
  const skills = isObject(config.skills) ? config.skills : undefined;
  if (skills === undefined || !Array.isArray(skills.urls) || skills.urls.length !== 0) return false;
  return Array.isArray(config.instructions) && config.instructions.includes(automaticInstructionPath());
}

function permissionRecordIsHardened(value: unknown): boolean {
  if (!isObject(value)) return false;
  for (const [name, action] of Object.entries(value)) {
    const reviewed = OPEN_CODE_PERMISSION[name as keyof typeof OPEN_CODE_PERMISSION];
    if (reviewed !== undefined) {
      if (action !== reviewed) return false;
      continue;
    }
    if (typeof action === "string") {
      if (action !== "deny") return false;
      continue;
    }
    if (!isObject(action) || Object.values(action).some((nested) => nested !== "deny")) return false;
  }
  return Object.entries(OPEN_CODE_PERMISSION).every(([name, action]) => value[name] === action);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function codexToolLockdownFeatures(path: string, env: NodeJS.ProcessEnv): Promise<string[] | undefined> {
  const listed = await runCommand(path, ["features", "list"], {
    env,
    timeoutMs: 10_000,
    maxOutput: 256_000
  });
  if (listed.code !== 0) return undefined;
  const output = stripAnsi(listed.stdout);
  const features = [...new Set(output.split("\n").map((line) => /^([a-z][a-z0-9_]*)\s/u.exec(line)?.[1]).filter((feature): feature is string => feature !== undefined))];
  if (features.length === 0) return undefined;
  const featureArguments = features.flatMap((feature) => ["-c", `features.${feature}=false`]);
  const validated = await runCommand(path, ["app-server", "--strict-config", ...featureArguments, "--listen", "stdio://"], {
    env,
    timeoutMs: 10_000,
    maxOutput: 64_000
  });
  return validated.code === 0 ? features : undefined;
}

export async function fallbackModels(provider: DiscoveredProvider): Promise<Array<{ id: string; name: string }>> {
  if (provider.id !== "opencode") return [];
  const result = await runCommand(provider.harnessPath, ["--pure", "models"], {
    env: provider.agent.env,
    timeoutMs: 15_000,
    maxOutput: 2_000_000
  });
  if (result.code !== 0) return [];
  return [...new Set(stripAnsi(result.stdout).split("\n").map((line) => line.trim()).filter((line) => /^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.:/+-]+$/u.test(line)))]
    .map((id) => ({ id, name: id }));
}

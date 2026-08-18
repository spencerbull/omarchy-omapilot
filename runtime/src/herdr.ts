import { spawn } from "node:child_process";
import type { ChatRecord, ProviderId } from "./types.js";
import { quickchatPaths } from "./paths.js";
import { resolveExecutable, runCommand } from "./process.js";

type HerdrCommand = { executable: string; args: string[] };
type RunResult = { code: number; stdout: string; stderr: string };
type CommandRunner = (executable: string, args: string[]) => Promise<RunResult>;
type WindowLauncher = (executable: string, args: string[], env: NodeJS.ProcessEnv) => Promise<void>;
type ExecutableResolver = (name: string, env: NodeJS.ProcessEnv) => Promise<string | undefined>;
type Delay = (milliseconds: number) => Promise<void>;

export type HerdrHandoffStage = "availability" | "launch" | "workspace" | "session" | "transcript" | "focus";

export class HerdrHandoffError extends Error {
  readonly stage: HerdrHandoffStage;
  readonly errorCode: string;

  constructor(stage: HerdrHandoffStage, errorCode: string) {
    super(herdrErrorMessage(stage, errorCode));
    this.name = "HerdrHandoffError";
    this.stage = stage;
    this.errorCode = errorCode;
  }
}

export type HerdrDependencies = {
  run?: CommandRunner;
  launch?: WindowLauncher;
  resolve?: ExecutableResolver;
  delay?: Delay;
};

type HerdrTarget = { workspaceId: string; tabId: string; paneId: string };
type ExistingAgent = HerdrTarget & { name: string };
type ResolvedHerdr = { herdr: string; launcher: string; tuiLauncher: string; hyprctl: string };

const HERDR_WINDOW_PATTERN = "herdr";

function parseJson(output: string): unknown {
  try {
    return JSON.parse(output);
  } catch {
    return undefined;
  }
}

function parseResult(output: string): unknown {
  const envelope = parseJson(output);
  return typeof envelope === "object" && envelope !== null && "result" in envelope ? envelope.result : undefined;
}

function objectValue(value: unknown, key: string): unknown {
  if (typeof value !== "object" || value === null) return undefined;
  return Object.entries(value).find(([entryKey]) => entryKey === key)?.[1];
}

function objectString(value: unknown, key: string): string | undefined {
  const entry = objectValue(value, key);
  return typeof entry === "string" ? entry : undefined;
}

function nestedObject(value: unknown, key: string): unknown {
  return objectValue(value, key);
}

function nestedArray(value: unknown, key: string): unknown[] | undefined {
  const entry = objectValue(value, key);
  return Array.isArray(entry) ? entry : undefined;
}

export function nativeResumeArgs(
  provider: ProviderId,
  sessionId: string,
  cwd = process.cwd(),
  env: NodeJS.ProcessEnv = process.env
): string[] | undefined {
  // Continue in Herdr deliberately hands authority back to the native harness.
  // Keep Codex interactive so any command outside its read-only sandbox still
  // requires the user's approval in Herdr.
  if (provider === "codex") return ["resume", sessionId, "-C", cwd, "-s", "read-only", "-a", "on-request"];
  if (provider === "claude") return ["--resume", sessionId];
  if (provider === "builtin") return ["--session", sessionId, "--session-dir", quickchatPaths(env).piSessions, "--approve"];
  return ["--pure", "--session", sessionId];
}

export function transcriptPrompt(chat: ChatRecord): string {
  return [
    "Continue this Quickchat conversation. The prior session could not be attached natively, so this is a transcript handoff.",
    "",
    "## Question",
    chat.question,
    "",
    "## Answer",
    chat.answer,
    "",
    "Continue from this context and wait for my next instruction."
  ].join("\n");
}

export async function continueInHerdr(
  chat: ChatRecord,
  env: NodeJS.ProcessEnv = process.env,
  dependencies: HerdrDependencies = {}
): Promise<{ mode: "native" | "transcript"; reused: boolean }> {
  const resolve = dependencies.resolve ?? resolveExecutable;
  const [herdr, launcher, tuiLauncher, hyprctl] = await Promise.all([
    resolve("herdr", env),
    resolve("omarchy-launch-or-focus", env),
    resolve("omarchy-launch-tui", env),
    resolve("hyprctl", env)
  ]);
  if (herdr === undefined) throw new HerdrHandoffError("availability", "herdr_missing");
  if (launcher === undefined || tuiLauncher === undefined || hyprctl === undefined)
    throw new HerdrHandoffError("availability", "omarchy_launcher_missing");
  const commands: ResolvedHerdr = { herdr, launcher, tuiLauncher, hyprctl };
  const run = dependencies.run ?? (async (executable, args) => runCommand(executable, args, {
    env, timeoutMs: 35_000, maxOutput: 256_000
  }));
  const launch = dependencies.launch ?? launchDetached;
  const wait = dependencies.delay ?? delay;

  const existingWindowAddress = await findHerdrWindow(commands.hyprctl, run);
  if (existingWindowAddress === undefined)
    await openOrFocusHerdr(commands, env, launch, "launch_spawn_failed");
  const listed = await waitForHerdr(run, commands.herdr, wait);
  if (listed.code !== 0) throw new HerdrHandoffError("launch", herdrCliErrorCode(listed) ?? "api_unavailable");
  const windowAddress = existingWindowAddress ?? await waitForHerdrWindow(commands.hyprctl, run, wait);
  if (windowAddress === undefined)
    throw new HerdrHandoffError("launch", "window_not_mapped");

  const agentName = `quickchat-${chat.id.slice(0, 8)}`;
  const transcriptAgentName = `${agentName}-context`;
  const existingAgents = await run(commands.herdr, ["agent", "list"]);
  if (existingAgents.code !== 0)
    throw new HerdrHandoffError("session", herdrCliErrorCode(existingAgents) ?? "agent_list_failed");
  const existing = findExistingAgent(parseResult(existingAgents.stdout), [agentName, transcriptAgentName]);
  if (existing !== undefined) {
    await focusSessionAndWindow(commands, existing, existing.name, windowAddress, run, wait);
    return { mode: existing.name === transcriptAgentName ? "transcript" : nativeMode(chat), reused: true };
  }

  const savedCwd = chat.session.cwd?.trim();
  const homeCwd = env.HOME?.trim();
  const cwd = savedCwd !== undefined && savedCwd.length > 0
    ? savedCwd
    : homeCwd !== undefined && homeCwd.length > 0 ? homeCwd : process.cwd();
  const createdTabs: string[] = [];
  let handoffStarted = false;
  try {
    let target = await createHandoffTarget(parseResult(listed.stdout), commands.herdr, cwd, chat.title, run, createdTabs);
    const workspaceId = target.workspaceId;
    const resume = !chat.session.resumable || chat.session.acpId === undefined
      ? undefined
      : nativeResumeArgs(chat.provider, chat.session.acpId, cwd, env);
    let mode: "native" | "transcript" = resume === undefined ? "transcript" : "native";
    const initialAgentName = resume === undefined ? transcriptAgentName : agentName;
    await prepareAgentPane(commands.herdr, chat.provider, target.paneId, env, run, wait);
    let started = await startAgent(commands.herdr, chat.provider, initialAgentName, target.paneId, resume, run, wait);

    if (started.code !== 0) {
      const racedAgents = await run(commands.herdr, ["agent", "list"]);
      const raced = racedAgents.code === 0 ? findExistingAgent(parseResult(racedAgents.stdout), [agentName]) : undefined;
      if (raced !== undefined) {
        handoffStarted = true;
        await rollbackCreatedTabs(commands.herdr, createdTabs, run, wait);
        await focusSessionAndWindow(commands, raced, agentName, windowAddress, run, wait);
        return { mode: nativeMode(chat), reused: true };
      }
      if (resume === undefined)
        throw new HerdrHandoffError("session", herdrCliErrorCode(started) ?? "agent_start_failed");

      mode = "transcript";
      const nativeTabId = target.tabId;
      target = await createTabTarget(commands.herdr, workspaceId, cwd, chat.title, run, createdTabs);
      await prepareAgentPane(commands.herdr, chat.provider, target.paneId, env, run, wait);
      started = await startAgent(commands.herdr, chat.provider, transcriptAgentName, target.paneId, undefined, run, wait);
      if (started.code !== 0)
        throw new HerdrHandoffError("session", herdrCliErrorCode(started) ?? "agent_start_failed");
      await closeCreatedTab(commands.herdr, nativeTabId, createdTabs, run, wait);
    }

    handoffStarted = true;
    if (mode === "transcript") {
      const prompted = await run(commands.herdr, [
        "agent", "prompt", transcriptAgentName, transcriptPrompt(chat), "--wait",
        "--until", "idle", "--until", "done", "--until", "blocked", "--timeout", "30000"
      ]);
      if (prompted.code !== 0) {
        await rollbackCreatedTabs(commands.herdr, createdTabs, run, wait);
        throw new HerdrHandoffError("transcript", herdrCliErrorCode(prompted) ?? "prompt_failed");
      }
    }
    const focusedAgentName = mode === "transcript" ? transcriptAgentName : agentName;
    await focusSessionAndWindow(commands, target, focusedAgentName, windowAddress, run, wait);
    return { mode, reused: false };
  } catch (error) {
    if (!handoffStarted) await rollbackCreatedTabs(commands.herdr, createdTabs, run, wait);
    throw error;
  }
}

export async function launchDetached(executable: string, args: string[], env: NodeJS.ProcessEnv): Promise<void> {
  await new Promise<void>((resolveLaunch, rejectLaunch) => {
    const child = spawn(executable, args, { env, stdio: "ignore", detached: true });
    child.once("error", rejectLaunch);
    child.once("spawn", () => {
      child.unref();
      resolveLaunch();
    });
  });
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

async function openOrFocusHerdr(
  commands: ResolvedHerdr,
  env: NodeJS.ProcessEnv,
  launch: WindowLauncher,
  errorCode: string
): Promise<void> {
  const command = herdrLauncherCommand(commands.herdr, commands.launcher, commands.tuiLauncher);
  try {
    await launch(command.executable, command.args, env);
  } catch {
    throw new HerdrHandoffError("launch", errorCode);
  }
}

async function waitForHerdr(run: CommandRunner, herdr: string, wait: Delay): Promise<RunResult> {
  let result = await run(herdr, ["workspace", "list"]);
  for (let attempt = 0; result.code !== 0 && attempt < 23; attempt += 1) {
    await wait(250);
    result = await run(herdr, ["workspace", "list"]);
  }
  return result;
}

async function waitForHerdrWindow(hyprctl: string, run: CommandRunner, wait: Delay): Promise<string | undefined> {
  for (let attempt = 0; attempt < 48; attempt += 1) {
    const address = await findHerdrWindow(hyprctl, run);
    if (address !== undefined) return address;
    if (attempt < 47) await wait(250);
  }
  return undefined;
}

async function findHerdrWindow(hyprctl: string, run: CommandRunner): Promise<string | undefined> {
  const active = await run(hyprctl, ["activewindow", "-j"]);
  const address = active.code === 0 ? herdrWindowAddress(parseJson(active.stdout)) : undefined;
  if (address !== undefined) return address;
  // A Quickshell layer surface can retain keyboard focus while Herdr is
  // already mapped. Check all clients before invoking the launcher so an
  // existing Herdr window is focused instead of opening a duplicate.
  const clients = await run(hyprctl, ["clients", "-j"]);
  return clients.code === 0 ? herdrClientAddress(parseJson(clients.stdout)) : undefined;
}

async function waitForActiveHerdrWindow(hyprctl: string, address: string, run: CommandRunner, wait: Delay): Promise<boolean> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const active = await run(hyprctl, ["activewindow", "-j"]);
    if (active.code === 0 && objectString(parseJson(active.stdout), "address") === address) return true;
    if (attempt < 19) await wait(100);
  }
  return false;
}

function herdrWindowAddress(window: unknown): string | undefined {
  const windowClass = objectString(window, "class")?.toLowerCase();
  const title = objectString(window, "title")?.toLowerCase();
  const address = objectString(window, "address");
  if ((windowClass === "org.omarchy.herdr" || (windowClass === "kitty" && title === "herdr"))
    && address !== undefined && /^0x[0-9a-f]+$/i.test(address))
    return address;
  return undefined;
}

function herdrClientAddress(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  const mapped = value.filter((client) => objectValue(client, "mapped") !== false);
  const official = mapped.find((client) => objectString(client, "class")?.toLowerCase() === "org.omarchy.herdr");
  return herdrWindowAddress(official) ?? mapped.map(herdrWindowAddress).find((address) => address !== undefined);
}

async function createHandoffTarget(
  listResult: unknown,
  herdr: string,
  cwd: string,
  title: string,
  run: CommandRunner,
  createdTabs: string[]
): Promise<HerdrTarget> {
  const existing = findQuickchatWorkspace(listResult);
  if (existing !== undefined) return createTabTarget(herdr, existing, cwd, title, run, createdTabs);
  const created = await run(herdr, ["workspace", "create", "--cwd", cwd, "--label", "Quickchat", "--no-focus"]);
  if (created.code !== 0)
    throw new HerdrHandoffError("workspace", herdrCliErrorCode(created) ?? "workspace_create_failed");
  const createdResult = parseResult(created.stdout);
  const tabId = objectString(nestedObject(createdResult, "tab"), "tab_id") ?? objectString(createdResult, "tab_id");
  const paneId = objectString(nestedObject(createdResult, "root_pane"), "pane_id");
  const workspaceId = objectString(nestedObject(createdResult, "workspace"), "workspace_id")
    ?? objectString(createdResult, "workspace_id")
    ?? workspaceFromTab(tabId);
  if (workspaceId === undefined || tabId === undefined || paneId === undefined)
    throw new HerdrHandoffError("workspace", "incomplete_workspace_target");
  createdTabs.push(tabId);
  await run(herdr, ["tab", "rename", tabId, title.slice(0, 60)]);
  return { workspaceId, tabId, paneId };
}

async function createTabTarget(
  herdr: string,
  workspaceId: string,
  cwd: string,
  title: string,
  run: CommandRunner,
  createdTabs: string[]
): Promise<HerdrTarget> {
  const created = await run(herdr, [
    "tab", "create", "--workspace", workspaceId, "--cwd", cwd,
    "--label", title.slice(0, 60), "--no-focus"
  ]);
  if (created.code !== 0)
    throw new HerdrHandoffError("workspace", herdrCliErrorCode(created) ?? "tab_create_failed");
  const result = parseResult(created.stdout);
  const tabId = objectString(nestedObject(result, "tab"), "tab_id") ?? objectString(result, "tab_id");
  const paneId = objectString(nestedObject(result, "root_pane"), "pane_id");
  if (tabId === undefined || paneId === undefined)
    throw new HerdrHandoffError("workspace", "incomplete_tab_target");
  createdTabs.push(tabId);
  return { workspaceId, tabId, paneId };
}

async function startAgent(
  herdr: string,
  provider: ProviderId,
  agentName: string,
  paneId: string,
  resume: string[] | undefined,
  run: CommandRunner,
  wait: Delay
): Promise<RunResult> {
  const kind = provider === "builtin" ? "pi" : provider;
  const args = ["agent", "start", agentName, "--kind", kind, "--pane", paneId, "--timeout", "30000"];
  if (resume !== undefined) args.push("--", ...resume);
  let result = await run(herdr, args);
  for (let attempt = 0; herdrCliErrorCode(result) === "agent_pane_busy" && attempt < 19; attempt += 1) {
    await wait(250);
    result = await run(herdr, args);
  }
  return result;
}

async function prepareAgentPane(
  herdr: string,
  provider: ProviderId,
  paneId: string,
  env: NodeJS.ProcessEnv,
  run: CommandRunner,
  wait: Delay
): Promise<void> {
  if (provider !== "builtin") return;
  const paths = quickchatPaths(env);
  const configured = await run(herdr, [
    "pane", "run", paneId,
    `export PI_CODING_AGENT_DIR=${shellWord(paths.config)} PI_CODING_AGENT_SESSION_DIR=${shellWord(paths.piSessions)}`
  ]);
  if (configured.code !== 0)
    throw new HerdrHandoffError("session", herdrCliErrorCode(configured) ?? "pi_environment_failed");
  await wait(100);
}

async function focusSessionAndWindow(
  commands: ResolvedHerdr,
  target: Pick<HerdrTarget, "workspaceId" | "tabId">,
  agentName: string,
  windowAddress: string,
  run: CommandRunner,
  wait: Delay
): Promise<void> {
  await runFocusCommands(commands.herdr, target.workspaceId, target.tabId, agentName, run);
  const raised = await run(commands.hyprctl, ["dispatch", `hl.dsp.focus({ window = "address:${windowAddress}" })`]);
  if (raised.code !== 0) throw new HerdrHandoffError("focus", "window_raise_failed");
  if (!await waitForActiveHerdrWindow(commands.hyprctl, windowAddress, run, wait))
    throw new HerdrHandoffError("focus", "window_not_focused");
  // Raising a previously attached client can restore that client's last target.
  // Reapply the API focus after the OS-level raise, then leave the Herdr window active.
  await runFocusCommands(commands.herdr, target.workspaceId, target.tabId, agentName, run);
  if (!await waitForActiveHerdrWindow(commands.hyprctl, windowAddress, run, wait))
    throw new HerdrHandoffError("focus", "window_focus_lost");
}

async function runFocusCommands(
  herdr: string,
  workspaceId: string,
  tabId: string,
  agentName: string,
  run: CommandRunner
): Promise<void> {
  for (const command of herdrSessionFocusCommands(herdr, workspaceId, tabId, agentName)) {
    const focused = await run(command.executable, command.args);
    if (focused.code !== 0)
      throw new HerdrHandoffError("focus", herdrCliErrorCode(focused) ?? `${command.args[0]}_focus_failed`);
  }
}

async function rollbackCreatedTabs(herdr: string, createdTabs: string[], run: CommandRunner, wait: Delay): Promise<void> {
  for (const tabId of [...createdTabs].reverse()) await closeCreatedTab(herdr, tabId, createdTabs, run, wait);
}

async function closeCreatedTab(herdr: string, tabId: string, createdTabs: string[], run: CommandRunner, wait: Delay): Promise<void> {
  let closed = await run(herdr, ["tab", "close", tabId]);
  for (let attempt = 0; closed.code !== 0 && attempt < 3; attempt += 1) {
    await wait(100);
    closed = await run(herdr, ["tab", "close", tabId]);
  }
  if (closed.code !== 0)
    throw new HerdrHandoffError("workspace", herdrCliErrorCode(closed) ?? "tab_cleanup_failed");
  const index = createdTabs.indexOf(tabId);
  if (index >= 0) createdTabs.splice(index, 1);
}

function workspaceFromTab(tabId: string | undefined): string | undefined {
  if (tabId === undefined) return undefined;
  const separator = tabId.indexOf(":");
  return separator > 0 ? tabId.slice(0, separator) : undefined;
}

function findQuickchatWorkspace(result: unknown): string | undefined {
  const workspaces = nestedArray(result, "workspaces");
  if (workspaces === undefined) return undefined;
  for (const workspace of workspaces) {
    if (objectString(workspace, "label")?.toLowerCase() === "quickchat") return objectString(workspace, "workspace_id");
  }
  return undefined;
}

function findExistingAgent(result: unknown, names: string[]): ExistingAgent | undefined {
  const agents = nestedArray(result, "agents");
  if (agents === undefined) return undefined;
  for (const agent of agents) {
    const name = objectString(agent, "name");
    if (name === undefined || !names.includes(name) || objectValue(agent, "interactive_ready") !== true) continue;
    const workspaceId = objectString(agent, "workspace_id");
    const tabId = objectString(agent, "tab_id");
    const paneId = objectString(agent, "pane_id");
    if (workspaceId !== undefined && tabId !== undefined && paneId !== undefined)
      return { name, workspaceId, tabId, paneId };
  }
  return undefined;
}

function nativeMode(chat: ChatRecord): "native" | "transcript" {
  return chat.session.resumable && chat.session.acpId !== undefined ? "native" : "transcript";
}

function herdrCliErrorCode(result: RunResult): string | undefined {
  for (const output of [result.stdout, result.stderr]) {
    const envelope = parseJson(output);
    const code = objectString(nestedObject(envelope, "error"), "code");
    if (code !== undefined && /^[a-z][a-z0-9_]{0,63}$/.test(code)) return code;
  }
  return undefined;
}

function shellWord(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

export function herdrLauncherCommand(herdr: string, launcher: string, tuiLauncher: string): HerdrCommand {
  const launchCommand = `${shellWord(tuiLauncher)} --app-id=org.omarchy.herdr ${shellWord(herdr)}`;
  return { executable: launcher, args: [HERDR_WINDOW_PATTERN, launchCommand] };
}

export function herdrFocusCommands(
  herdr: string,
  hyprctl: string,
  windowAddress: string,
  workspaceId: string,
  tabId: string,
  agentName: string
): HerdrCommand[] {
  return [
    ...herdrSessionFocusCommands(herdr, workspaceId, tabId, agentName),
    { executable: hyprctl, args: ["dispatch", `hl.dsp.focus({ window = "address:${windowAddress}" })`] },
    ...herdrSessionFocusCommands(herdr, workspaceId, tabId, agentName)
  ];
}

function herdrSessionFocusCommands(
  herdr: string,
  workspaceId: string,
  tabId: string,
  agentName: string
): HerdrCommand[] {
  return [
    { executable: herdr, args: ["workspace", "focus", workspaceId] },
    { executable: herdr, args: ["tab", "focus", tabId] },
    { executable: herdr, args: ["agent", "focus", agentName] }
  ];
}

export function describeHerdrError(error: unknown): {
  state: "unavailable" | "failed";
  message: string;
  stage?: HerdrHandoffStage;
  errorCode?: string;
} {
  if (!(error instanceof HerdrHandoffError))
    return { state: "failed", message: "Could not continue this chat in Herdr" };
  return {
    state: error.stage === "availability" ? "unavailable" : "failed",
    message: error.message,
    stage: error.stage,
    errorCode: error.errorCode
  };
}

function herdrErrorMessage(stage: HerdrHandoffStage, errorCode: string): string {
  if (stage === "availability")
    return errorCode === "herdr_missing" ? "Herdr is not installed" : "Omarchy's Herdr launcher is unavailable";
  if (stage === "launch") return "Herdr could not be opened";
  if (stage === "workspace") return "Herdr opened, but Quickchat could not prepare its workspace";
  if (stage === "session") return "Herdr opened, but the selected harness session could not be continued";
  if (stage === "transcript") return "Herdr opened, but the transcript handoff could not be sent";
  return "The session opened in Herdr, but Quickchat could not focus it";
}

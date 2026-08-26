import { accessSync, constants, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { execFile, spawn } from "node:child_process";
import { homedir } from "node:os";
import { delimiter, join, relative, sep } from "node:path";
import { Type } from "typebox";
import type { ToolDefinition } from "../../../node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.js";
import type { CommandReceipt } from "../types.js";

const MAX_COMMAND_OUTPUT = 512 * 1024;
const MAX_DESKTOP_FILE_BYTES = 256 * 1024;
const MAX_WINDOWS = 200;
const MAX_WORKSPACES = 100;
const MAX_MONITORS = 32;
const MAX_DIRECTORY_ENTRIES = 5_000;
const MAX_CATALOG_ENTRIES = 10_000;
const VERIFY_ATTEMPTS = 30;
const VERIFY_DELAY_MS = 50;
const APP_VERIFY_ATTEMPTS = 40;
const APP_VERIFY_DELAY_MS = 50;
const SAFE_CLI_APP_ID = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,255}$/u;
const UNSAFE_DISPLAY_TEXT = /[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/u;

const appCatalogParameters = Type.Object({
  query: Type.Optional(Type.String({ description: "Optional app name or command to find; omit to browse installed apps", minLength: 1, maxLength: 128 })),
  kind: Type.Optional(Type.Union([Type.Literal("all"), Type.Literal("desktop"), Type.Literal("cli")])),
  limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 40 }))
});

const omarchyCommandsParameters = Type.Object({
  query: Type.Optional(Type.String({ description: "Optional command, task, or keyword to find", minLength: 1, maxLength: 128 })),
  group: Type.Optional(Type.String({ description: "Optional exact Omarchy command group, such as launch, menu, or theme", minLength: 1, maxLength: 64 })),
  limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 40 }))
});

const appOpenParameters = Type.Object({
  kind: Type.Union([Type.Literal("desktop"), Type.Literal("cli")]),
  id: Type.String({ description: "Exact ID returned by app_catalog", minLength: 1, maxLength: 256 }),
  mode: Type.Optional(Type.Union([
    Type.Literal("focus_or_launch"), Type.Literal("focus_existing"), Type.Literal("new_window")
  ]))
});

const desktopStateParameters = Type.Object({
  includeTitles: Type.Optional(Type.Boolean({
    description: "Include bounded window titles only when they are needed to identify the user's target"
  }))
});

const windowActionParameters = Type.Object({
  action: Type.Union([
    Type.Literal("focus"), Type.Literal("move_to_workspace"), Type.Literal("resize"),
    Type.Literal("set_floating"), Type.Literal("close")
  ]),
  address: Type.String({ description: "Exact 0x address returned by desktop_state", minLength: 3, maxLength: 32 }),
  pid: Type.Integer({ description: "Exact process ID returned with that window address", minimum: 1 }),
  workspace: Type.Optional(Type.Integer({ minimum: 1, maximum: 99 })),
  follow: Type.Optional(Type.Boolean({ description: "Follow the window to its destination workspace" })),
  width: Type.Optional(Type.Integer({ description: "Requested exact width in pixels", minimum: 100, maximum: 10_000 })),
  height: Type.Optional(Type.Integer({ description: "Requested exact height in pixels", minimum: 100, maximum: 10_000 })),
  enabled: Type.Optional(Type.Boolean({ description: "Desired state for set_floating" }))
});

const workspaceActionParameters = Type.Object({
  action: Type.Union([Type.Literal("focus"), Type.Literal("move_to_monitor")]),
  workspace: Type.Integer({ description: "Exact numbered workspace returned by desktop_state", minimum: 1, maximum: 99 }),
  monitor: Type.Optional(Type.String({ description: "Exact monitor name returned by desktop_state", minLength: 1, maxLength: 128 }))
});

export type DesktopCommandResult = { stdout: string; stderr: string };
export type DesktopCommandRunner = (
  file: string,
  args: string[],
  signal?: AbortSignal
) => Promise<DesktopCommandResult>;

export type InstalledApp = {
  kind: "desktop" | "cli";
  id: string;
  name: string;
  description?: string;
  startupWmClass?: string;
  terminal?: boolean;
};

export type OmarchyCommand = {
  route: string;
  summary: string;
  args?: string;
  aliases?: string[];
  requiresSudo: boolean;
};

export type DesktopWindow = {
  address: string;
  class?: string;
  initialClass?: string;
  title?: string;
  pid?: number;
  workspace?: number;
  monitor?: number;
  position?: [number, number];
  size?: [number, number];
  floating: boolean;
  fullscreen: number;
  pseudo: boolean;
  pinned: boolean;
  grouped: boolean;
  mapped: boolean;
  hidden: boolean;
};

export type DesktopWorkspace = {
  id?: number;
  name?: string;
  monitor?: string;
  monitorId?: number;
  windows?: number;
  hasFullscreen: boolean;
};

export type DesktopMonitor = {
  id?: number;
  name?: string;
  description?: string;
  focused: boolean;
  activeWorkspace?: number;
  position?: [number, number];
  size?: [number, number];
  scale?: number;
};

export type DesktopState = {
  activeWindow?: DesktopWindow;
  activeWorkspace?: DesktopWorkspace;
  monitors: DesktopMonitor[];
  workspaces: DesktopWorkspace[];
  windows: DesktopWindow[];
};

type AppOpenInput = {
  kind: "desktop" | "cli";
  id: string;
  mode?: "focus_or_launch" | "focus_existing" | "new_window";
};

export type WindowActionInput = {
  action: "focus" | "move_to_workspace" | "resize" | "set_floating" | "close";
  address: string;
  pid: number;
  workspace?: number;
  follow?: boolean;
  width?: number;
  height?: number;
  enabled?: boolean;
};

export type WorkspaceActionInput = {
  action: "focus" | "move_to_monitor";
  workspace: number;
  monitor?: string;
};

type Command = { file: "hyprctl"; args: string[] };
type ActionReceipt = {
  action: string;
  command?: string;
  target: Record<string, unknown>;
  requested: Record<string, unknown>;
  before: Record<string, unknown> | undefined;
  after: Record<string, unknown> | undefined;
  changed: boolean;
  verified: boolean;
};

export type ActionReceiptObserver = (receipt: CommandReceipt) => void;

export class DesktopToolError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "DesktopToolError";
    this.code = code;
  }
}

export const runDesktopCommand: DesktopCommandRunner = (file, args, signal) => new Promise((resolve, reject) => {
  execFile(file, args, {
    encoding: "utf8",
    maxBuffer: MAX_COMMAND_OUTPUT,
    timeout: 10_000,
    signal
  }, (error, stdout, stderr) => {
    if (error !== null) reject(error);
    else resolve({ stdout, stderr });
  });
});

export const launchDesktopCommand: DesktopCommandRunner = (file, args, signal) => new Promise((resolve, reject) => {
  if (signal?.aborted === true) {
    reject(signal.reason);
    return;
  }
  let settled = false;
  const child = spawn(file, args, { detached: true, stdio: "ignore" });
  const finish = (error?: Error): void => {
    if (settled) return;
    settled = true;
    signal?.removeEventListener("abort", abort);
    if (error === undefined) resolve({ stdout: "", stderr: "" });
    else reject(error);
  };
  const abort = (): void => {
    child.kill();
    finish(signal?.reason instanceof Error ? signal.reason : new Error("The app launch was cancelled"));
  };
  signal?.addEventListener("abort", abort, { once: true });
  child.once("error", finish);
  child.once("spawn", () => {
    child.unref();
    finish();
  });
});

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundedText(value: unknown, maximum = 240): string | undefined {
  return typeof value === "string" && value !== "" ? value.slice(0, maximum) : undefined;
}

function boundedInteger(value: unknown): number | undefined {
  return typeof value === "number" && Number.isInteger(value) ? value : undefined;
}

function boundedNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function point(value: unknown): [number, number] | undefined {
  if (!Array.isArray(value) || value.length < 2) return undefined;
  const x = boundedInteger(value[0]);
  const y = boundedInteger(value[1]);
  return x === undefined || y === undefined ? undefined : [x, y];
}

function jsonObject(output: string, subject: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(output);
    if (isObject(value)) return value;
  } catch { /* Return the stable error below. */ }
  throw new DesktopToolError("desktop_state_unavailable", `Hyprland returned invalid ${subject} state`);
}

function jsonObjects(output: string, subject: string): Array<Record<string, unknown>> {
  try {
    const value: unknown = JSON.parse(output);
    if (Array.isArray(value)) return value.filter(isObject);
  } catch { /* Return the stable error below. */ }
  throw new DesktopToolError("desktop_state_unavailable", `Hyprland returned invalid ${subject} state`);
}

function parseWindow(value: Record<string, unknown>, includeTitle: boolean): DesktopWindow | undefined {
  const address = normalizeWindowAddress(boundedText(value.address, 32));
  if (address === undefined) return undefined;
  const workspace = isObject(value.workspace) ? boundedInteger(value.workspace.id) : undefined;
  const windowClass = boundedText(value.class);
  const initialClass = boundedText(value.initialClass);
  const title = boundedText(value.title);
  const pid = boundedInteger(value.pid);
  const monitor = boundedInteger(value.monitor);
  const position = point(value.at);
  const size = point(value.size);
  return {
    address,
    ...(windowClass === undefined ? {} : { class: windowClass }),
    ...(initialClass === undefined ? {} : { initialClass }),
    ...(!includeTitle || title === undefined ? {} : { title }),
    ...(pid === undefined ? {} : { pid }),
    ...(workspace === undefined ? {} : { workspace }),
    ...(monitor === undefined ? {} : { monitor }),
    ...(position === undefined ? {} : { position }),
    ...(size === undefined ? {} : { size }),
    floating: value.floating === true,
    fullscreen: boundedInteger(value.fullscreen) ?? 0,
    pseudo: value.pseudo === true,
    pinned: value.pinned === true,
    grouped: Array.isArray(value.grouped) && value.grouped.length > 0,
    mapped: value.mapped === true,
    hidden: value.hidden === true
  };
}

function parseWorkspace(value: Record<string, unknown>): DesktopWorkspace {
  const id = boundedInteger(value.id);
  const name = boundedText(value.name, 80);
  const monitor = boundedText(value.monitor, 128);
  const monitorId = boundedInteger(value.monitorID);
  const windows = boundedInteger(value.windows);
  return {
    ...(id === undefined ? {} : { id }),
    ...(name === undefined ? {} : { name }),
    ...(monitor === undefined ? {} : { monitor }),
    ...(monitorId === undefined ? {} : { monitorId }),
    ...(windows === undefined ? {} : { windows }),
    hasFullscreen: value.hasfullscreen === true
  };
}

function parseMonitor(value: Record<string, unknown>): DesktopMonitor {
  const activeWorkspace = isObject(value.activeWorkspace) ? boundedInteger(value.activeWorkspace.id) : undefined;
  const id = boundedInteger(value.id);
  const name = boundedText(value.name, 128);
  const description = boundedText(value.description);
  const x = boundedInteger(value.x);
  const y = boundedInteger(value.y);
  const width = boundedInteger(value.width);
  const height = boundedInteger(value.height);
  const scale = boundedNumber(value.scale);
  return {
    ...(id === undefined ? {} : { id }),
    ...(name === undefined ? {} : { name }),
    ...(description === undefined ? {} : { description }),
    focused: value.focused === true,
    ...(activeWorkspace === undefined ? {} : { activeWorkspace }),
    ...(x === undefined || y === undefined ? {} : { position: [x, y] }),
    ...(width === undefined || height === undefined ? {} : { size: [width, height] }),
    ...(scale === undefined ? {} : { scale })
  };
}

export async function readDesktopState(
  run: DesktopCommandRunner = runDesktopCommand,
  includeTitles = false,
  signal?: AbortSignal
): Promise<DesktopState> {
  const [activeWindowResult, activeWorkspaceResult, monitorsResult, workspacesResult, clientsResult] = await Promise.all([
    run("hyprctl", ["-j", "activewindow"], signal),
    run("hyprctl", ["-j", "activeworkspace"], signal),
    run("hyprctl", ["-j", "monitors", "all"], signal),
    run("hyprctl", ["-j", "workspaces"], signal),
    run("hyprctl", ["-j", "clients"], signal)
  ]);
  const activeWindow = parseWindow(jsonObject(activeWindowResult.stdout, "active-window"), includeTitles);
  const activeWorkspace = parseWorkspace(jsonObject(activeWorkspaceResult.stdout, "active-workspace"));
  const windows = jsonObjects(clientsResult.stdout, "window").slice(0, MAX_WINDOWS)
    .map((value) => parseWindow(value, includeTitles)).filter((value): value is DesktopWindow => value !== undefined);
  return {
    ...(activeWindow === undefined ? {} : { activeWindow }),
    activeWorkspace,
    monitors: jsonObjects(monitorsResult.stdout, "monitor").slice(0, MAX_MONITORS).map(parseMonitor),
    workspaces: jsonObjects(workspacesResult.stdout, "workspace").slice(0, MAX_WORKSPACES).map(parseWorkspace),
    windows
  };
}

async function readDesktopWindows(
  run: DesktopCommandRunner,
  includeTitles: boolean,
  signal?: AbortSignal
): Promise<DesktopWindow[]> {
  const result = await run("hyprctl", ["-j", "clients"], signal);
  return jsonObjects(result.stdout, "window").slice(0, MAX_WINDOWS)
    .map((value) => parseWindow(value, includeTitles)).filter((value): value is DesktopWindow => value !== undefined);
}

function desktopAppDirectories(env: NodeJS.ProcessEnv): string[] {
  const home = env.HOME ?? homedir();
  const configuredDataHome = env.XDG_DATA_HOME?.trim();
  const configuredDataDirectories = env.XDG_DATA_DIRS?.trim();
  const dataHome = configuredDataHome === undefined || configuredDataHome === "" ? join(home, ".local/share") : configuredDataHome;
  const dataDirectories = (configuredDataDirectories === undefined || configuredDataDirectories === ""
    ? "/usr/local/share:/usr/share" : configuredDataDirectories).split(":");
  return [...new Set([dataHome, ...dataDirectories].filter(Boolean).map((path) => join(path, "applications")))];
}

function desktopFiles(directory: string, depth = 0): string[] {
  if (depth > 4) return [];
  let entries;
  try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return []; }
  return entries.slice(0, MAX_DIRECTORY_ENTRIES).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return desktopFiles(path, depth + 1);
    return (entry.isFile() || entry.isSymbolicLink()) && entry.name.endsWith(".desktop") ? [path] : [];
  });
}

function parseDesktopApp(path: string, id: string): InstalledApp | undefined {
  try {
    if (id.length > 256 || id.trim() !== id || /[/\\]/u.test(id) || UNSAFE_DISPLAY_TEXT.test(id)) return undefined;
    if (statSync(path).size > MAX_DESKTOP_FILE_BYTES) return undefined;
    const values = new Map<string, string>();
    let inDesktopEntry = false;
    for (const line of readFileSync(path, "utf8").split(/\r?\n/u)) {
      if (line.startsWith("[")) {
        inDesktopEntry = line === "[Desktop Entry]";
        continue;
      }
      if (!inDesktopEntry || line.startsWith("#")) continue;
      const separator = line.indexOf("=");
      if (separator > 0) values.set(line.slice(0, separator), line.slice(separator + 1).trim());
    }
    if (values.get("Type") !== "Application" || values.get("Hidden") === "true" || values.get("NoDisplay") === "true") return undefined;
    const name = values.get("Name")?.trim();
    if (!name || UNSAFE_DISPLAY_TEXT.test(name)) return undefined;
    const genericName = values.get("GenericName")?.trim();
    const rawDescription = genericName === undefined || genericName === "" ? values.get("Comment")?.trim() : genericName;
    const description = rawDescription !== undefined && !UNSAFE_DISPLAY_TEXT.test(rawDescription) ? rawDescription : undefined;
    const rawStartupWmClass = values.get("StartupWMClass")?.trim();
    const startupWmClass = rawStartupWmClass !== undefined && !UNSAFE_DISPLAY_TEXT.test(rawStartupWmClass) ? rawStartupWmClass : undefined;
    const terminal = values.get("Terminal")?.trim().toLocaleLowerCase() === "true";
    return {
      kind: "desktop",
      id,
      name,
      ...(description ? { description: description.slice(0, 240) } : {}),
      ...(startupWmClass ? { startupWmClass: startupWmClass.slice(0, 240) } : {}),
      ...(terminal ? { terminal: true } : {})
    };
  } catch { return undefined; }
}

function installedDesktopApps(env: NodeJS.ProcessEnv): InstalledApp[] {
  const seen = new Set<string>();
  const apps: InstalledApp[] = [];
  for (const root of desktopAppDirectories(env)) {
    if (!existsSync(root)) continue;
    for (const path of desktopFiles(root).slice(0, MAX_CATALOG_ENTRIES)) {
      const id = relative(root, path).split(sep).join("-").replace(/\.desktop$/u, "");
      if (seen.has(id)) continue;
      seen.add(id);
      const app = parseDesktopApp(path, id);
      if (app !== undefined) apps.push(app);
    }
  }
  return apps;
}

function installedCliApps(env: NodeJS.ProcessEnv): InstalledApp[] {
  const seen = new Set<string>();
  const apps: InstalledApp[] = [];
  for (const directory of (env.PATH ?? "").split(delimiter).filter(Boolean)) {
    let entries;
    try { entries = readdirSync(directory, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries.slice(0, MAX_DIRECTORY_ENTRIES)) {
      if (apps.length >= MAX_CATALOG_ENTRIES) return apps;
      if (seen.has(entry.name) || !SAFE_CLI_APP_ID.test(entry.name) || (!entry.isFile() && !entry.isSymbolicLink())) continue;
      seen.add(entry.name);
      try { accessSync(join(directory, entry.name), constants.X_OK); } catch { continue; }
      apps.push({ kind: "cli", id: entry.name, name: entry.name });
    }
  }
  return apps;
}

export function discoverInstalledApps(
  query = "",
  kind: "all" | "desktop" | "cli" = "all",
  limit = 20,
  env: NodeJS.ProcessEnv = process.env
): InstalledApp[] {
  const needle = query.trim().toLocaleLowerCase();
  const candidates = [
    ...(kind === "cli" ? [] : installedDesktopApps(env)),
    ...(kind === "desktop" ? [] : installedCliApps(env))
  ];
  return candidates.filter((app) => needle === "" || `${app.name}\n${app.id}\n${app.description ?? ""}`.toLocaleLowerCase().includes(needle))
    .sort((left, right) => {
      const leftExact = left.id.toLocaleLowerCase() === needle || left.name.toLocaleLowerCase() === needle ? 0 : 1;
      const rightExact = right.id.toLocaleLowerCase() === needle || right.name.toLocaleLowerCase() === needle ? 0 : 1;
      return leftExact - rightExact || left.name.localeCompare(right.name) || left.id.localeCompare(right.id);
    }).slice(0, Math.max(1, Math.min(limit, 40)));
}

function boundedCommandText(value: unknown, maximum: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  return text === "" || UNSAFE_DISPLAY_TEXT.test(text) ? undefined : text.slice(0, maximum);
}

function parseOmarchyCommands(stdout: string): Array<OmarchyCommand & { group: string; search: string }> {
  let parsed: unknown;
  try { parsed = JSON.parse(stdout); }
  catch { throw new DesktopToolError("omarchy_commands_unavailable", "Omarchy returned an invalid command catalog"); }
  if (!isObject(parsed) || !Array.isArray(parsed.commands)) {
    throw new DesktopToolError("omarchy_commands_unavailable", "Omarchy returned an invalid command catalog");
  }
  const commands: Array<OmarchyCommand & { group: string; search: string }> = [];
  for (const raw of parsed.commands.slice(0, 2_000)) {
    if (!isObject(raw) || raw.hidden === true) continue;
    const route = boundedCommandText(raw.route, 256);
    const summary = boundedCommandText(raw.summary, 500);
    if (route === undefined || summary === undefined || !route.startsWith("omarchy ")) continue;
    const group = boundedCommandText(raw.group, 64)?.toLocaleLowerCase() ?? "";
    const args = boundedCommandText(raw.args, 256);
    const aliases = Array.isArray(raw.aliases)
      ? raw.aliases.map((alias) => boundedCommandText(alias, 256)).filter((alias): alias is string => alias !== undefined).slice(0, 12)
      : [];
    commands.push({
      route,
      summary,
      ...(args === undefined ? {} : { args }),
      ...(aliases.length === 0 ? {} : { aliases }),
      requiresSudo: raw.requires_sudo === true,
      group,
      search: `${route}\n${summary}\n${args ?? ""}\n${aliases.join("\n")}`.toLocaleLowerCase()
    });
  }
  return commands;
}

export async function discoverOmarchyCommands(
  query = "",
  group = "",
  limit = 20,
  run: DesktopCommandRunner = runDesktopCommand,
  signal?: AbortSignal
): Promise<OmarchyCommand[]> {
  const result = await run("omarchy", ["commands", "--json"], signal);
  const needle = query.trim().toLocaleLowerCase();
  const requestedGroup = group.trim().toLocaleLowerCase();
  return parseOmarchyCommands(result.stdout)
    .filter((command) => (requestedGroup === "" || command.group === requestedGroup) && (needle === "" || command.search.includes(needle)))
    .sort((left, right) => {
      const leftExact = left.route.toLocaleLowerCase() === needle ? 0 : 1;
      const rightExact = right.route.toLocaleLowerCase() === needle ? 0 : 1;
      return leftExact - rightExact || left.route.localeCompare(right.route);
    })
    .slice(0, Math.max(1, Math.min(limit, 40)))
    .map((command) => ({
      route: command.route,
      summary: command.summary,
      ...(command.args === undefined ? {} : { args: command.args }),
      ...(command.aliases === undefined ? {} : { aliases: command.aliases }),
      requiresSudo: command.requiresSudo
    }));
}

function resolveInstalledApp(kind: "desktop" | "cli", id: string, env: NodeJS.ProcessEnv): InstalledApp {
  const validId = kind === "desktop"
    ? id.length <= 256 && id.trim() === id && !/[/\\]/u.test(id) && !UNSAFE_DISPLAY_TEXT.test(id)
    : SAFE_CLI_APP_ID.test(id);
  if (!validId) {
    throw new DesktopToolError("invalid_app", "Use an exact app ID returned by app_catalog");
  }
  const candidates = kind === "desktop" ? installedDesktopApps(env) : installedCliApps(env);
  const app = candidates.find((candidate) => candidate.id === id);
  if (app === undefined) throw new DesktopToolError("app_unavailable", "That exact installed app is no longer available");
  return app;
}

export function normalizeWindowAddress(value: string | undefined): string | undefined {
  if (value === undefined || value === "") return undefined;
  if (!/^0x[0-9a-f]+$/iu.test(value)) {
    throw new DesktopToolError("invalid_window", "Use an exact window address returned by desktop_state");
  }
  return value.toLocaleLowerCase();
}

function requireWindowAddress(value: string | undefined): string {
  const address = normalizeWindowAddress(value);
  if (address === undefined) throw new DesktopToolError("invalid_window", "Choose a window returned by desktop_state");
  return address;
}

function requireWorkspace(value: number | undefined): number {
  if (value === undefined || !Number.isInteger(value) || value < 1 || value > 99) {
    throw new DesktopToolError("invalid_workspace", "Choose a numbered workspace from 1 through 99");
  }
  return value;
}

function requireWindowPid(value: number | undefined): number {
  if (value === undefined || !Number.isInteger(value) || value < 1) {
    throw new DesktopToolError("invalid_window", "Use the exact window PID returned by desktop_state");
  }
  return value;
}

export function windowActionCommand(input: WindowActionInput): Command {
  const address = requireWindowAddress(input.address);
  requireWindowPid(input.pid);
  switch (input.action) {
    case "focus": return {
      file: "hyprctl", args: ["dispatch", `hl.dsp.focus({ window = "address:${address}" })`]
    };
    case "move_to_workspace": {
      const workspace = requireWorkspace(input.workspace);
      return {
        file: "hyprctl",
        args: ["dispatch", `hl.dsp.window.move({ window = "address:${address}", workspace = ${workspace}, follow = ${input.follow === false ? "false" : "true"} })`]
      };
    }
    case "resize": {
      if (input.width === undefined || input.height === undefined) {
        throw new DesktopToolError("invalid_size", "Choose both the requested width and height");
      }
      if (!Number.isInteger(input.width) || !Number.isInteger(input.height)
        || input.width < 100 || input.height < 100 || input.width > 10_000 || input.height > 10_000) {
        throw new DesktopToolError("invalid_size", "Choose a width and height from 100 through 10000 pixels");
      }
      return {
        file: "hyprctl",
        args: ["dispatch", `hl.dsp.window.resize({ window = "address:${address}", x = ${input.width}, y = ${input.height} })`]
      };
    }
    case "set_floating":
      if (input.enabled === undefined) throw new DesktopToolError("invalid_state", "Choose whether floating should be enabled");
      return {
        file: "hyprctl", args: ["dispatch", `hl.dsp.window.float({ window = "address:${address}", action = "toggle" })`]
      };
    case "close": return {
      file: "hyprctl", args: ["dispatch", `hl.dsp.window.close({ window = "address:${address}" })`]
    };
    default: throw new DesktopToolError("invalid_window_action", "That window action is unavailable");
  }
}

export function workspaceActionCommand(input: WorkspaceActionInput): Command {
  const workspace = requireWorkspace(input.workspace);
  switch (input.action) {
    case "focus": return {
      file: "hyprctl", args: ["dispatch", `hl.dsp.focus({ workspace = ${workspace} })`]
    };
    case "move_to_monitor": {
      const monitor = input.monitor?.trim();
      if (monitor === undefined || monitor === "" || !/^[A-Za-z0-9_.:-]{1,128}$/u.test(monitor)) {
        throw new DesktopToolError("invalid_monitor", "Use an exact monitor name returned by desktop_state");
      }
      return {
        file: "hyprctl", args: ["dispatch", `hl.dsp.workspace.move({ workspace = ${workspace}, monitor = "${monitor}" })`]
      };
    }
    default: throw new DesktopToolError("invalid_workspace_action", "That workspace action is unavailable");
  }
}

function windowSummary(window: DesktopWindow | undefined, activeAddress?: string): Record<string, unknown> | undefined {
  if (window === undefined) return undefined;
  return {
    address: window.address,
    ...(window.pid === undefined ? {} : { pid: window.pid }),
    ...(window.workspace === undefined ? {} : { workspace: window.workspace }),
    ...(window.monitor === undefined ? {} : { monitor: window.monitor }),
    ...(window.position === undefined ? {} : { position: window.position }),
    ...(window.size === undefined ? {} : { size: window.size }),
    floating: window.floating,
    active: window.address === activeAddress
  };
}

function workspaceSummary(workspace: DesktopWorkspace | undefined, activeWorkspace?: number): Record<string, unknown> | undefined {
  if (workspace === undefined) return undefined;
  return {
    ...(workspace.id === undefined ? {} : { id: workspace.id }),
    ...(workspace.monitor === undefined ? {} : { monitor: workspace.monitor }),
    active: workspace.id === activeWorkspace
  };
}

function receiptResult(receipt: ActionReceipt): {
  content: Array<{ type: "text"; text: string }>;
  details: ActionReceipt;
  isError?: true;
} {
  return {
    content: [{ type: "text", text: JSON.stringify(receipt, undefined, 2) }],
    details: receipt,
    ...(receipt.verified ? {} : { isError: true as const })
  };
}

function observeReceipt(receipt: ActionReceipt, startedAt: number, observer: ActionReceiptObserver | undefined): void {
  if (!receipt.changed || !receipt.verified || receipt.command === undefined) return;
  observer?.({ command: receipt.command, exitCode: 0, durationMs: Math.max(0, Date.now() - startedAt) });
}

function toolFailure(action: string, error: unknown): {
  content: Array<{ type: "text"; text: string }>;
  details: { code?: string };
  isError: true;
} {
  const message = error instanceof DesktopToolError ? error.message : `${action} failed`;
  return {
    content: [{ type: "text", text: message }],
    details: error instanceof DesktopToolError ? { code: error.code } : {},
    isError: true
  };
}

async function dispatch(run: DesktopCommandRunner, command: Command, signal?: AbortSignal): Promise<void> {
  const result = await run(command.file, command.args, signal);
  if (`${result.stdout}\n${result.stderr}`.trim() !== "ok") {
    throw new DesktopToolError("desktop_action_rejected", "Hyprland did not accept the requested action");
  }
}

function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted === true) {
      reject(signal.reason instanceof Error ? signal.reason : new Error("aborted"));
      return;
    }
    const onAbort = (): void => {
      clearTimeout(timeout);
      reject(signal?.reason instanceof Error ? signal.reason : new Error("aborted"));
    };
    const timeout = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    timeout.unref();
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

async function waitForState(
  run: DesktopCommandRunner,
  predicate: (state: DesktopState) => boolean,
  signal?: AbortSignal,
  attempts = VERIFY_ATTEMPTS,
  delayMs = VERIFY_DELAY_MS
): Promise<DesktopState> {
  let state = await readDesktopState(run, false, signal);
  for (let attempt = 0; attempt < attempts && !predicate(state); attempt += 1) {
    await delay(delayMs, signal);
    state = await readDesktopState(run, false, signal);
  }
  return state;
}

function normalizedIdentity(value: string | undefined): string {
  return (value ?? "").toLocaleLowerCase().replace(/\.desktop$/u, "");
}

function compactIdentity(value: string | undefined): string {
  return normalizedIdentity(value).replace(/[^\p{L}\p{N}]+/gu, "");
}

function terminalTitleMatches(app: InstalledApp, title: string | undefined): boolean {
  if (app.terminal !== true || title === undefined) return false;
  const identities = new Set([
    compactIdentity(app.id),
    compactIdentity(app.id.split(".").at(-1)),
    compactIdentity(app.name)
  ].filter((value) => value.length >= 2));
  if (identities.size === 0) return false;
  const segments = [title, ...title.split(/[|:—–-]/u)].map(compactIdentity).filter(Boolean);
  return segments.some((segment) => identities.has(segment));
}

type KnownAppWindows = Map<string, Map<string, number | undefined>>;

function appKey(app: InstalledApp): string {
  return `${app.kind}:${app.id}`;
}

function rememberAppWindows(known: KnownAppWindows, app: InstalledApp, windows: DesktopWindow[]): void {
  const remembered = known.get(appKey(app)) ?? new Map<string, number | undefined>();
  for (const window of windows) remembered.set(window.address, window.pid);
  known.set(appKey(app), remembered);
}

function appWindows(app: InstalledApp, state: DesktopState, known?: KnownAppWindows): DesktopWindow[] {
  const identities = new Set([
    normalizedIdentity(app.id),
    normalizedIdentity(app.id.split(".").at(-1)),
    normalizedIdentity(app.startupWmClass),
    ...(app.kind === "cli" ? [normalizedIdentity(`org.omarchy.${app.id}`)] : [])
  ].filter(Boolean));
  const remembered = known?.get(appKey(app));
  const matches = state.windows.filter((window) => {
    const classes = [normalizedIdentity(window.class), normalizedIdentity(window.initialClass)];
    const knownPid = remembered?.get(window.address);
    const knownMatch = remembered?.has(window.address) === true
      && (knownPid === undefined || knownPid === window.pid);
    return knownMatch || classes.some((candidate) => identities.has(candidate)) || terminalTitleMatches(app, window.title);
  });
  if (remembered !== undefined) {
    const liveAddresses = new Set(state.windows.map((window) => window.address));
    for (const address of remembered.keys()) if (!liveAddresses.has(address)) remembered.delete(address);
  }
  return matches;
}

async function waitForWindows(
  run: DesktopCommandRunner,
  predicate: (windows: DesktopWindow[]) => boolean,
  signal?: AbortSignal
): Promise<DesktopWindow[]> {
  let windows = await readDesktopWindows(run, true, signal);
  for (let attempt = 0; attempt < APP_VERIFY_ATTEMPTS && !predicate(windows); attempt += 1) {
    await delay(APP_VERIFY_DELAY_MS, signal);
    windows = await readDesktopWindows(run, true, signal);
  }
  return windows;
}

function newVisibleWindows(windows: DesktopWindow[], previousAddresses: Set<string>): DesktopWindow[] {
  return windows.filter((window) => !previousAddresses.has(window.address) && window.mapped && !window.hidden);
}

function attributedLaunchWindows(
  app: InstalledApp,
  windows: DesktopWindow[],
  previousAddresses: Set<string>,
  known: KnownAppWindows
): { windows: DesktopWindow[]; matchedBy?: "identity" | "single_new_window" } {
  const state: DesktopState = { monitors: [], workspaces: [], windows };
  const identityMatches = appWindows(app, state, known).filter((window) => !previousAddresses.has(window.address));
  if (identityMatches.length > 0) return { windows: identityMatches, matchedBy: "identity" };
  const newWindows = newVisibleWindows(windows, previousAddresses);
  return newWindows.length === 1 ? { windows: newWindows, matchedBy: "single_new_window" } : { windows: [] };
}

async function focusAppWindow(
  run: DesktopCommandRunner,
  app: InstalledApp,
  matches: DesktopWindow[],
  known: KnownAppWindows,
  signal?: AbortSignal
): Promise<ActionReceipt> {
  if (matches.length !== 1) {
    throw new DesktopToolError(
      matches.length === 0 ? "app_window_unavailable" : "app_window_ambiguous",
      matches.length === 0 ? "No matching app window is open" : "More than one matching app window is open; target an exact address"
    );
  }
  const target = matches[0];
  if (target === undefined) throw new DesktopToolError("app_window_unavailable", "No matching app window is open");
  const before = await readDesktopState(run, true, signal);
  const currentTarget = appWindows(app, before, known).find((window) => window.address === target.address);
  if (currentTarget === undefined) throw new DesktopToolError("app_window_unavailable", "That exact app window is no longer available");
  rememberAppWindows(known, app, [currentTarget]);
  if (before.activeWindow?.address === currentTarget.address) {
    return {
      action: "focus_existing_app", target: { app: app.id, address: currentTarget.address }, requested: {},
      before: windowSummary(currentTarget, before.activeWindow.address), after: windowSummary(currentTarget, before.activeWindow.address),
      changed: false, verified: true
    };
  }
  const command: Command = {
    file: "hyprctl", args: ["dispatch", `hl.dsp.focus({ window = "address:${currentTarget.address}" })`]
  };
  await dispatch(run, command, signal);
  const after = await waitForState(run, (state) => state.activeWindow?.address === currentTarget.address, signal);
  return {
    action: "focus_existing_app", command: displayCommand(command.file, command.args), target: { app: app.id, address: currentTarget.address }, requested: {},
    before: windowSummary(currentTarget, before.activeWindow?.address),
    after: windowSummary(after.windows.find((window) => window.address === currentTarget.address), after.activeWindow?.address),
    changed: before.activeWindow?.address !== after.activeWindow?.address,
    verified: after.activeWindow?.address === currentTarget.address
  };
}

async function openApp(
  run: DesktopCommandRunner,
  launch: DesktopCommandRunner,
  env: NodeJS.ProcessEnv,
  input: AppOpenInput,
  known: KnownAppWindows,
  signal?: AbortSignal
): Promise<ActionReceipt> {
  const app = resolveInstalledApp(input.kind, input.id, env);
  const mode = input.mode ?? "focus_or_launch";
  if (!["focus_or_launch", "focus_existing", "new_window"].includes(mode)) {
    throw new DesktopToolError("invalid_app_mode", "That app-open mode is unavailable");
  }
  const before = await readDesktopState(run, true, signal);
  const matches = appWindows(app, before, known);
  if (mode !== "new_window" && matches.length > 0) return focusAppWindow(run, app, matches, known, signal);
  if (mode === "focus_existing") return focusAppWindow(run, app, matches, known, signal);
  const previousAddresses = new Set(before.windows.map((window) => window.address));
  const command = app.kind === "desktop"
    ? { file: "uwsm-app", args: ["--", "gtk-launch", `${app.id}.desktop`] }
    : { file: "omarchy", args: ["launch", "tui", `--app-id=org.omarchy.${app.id}`, app.id] };
  await launch(command.file, command.args, signal);
  const afterWindows = await waitForWindows(run, (windows) => {
    return attributedLaunchWindows(app, windows, previousAddresses, known).windows.length > 0;
  }, signal);
  const attributed = attributedLaunchWindows(app, afterWindows, previousAddresses, known);
  const observed = newVisibleWindows(afterWindows, previousAddresses);
  if (attributed.windows.length > 0) rememberAppWindows(known, app, attributed.windows);
  return {
    action: "open_app", command: displayCommand(command.file, command.args), target: { kind: app.kind, id: app.id }, requested: { mode },
    before: { matchingWindows: matches.map((window) => window.address) },
    after: {
      newWindows: attributed.windows.map((window) => window.address),
      ...(attributed.matchedBy === undefined ? {} : { matchedBy: attributed.matchedBy }),
      ...(attributed.windows.length > 0 || observed.length === 0 ? {} : { ambiguousWindows: observed.map((window) => window.address) })
    },
    changed: observed.length > 0,
    verified: attributed.windows.length > 0
  };
}

async function executeWindowAction(
  run: DesktopCommandRunner,
  input: WindowActionInput,
  signal?: AbortSignal
): Promise<ActionReceipt> {
  const address = requireWindowAddress(input.address);
  const beforeState = await readDesktopState(run, false, signal);
  const beforeWindow = beforeState.windows.find((window) => window.address === address);
  if (beforeWindow === undefined) throw new DesktopToolError("window_unavailable", "That exact window is no longer available");
  if (beforeWindow.pid !== input.pid) {
    throw new DesktopToolError("window_identity_changed", "That window address no longer belongs to the inspected process");
  }
  if (input.action === "resize" && !beforeWindow.floating) {
    throw new DesktopToolError(
      "tiled_window_resize_unsupported",
      "Exact pixel resizing is unavailable while the window is tiled; do not retry, close, or relaunch it"
    );
  }
  const command = windowActionCommand(input);
  const requested: Record<string, unknown> = {
    ...(input.workspace === undefined ? {} : { workspace: input.workspace }),
    ...(input.follow === undefined ? {} : { follow: input.follow }),
    ...(input.width === undefined ? {} : { width: input.width }),
    ...(input.height === undefined ? {} : { height: input.height }),
    ...(input.enabled === undefined ? {} : { enabled: input.enabled })
  };
  const alreadySatisfied = (input.action === "focus" && beforeState.activeWindow?.address === address)
    || (input.action === "resize" && beforeWindow.size?.[0] === input.width && beforeWindow.size?.[1] === input.height)
    || (input.action === "set_floating" && beforeWindow.floating === input.enabled)
    || (input.action === "move_to_workspace" && input.follow === false && beforeWindow.workspace === input.workspace);
  if (alreadySatisfied) {
    const summary = windowSummary(beforeWindow, beforeState.activeWindow?.address);
    return {
      action: input.action, command: displayCommand(command.file, command.args), target: { address, pid: input.pid }, requested,
      before: summary, after: summary, changed: false, verified: true
    };
  }
  await dispatch(run, command, signal);
  const predicate = (state: DesktopState): boolean => {
    const window = state.windows.find((candidate) => candidate.address === address);
    switch (input.action) {
      case "focus": return state.activeWindow?.address === address;
      case "move_to_workspace": return window?.workspace === input.workspace;
      case "resize": return window?.size?.[0] === input.width && window?.size?.[1] === input.height;
      case "set_floating": return window?.floating === input.enabled;
      case "close": return window === undefined;
    }
  };
  const afterState = await waitForState(run, predicate, signal);
  const afterWindow = afterState.windows.find((window) => window.address === address);
  const verified = predicate(afterState);
  const changed = (() => {
    switch (input.action) {
      case "focus": return beforeState.activeWindow?.address !== afterState.activeWindow?.address;
      case "move_to_workspace": return beforeWindow.workspace !== afterWindow?.workspace;
      case "resize": return beforeWindow.size?.[0] !== afterWindow?.size?.[0] || beforeWindow.size?.[1] !== afterWindow?.size?.[1];
      case "set_floating": return beforeWindow.floating !== afterWindow?.floating;
      case "close": return afterWindow === undefined;
    }
  })();
  return {
    action: input.action,
    command: displayCommand(command.file, command.args),
    target: { address, pid: input.pid },
    requested,
    before: windowSummary(beforeWindow, beforeState.activeWindow?.address),
    after: windowSummary(afterWindow, afterState.activeWindow?.address),
    changed,
    verified
  };
}

async function executeWorkspaceAction(
  run: DesktopCommandRunner,
  input: WorkspaceActionInput,
  signal?: AbortSignal
): Promise<ActionReceipt> {
  const workspace = requireWorkspace(input.workspace);
  const beforeState = await readDesktopState(run, false, signal);
  const beforeWorkspace = beforeState.workspaces.find((candidate) => candidate.id === workspace);
  if (input.action === "focus" && beforeState.activeWorkspace?.id === workspace) {
    const summary = workspaceSummary(beforeWorkspace, beforeState.activeWorkspace.id);
    const command = workspaceActionCommand(input);
    return {
      action: input.action, command: displayCommand(command.file, command.args), target: { workspace }, requested: {},
      before: summary, after: summary, changed: false, verified: true
    };
  }
  if (input.action === "move_to_monitor") {
    const monitor = input.monitor?.trim();
    if (!beforeState.monitors.some((candidate) => candidate.name === monitor)) {
      throw new DesktopToolError("monitor_unavailable", "That exact monitor is no longer available");
    }
    if (beforeWorkspace === undefined) throw new DesktopToolError("workspace_unavailable", "That exact workspace is no longer available");
    if (beforeWorkspace.monitor === monitor) {
      const summary = workspaceSummary(beforeWorkspace, beforeState.activeWorkspace?.id);
      const command = workspaceActionCommand(input);
      return {
        action: input.action, command: displayCommand(command.file, command.args), target: { workspace }, requested: { monitor },
        before: summary, after: summary, changed: false, verified: true
      };
    }
  }
  const command = workspaceActionCommand(input);
  await dispatch(run, command, signal);
  const predicate = (state: DesktopState): boolean => input.action === "focus"
    ? state.activeWorkspace?.id === workspace
    : state.workspaces.find((candidate) => candidate.id === workspace)?.monitor === input.monitor;
  const afterState = await waitForState(run, predicate, signal);
  const afterWorkspace = afterState.workspaces.find((candidate) => candidate.id === workspace);
  const verified = predicate(afterState);
  const changed = input.action === "focus"
    ? beforeState.activeWorkspace?.id !== afterState.activeWorkspace?.id
    : beforeWorkspace?.monitor !== afterWorkspace?.monitor;
  return {
    action: input.action,
    command: displayCommand(command.file, command.args),
    target: { workspace },
    requested: input.monitor === undefined ? {} : { monitor: input.monitor },
    before: workspaceSummary(beforeWorkspace, beforeState.activeWorkspace?.id),
    after: workspaceSummary(afterWorkspace, afterState.activeWorkspace?.id),
    changed,
    verified
  };
}

export function displayCommand(file: string, args: string[]): string {
  return [file, ...args].map((part) => /^[A-Za-z0-9_./:+-]+$/u.test(part) ? part : JSON.stringify(part)).join(" ");
}

export function reviewDesktopToolInput(name: string, input: Record<string, unknown>): Record<string, unknown> | undefined {
  if (name === "app_open") {
    const kind = input.kind === "desktop" ? "desktop" : "cli";
    const id = typeof input.id === "string" ? input.id : "";
    const mode = typeof input.mode === "string" ? input.mode : "focus_or_launch";
    return {
      command: displayCommand("app_open", ["--kind", kind, "--id", id, "--mode", mode]),
      operation: "app_open", kind, id, mode
    };
  }
  if (name === "window_action") {
    try {
      const normalized = {
        action: typeof input.action === "string" ? input.action : "",
        address: typeof input.address === "string" ? input.address : "",
        pid: typeof input.pid === "number" ? input.pid : 0,
        ...(typeof input.workspace === "number" ? { workspace: input.workspace } : {}),
        ...(typeof input.follow === "boolean" ? { follow: input.follow } : {}),
        ...(typeof input.width === "number" ? { width: input.width } : {}),
        ...(typeof input.height === "number" ? { height: input.height } : {}),
        ...(typeof input.enabled === "boolean" ? { enabled: input.enabled } : {})
      } as WindowActionInput;
      const command = windowActionCommand(normalized);
      return { operation: "window_action", command: displayCommand(command.file, command.args), argv: [command.file, ...command.args], ...normalized };
    } catch { return { operation: "invalid_window_action", ...input }; }
  }
  if (name === "workspace_action") {
    try {
      const normalized = {
        action: typeof input.action === "string" ? input.action : "",
        workspace: typeof input.workspace === "number" ? input.workspace : 0,
        ...(typeof input.monitor === "string" ? { monitor: input.monitor } : {})
      } as WorkspaceActionInput;
      const command = workspaceActionCommand(normalized);
      return { operation: "workspace_action", command: displayCommand(command.file, command.args), argv: [command.file, ...command.args], ...normalized };
    } catch { return { operation: "invalid_workspace_action", ...input }; }
  }
  return undefined;
}

export function desktopToolTitle(name: string, input: Record<string, unknown>): string | undefined {
  if (name === "app_open") return `Open app: ${typeof input.id === "string" ? input.id : "app"}`;
  if (name === "window_action") return `Window: ${typeof input.action === "string" ? input.action : "action"}`;
  if (name === "workspace_action") return `Workspace: ${typeof input.action === "string" ? input.action : "action"}`;
  return undefined;
}

export function createPersonalAssistantTools(
  run: DesktopCommandRunner = runDesktopCommand,
  env: NodeJS.ProcessEnv = process.env,
  launch: DesktopCommandRunner = run === runDesktopCommand ? launchDesktopCommand : run,
  observeAction?: ActionReceiptObserver
): [
  ToolDefinition<typeof appCatalogParameters>,
  ToolDefinition<typeof appOpenParameters>,
  ToolDefinition<typeof desktopStateParameters>,
  ToolDefinition<typeof windowActionParameters>,
  ToolDefinition<typeof workspaceActionParameters>,
  ToolDefinition<typeof omarchyCommandsParameters>
] {
  const knownAppWindows: KnownAppWindows = new Map();
  let appOpenQueue: Promise<void> = Promise.resolve();
  const appCatalog: ToolDefinition<typeof appCatalogParameters> = {
    name: "app_catalog",
    label: "Find installed apps",
    description: "Find installed graphical desktop apps and executable CLI commands before opening or claiming an app is unavailable.",
    promptSnippet: "Search the read-only installed app catalog",
    parameters: appCatalogParameters,
    execute(_toolCallId, input) {
      try {
        const apps = discoverInstalledApps(input.query ?? "", input.kind ?? "all", input.limit ?? 20, env);
        return Promise.resolve({
          content: [{ type: "text" as const, text: apps.length === 0 ? "No matching installed apps were found." : JSON.stringify(apps, undefined, 2) }],
          details: { apps }
        });
      } catch (error) { return Promise.resolve(toolFailure("Searching installed apps", error)); }
    }
  };
  const appOpen: ToolDefinition<typeof appOpenParameters> = {
    name: "app_open",
    label: "Open installed app",
    description: "Focus one unambiguous matching window or launch an exact app returned by app_catalog. The tool serializes launches and verifies the resulting window internally.",
    promptSnippet: "Focus or launch a discovered app with internal verification",
    parameters: appOpenParameters,
    async execute(_toolCallId, input, signal) {
      const operation = appOpenQueue.then(
        () => openApp(run, launch, env, input, knownAppWindows, signal),
        () => openApp(run, launch, env, input, knownAppWindows, signal)
      );
      appOpenQueue = operation.then(() => undefined, () => undefined);
      const startedAt = Date.now();
      try {
        const receipt = await operation;
        observeReceipt(receipt, startedAt, observeAction);
        return receiptResult(receipt);
      }
      catch (error) { return toolFailure("Opening the app", error); }
    }
  };
  const desktopState: ToolDefinition<typeof desktopStateParameters> = {
    name: "desktop_state",
    label: "Inspect desktop",
    description: "Read bounded Hyprland monitor, workspace, and exact window state. Titles are omitted unless explicitly requested.",
    promptSnippet: "Inspect current monitors, workspaces, and windows",
    parameters: desktopStateParameters,
    async execute(_toolCallId, input, signal) {
      try {
        const state = await readDesktopState(run, input.includeTitles ?? false, signal);
        return { content: [{ type: "text", text: JSON.stringify(state, undefined, 2) }], details: state };
      } catch (error) { return toolFailure("Reading desktop state", error); }
    }
  };
  const windowAction: ToolDefinition<typeof windowActionParameters> = {
    name: "window_action",
    label: "Control exact window",
    description: "Focus, move, resize, float, or close one exact window address. Re-reads the target and verifies post-state internally.",
    promptSnippet: "Perform and verify one exact window action",
    parameters: windowActionParameters,
    async execute(_toolCallId, input, signal) {
      const startedAt = Date.now();
      try {
        const receipt = await executeWindowAction(run, input, signal);
        observeReceipt(receipt, startedAt, observeAction);
        return receiptResult(receipt);
      }
      catch (error) { return toolFailure("The window action", error); }
    }
  };
  const workspaceAction: ToolDefinition<typeof workspaceActionParameters> = {
    name: "workspace_action",
    label: "Control workspace",
    description: "Focus a numbered workspace or move it to an exact monitor, then verify the result internally.",
    promptSnippet: "Perform and verify one exact workspace action",
    parameters: workspaceActionParameters,
    async execute(_toolCallId, input, signal) {
      const startedAt = Date.now();
      try {
        const receipt = await executeWorkspaceAction(run, input, signal);
        observeReceipt(receipt, startedAt, observeAction);
        return receiptResult(receipt);
      }
      catch (error) { return toolFailure("The workspace action", error); }
    }
  };
  const omarchyCommands: ToolDefinition<typeof omarchyCommandsParameters> = {
    name: "omarchy_commands",
    label: "Find Omarchy commands",
    description: "Search or browse the live read-only `omarchy commands --json` catalog before guessing a route or claiming an Omarchy action is unavailable. This discovers commands but does not execute them.",
    promptSnippet: "Search documented commands supported by the installed Omarchy CLI",
    parameters: omarchyCommandsParameters,
    async execute(_toolCallId, input, signal) {
      try {
        const commands = await discoverOmarchyCommands(input.query ?? "", input.group ?? "", input.limit ?? 20, run, signal);
        return {
          content: [{ type: "text" as const, text: commands.length === 0 ? "No matching Omarchy commands were found." : JSON.stringify(commands, undefined, 2) }],
          details: { commands }
        };
      } catch (error) { return toolFailure("Reading the Omarchy command catalog", error); }
    }
  };
  return [appCatalog, appOpen, desktopState, windowAction, workspaceAction, omarchyCommands];
}

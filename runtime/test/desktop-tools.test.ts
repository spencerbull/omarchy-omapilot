import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  createPersonalAssistantTools,
  discoverInstalledApps,
  discoverOmarchyCommands,
  launchDesktopCommand,
  readDesktopState,
  reviewDesktopToolInput,
  windowActionCommand,
  workspaceActionCommand,
  type DesktopCommandRunner
} from "../src/tools/desktop.js";
import { normalizeToolPermission } from "../src/permissions.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

type MutableDesktop = {
  activeAddress: string | undefined;
  window: {
    address: string;
    class: string;
    initialClass: string;
    title?: string;
    workspace: number;
    monitor: number;
    size: [number, number];
    floating: boolean;
  } | undefined;
  workspaceMonitor: string;
  launched?: boolean;
};

function desktopRunner(state: MutableDesktop, calls: Array<{ file: string; args: string[] }>): DesktopCommandRunner {
  return (file, args) => {
    calls.push({ file, args });
    if (file === "uwsm-app") {
      const desktopId = args.at(-1);
      const terminal = desktopId === "org.example.Console.desktop";
      const wrapped = desktopId === "org.example.Wrapped.desktop";
      state.launched = true;
      state.window = {
        address: "0xbbb", class: terminal || wrapped ? "kitty" : "ExampleEditor",
        initialClass: terminal || wrapped ? "kitty" : "ExampleEditor",
        title: terminal ? "Example Console" : wrapped ? "Unrelated shell" : "Private document title",
        workspace: 1, monitor: 0, size: [900, 700], floating: false
      };
      state.activeAddress = "0xbbb";
      return Promise.resolve({ stdout: "", stderr: "" });
    }
    if (file === "omarchy") {
      const appId = args.find((argument) => argument.startsWith("--app-id="))?.slice("--app-id=".length);
      state.launched = true;
      state.window = {
        address: "0xccc", class: appId ?? "kitty", initialClass: appId ?? "kitty",
        workspace: 1, monitor: 0, size: [900, 700], floating: false
      };
      state.activeAddress = "0xccc";
      return Promise.resolve({ stdout: "", stderr: "" });
    }
    if (file !== "hyprctl") return Promise.reject(new Error(`unexpected command: ${file}`));
    if (args[0] === "dispatch") {
      const dispatcher = args[1] ?? "";
      const address = /address:(0x[0-9a-f]+)/u.exec(dispatcher)?.[1];
      if (dispatcher.startsWith("hl.dsp.focus({ window")) state.activeAddress = address;
      if (dispatcher.startsWith("hl.dsp.window.move")) {
        const workspace = /workspace = (\d+)/u.exec(dispatcher)?.[1];
        if (state.window !== undefined && workspace !== undefined) state.window.workspace = Number(workspace);
      }
      if (dispatcher.startsWith("hl.dsp.window.resize")) {
        const match = /x = (\d+), y = (\d+)/u.exec(dispatcher);
        if (match !== null && state.window !== undefined) {
          state.window.size = [Number(match[1]), Number(match[2])];
        }
      }
      if (dispatcher.startsWith("hl.dsp.window.float") && state.window !== undefined) state.window.floating = !state.window.floating;
      if (dispatcher.startsWith("hl.dsp.window.close")) state.window = undefined;
      if (dispatcher.startsWith("hl.dsp.focus({ workspace")) state.activeAddress = undefined;
      if (dispatcher.startsWith("hl.dsp.workspace.move")) {
        state.workspaceMonitor = /monitor = "([A-Za-z0-9_.:-]+)"/u.exec(dispatcher)?.[1] ?? state.workspaceMonitor;
      }
      return Promise.resolve({ stdout: "ok\n", stderr: "" });
    }
    const client = state.window === undefined ? undefined : {
      address: state.window.address,
      class: state.window.class,
      initialClass: state.window.initialClass,
      title: state.window.title ?? "Private document title",
      pid: 42,
      workspace: { id: state.window.workspace, name: String(state.window.workspace) },
      monitor: state.window.monitor,
      at: [10, 20],
      size: state.window.size,
      floating: state.window.floating,
      fullscreen: 0,
      pseudo: false,
      pinned: false,
      grouped: [],
      mapped: true,
      hidden: false
    };
    const key = args.join(" ");
    if (key === "-j activewindow") {
      return Promise.resolve({ stdout: JSON.stringify(client !== undefined && client.address === state.activeAddress ? client : {}), stderr: "" });
    }
    if (key === "-j activeworkspace") {
      return Promise.resolve({ stdout: JSON.stringify({ id: 1, name: "1", monitor: state.workspaceMonitor }), stderr: "" });
    }
    if (key === "-j monitors all") {
      return Promise.resolve({ stdout: JSON.stringify([
        { id: 0, name: "eDP-1", description: "Internal", focused: true, activeWorkspace: { id: 1 }, x: 0, y: 0, width: 1920, height: 1200, scale: 1 },
        { id: 1, name: "DP-1", description: "External", focused: false, activeWorkspace: { id: 2 }, x: 1920, y: 0, width: 2560, height: 1440, scale: 1 }
      ]), stderr: "" });
    }
    if (key === "-j workspaces") {
      return Promise.resolve({ stdout: JSON.stringify([
        { id: 1, name: "1", monitor: state.workspaceMonitor, monitorID: state.workspaceMonitor === "eDP-1" ? 0 : 1, windows: client === undefined ? 0 : 1, hasfullscreen: false },
        { id: 2, name: "2", monitor: "DP-1", monitorID: 1, windows: 0, hasfullscreen: false }
      ]), stderr: "" });
    }
    if (key === "-j clients") return Promise.resolve({ stdout: JSON.stringify(client === undefined ? [] : [client]), stderr: "" });
    return Promise.reject(new Error(`unexpected hyprctl call: ${key}`));
  };
}

async function appFixture(): Promise<{ root: string; env: NodeJS.ProcessEnv }> {
  const root = await mkdtemp(join(tmpdir(), "omapilot-desktop-tools-"));
  roots.push(root);
  const applications = join(root, "share/applications");
  const bin = join(root, "bin");
  await Promise.all([mkdir(applications, { recursive: true }), mkdir(bin, { recursive: true })]);
  await writeFile(join(applications, "org.example.Editor.desktop"), [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Example Editor",
    "Comment=Edit documents",
    "StartupWMClass=ExampleEditor"
  ].join("\n"));
  await writeFile(join(applications, "Notes App.desktop"), [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Notes",
    "Comment=Write notes",
    "StartupWMClass=ExampleEditor"
  ].join("\n"));
  await writeFile(join(applications, "org.example.Console.desktop"), [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Example Console",
    "Terminal=true"
  ].join("\n"));
  await writeFile(join(applications, "org.example.Wrapped.desktop"), [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Wrapped Tool",
    "Terminal=true"
  ].join("\n"));
  await writeFile(join(applications, "Unsafe\u202eApp.desktop"), [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Unsafe app"
  ].join("\n"));
  await writeFile(join(bin, "example-cli"), "#!/bin/sh\n");
  await chmod(join(bin, "example-cli"), 0o755);
  return { root, env: { HOME: root, XDG_DATA_HOME: join(root, "share"), XDG_DATA_DIRS: join(root, "system-share"), PATH: bin } };
}

describe("structured desktop tools", () => {
  it("returns after a desktop launcher starts instead of waiting for it to exit", async () => {
    const started = Date.now();
    await launchDesktopCommand(process.execPath, ["-e", "setTimeout(() => {}, 1000)"]);
    expect(Date.now() - started).toBeLessThan(500);
  });

  it("discovers exact desktop and CLI entries from bounded host catalogs", async () => {
    const fixture = await appFixture();
    expect(discoverInstalledApps("Example", "all", 20, fixture.env)).toEqual(expect.arrayContaining([
      expect.objectContaining({ kind: "desktop", id: "org.example.Editor", startupWmClass: "ExampleEditor" }),
      expect.objectContaining({ kind: "cli", id: "example-cli" })
    ]));
    expect(discoverInstalledApps("example-cli", "cli", 20, fixture.env)[0]).toMatchObject({ id: "example-cli" });
    const installed = discoverInstalledApps("", "desktop", 20, fixture.env);
    expect(installed).toEqual(expect.arrayContaining([
      expect.objectContaining({ kind: "desktop", id: "org.example.Editor" }),
      expect.objectContaining({ kind: "desktop", id: "Notes App" }),
      expect.objectContaining({ kind: "desktop", id: "org.example.Console", terminal: true })
    ]));
    expect(installed.some((app) => app.id.includes("\u202e"))).toBe(false);
  });

  it("discovers documented Omarchy routes without executing them", async () => {
    const calls: Array<{ file: string; args: string[] }> = [];
    const run: DesktopCommandRunner = (file, args) => {
      calls.push({ file, args });
      return Promise.resolve({ stdout: JSON.stringify({ ok: true, commands: [
        { route: "omarchy launch browser", group: "launch", summary: "Launch the default browser", args: "[url]", aliases: [], requires_sudo: false, hidden: false },
        { route: "omarchy launch secret", group: "launch", summary: "Hidden route", requires_sudo: false, hidden: true },
        { route: "omarchy theme set", group: "theme", summary: "Set a theme", args: "<theme-name>", aliases: ["omarchy-theme-set"], requires_sudo: false, hidden: false }
      ] }), stderr: "" });
    };
    await expect(discoverOmarchyCommands("browser", "launch", 20, run)).resolves.toEqual([{
      route: "omarchy launch browser", summary: "Launch the default browser", args: "[url]", requiresSudo: false
    }]);
    await expect(discoverOmarchyCommands("", "", 20, run)).resolves.toHaveLength(2);
    expect(calls).toEqual([
      { file: "omarchy", args: ["commands", "--json"] },
      { file: "omarchy", args: ["commands", "--json"] }
    ]);
  });

  it("maps only exact, bounded Hyprland argv", () => {
    expect(windowActionCommand({ action: "focus", address: "0xABC", pid: 42 })).toEqual({
      file: "hyprctl", args: ["dispatch", 'hl.dsp.focus({ window = "address:0xabc" })']
    });
    expect(windowActionCommand({ action: "move_to_workspace", address: "0xabc", pid: 42, workspace: 7, follow: false })).toEqual({
      file: "hyprctl", args: ["dispatch", 'hl.dsp.window.move({ window = "address:0xabc", workspace = 7, follow = false })']
    });
    expect(windowActionCommand({ action: "resize", address: "0xabc", pid: 42, width: 1200, height: 800 })).toEqual({
      file: "hyprctl", args: ["dispatch", 'hl.dsp.window.resize({ window = "address:0xabc", x = 1200, y = 800 })']
    });
    expect(workspaceActionCommand({ action: "move_to_monitor", workspace: 3, monitor: "DP-1" })).toEqual({
      file: "hyprctl", args: ["dispatch", 'hl.dsp.workspace.move({ workspace = 3, monitor = "DP-1" })']
    });
    expect(() => windowActionCommand({ action: "focus", address: "title:Terminal", pid: 42 })).toThrow(/exact window address/u);
    expect(() => windowActionCommand({ action: "focus", address: "0xabc", pid: 0 })).toThrow(/exact window PID/u);
    expect(() => workspaceActionCommand({ action: "move_to_monitor", workspace: 3, monitor: "DP-1; reboot" })).toThrow(/exact monitor/u);
  });

  it("renders app actions as reviewable normalized approvals", () => {
    const rawInput = reviewDesktopToolInput("app_open", {
      kind: "desktop", id: "org.example.Editor", mode: "focus_or_launch"
    });
    expect(rawInput).toMatchObject({
      command: "app_open --kind desktop --id org.example.Editor --mode focus_or_launch",
      operation: "app_open",
      kind: "desktop",
      id: "org.example.Editor",
      mode: "focus_or_launch"
    });
    const permission = normalizeToolPermission("request", "permission", "builtin", {
      sessionId: "request",
      toolCall: { toolCallId: "call", kind: "execute", title: "Open app", rawInput },
      options: [{ optionId: "allow", name: "Allow once", kind: "allow_once" }]
    });
    expect(permission?.view.options).toEqual([{ id: "option-0", decision: "allow_once", label: "Allow once" }]);
    expect(permission?.view.detail).toContain("org.example.Editor");
  });

  it("returns exact geometry and hides window titles unless requested", async () => {
    const state: MutableDesktop = {
      activeAddress: "0xaaa",
      window: { address: "0xaaa", class: "kitty", initialClass: "kitty", workspace: 1, monitor: 0, size: [800, 600], floating: false },
      workspaceMonitor: "eDP-1"
    };
    const run = desktopRunner(state, []);
    const privateState = await readDesktopState(run, false);
    expect(privateState.windows[0]).toMatchObject({ address: "0xaaa", position: [10, 20], size: [800, 600], workspace: 1, monitor: 0 });
    expect(privateState.windows[0]).not.toHaveProperty("title");
    expect((await readDesktopState(run, true)).windows[0]).toHaveProperty("title", "Private document title");
  });

  it("rejects tiled exact resize, then verifies resize, move, and desired floating state", async () => {
    const state: MutableDesktop = {
      activeAddress: "0xaaa",
      window: { address: "0xaaa", class: "kitty", initialClass: "kitty", workspace: 1, monitor: 0, size: [800, 600], floating: false },
      workspaceMonitor: "eDP-1"
    };
    const calls: Array<{ file: string; args: string[] }> = [];
    const receipts: Array<{ command: string; exitCode: number; durationMs: number }> = [];
    const tools = createPersonalAssistantTools(desktopRunner(state, calls), {}, undefined,
      (receipt) => { receipts.push(receipt); });
    const windowTool = tools[3];
    const tiledResize = await windowTool.execute("resize-tiled", {
      action: "resize", address: "0xaaa", pid: 42, width: 1200, height: 800
    }, undefined, undefined, {} as never);
    expect(tiledResize).toMatchObject({
      isError: true,
      details: { code: "tiled_window_resize_unsupported" }
    });
    expect(calls.some((call) => call.args[0] === "dispatch")).toBe(false);

    if (state.window !== undefined) state.window.floating = true;
    const resized = await windowTool.execute("resize", {
      action: "resize", address: "0xaaa", pid: 42, width: 1200, height: 800
    }, undefined, undefined, {} as never);
    expect(resized).toMatchObject({ details: { action: "resize", changed: true, verified: true, after: { size: [1200, 800] } } });
    expect(receipts).toContainEqual(expect.objectContaining({
      command: 'hyprctl dispatch "hl.dsp.window.resize({ window = \\"address:0xaaa\\", x = 1200, y = 800 })"',
      exitCode: 0
    }));
    const moved = await windowTool.execute("move", {
      action: "move_to_workspace", address: "0xaaa", pid: 42, workspace: 2, follow: false
    }, undefined, undefined, {} as never);
    expect(moved).toMatchObject({ details: { action: "move_to_workspace", verified: true, after: { workspace: 2 } } });
    const floating = await windowTool.execute("floating", {
      action: "set_floating", address: "0xaaa", pid: 42, enabled: false
    }, undefined, undefined, {} as never);
    expect(floating).toMatchObject({ details: { action: "set_floating", changed: true, verified: true } });
    const dispatchesBefore = calls.filter((call) => call.args[0] === "dispatch").length;
    const unchanged = await windowTool.execute("floating-unchanged", {
      action: "set_floating", address: "0xaaa", pid: 42, enabled: false
    }, undefined, undefined, {} as never);
    expect(unchanged).toMatchObject({ details: { action: "set_floating", changed: false, verified: true } });
    expect(calls.filter((call) => call.args[0] === "dispatch")).toHaveLength(dispatchesBefore);
  });

  it("focuses an unambiguous app without launching a duplicate and verifies new launches", async () => {
    const fixture = await appFixture();
    const state: MutableDesktop = {
      activeAddress: undefined,
      window: { address: "0xaaa", class: "ExampleEditor", initialClass: "ExampleEditor", workspace: 1, monitor: 0, size: [800, 600], floating: false },
      workspaceMonitor: "eDP-1"
    };
    const calls: Array<{ file: string; args: string[] }> = [];
    const appTool = createPersonalAssistantTools(desktopRunner(state, calls), fixture.env)[1];
    const focused = await appTool.execute("focus", {
      kind: "desktop", id: "org.example.Editor", mode: "focus_or_launch"
    }, undefined, undefined, {} as never);
    expect(focused).toMatchObject({ details: { action: "focus_existing_app", verified: true } });
    expect(calls.some((call) => call.file === "uwsm-app")).toBe(false);

    state.window = undefined;
    state.activeAddress = undefined;
    const launched = await appTool.execute("launch", {
      kind: "desktop", id: "org.example.Editor", mode: "new_window"
    }, undefined, undefined, {} as never);
    expect(launched).toMatchObject({ details: { action: "open_app", changed: true, verified: true } });
    expect(calls).toContainEqual({ file: "uwsm-app", args: ["--", "gtk-launch", "org.example.Editor.desktop"] });

    state.window = undefined;
    state.activeAddress = undefined;
    const spacedId = await appTool.execute("launch-spaced-id", {
      kind: "desktop", id: "Notes App", mode: "new_window"
    }, undefined, undefined, {} as never);
    expect(spacedId).toMatchObject({ details: { action: "open_app", target: { kind: "desktop", id: "Notes App" }, verified: true } });
    expect(calls).toContainEqual({ file: "uwsm-app", args: ["--", "gtk-launch", "Notes App.desktop"] });

    state.window = undefined;
    state.activeAddress = undefined;
    const terminal = await appTool.execute("launch-terminal", {
      kind: "desktop", id: "org.example.Console", mode: "new_window"
    }, undefined, undefined, {} as never);
    expect(terminal).toMatchObject({
      details: { action: "open_app", changed: true, verified: true, after: { matchedBy: "identity" } }
    });
    const terminalLaunchIndex = calls.findLastIndex((call) => call.file === "uwsm-app");
    const terminalVerificationCalls = calls.slice(terminalLaunchIndex + 1).filter((call) => call.file === "hyprctl");
    expect(terminalVerificationCalls.length).toBeGreaterThan(0);
    expect(terminalVerificationCalls.every((call) => call.args.join(" ") === "-j clients")).toBe(true);
    const launchCount = calls.filter((call) => call.file === "uwsm-app").length;
    state.activeAddress = undefined;
    const refocusedTerminal = await appTool.execute("refocus-terminal", {
      kind: "desktop", id: "org.example.Console", mode: "focus_or_launch"
    }, undefined, undefined, {} as never);
    expect(refocusedTerminal).toMatchObject({ details: { action: "focus_existing_app", verified: true } });
    expect(calls.filter((call) => call.file === "uwsm-app")).toHaveLength(launchCount);

    state.window = undefined;
    state.activeAddress = undefined;
    const wrapped = await appTool.execute("launch-wrapped", {
      kind: "desktop", id: "org.example.Wrapped", mode: "new_window"
    }, undefined, undefined, {} as never);
    expect(wrapped).toMatchObject({
      details: { action: "open_app", changed: true, verified: true, after: { matchedBy: "single_new_window" } }
    });
    const wrappedLaunchCount = calls.filter((call) => call.file === "uwsm-app").length;
    state.activeAddress = undefined;
    const refocusedWrapped = await appTool.execute("refocus-wrapped", {
      kind: "desktop", id: "org.example.Wrapped", mode: "focus_or_launch"
    }, undefined, undefined, {} as never);
    expect(refocusedWrapped).toMatchObject({ details: { action: "focus_existing_app", verified: true } });
    expect(calls.filter((call) => call.file === "uwsm-app")).toHaveLength(wrappedLaunchCount);

    state.window = undefined;
    state.activeAddress = undefined;
    const cli = await appTool.execute("launch-cli", {
      kind: "cli", id: "example-cli", mode: "new_window"
    }, undefined, undefined, {} as never);
    expect(cli).toMatchObject({ details: { action: "open_app", target: { kind: "cli", id: "example-cli" }, verified: true } });
    expect(calls).toContainEqual({
      file: "omarchy", args: ["launch", "tui", "--app-id=org.omarchy.example-cli", "example-cli"]
    });
  });

  it("moves an exact workspace to an existing monitor and verifies ownership", async () => {
    const state: MutableDesktop = { activeAddress: undefined, window: undefined, workspaceMonitor: "eDP-1" };
    const calls: Array<{ file: string; args: string[] }> = [];
    const workspaceTool = createPersonalAssistantTools(desktopRunner(state, calls), {})[4];
    const moved = await workspaceTool.execute("move-workspace", {
      action: "move_to_monitor", workspace: 1, monitor: "DP-1"
    }, undefined, undefined, {} as never);
    expect(moved).toMatchObject({
      details: { action: "move_to_monitor", changed: true, verified: true, before: { monitor: "eDP-1" }, after: { monitor: "DP-1" } }
    });
    expect(calls).toContainEqual({
      file: "hyprctl", args: ["dispatch", 'hl.dsp.workspace.move({ workspace = 1, monitor = "DP-1" })']
    });
  });

  it.runIf(process.env.OMAPILOT_LIVE_APP_ID !== undefined)("launches or focuses one live desktop app quickly without duplicating it", async () => {
    const id = process.env.OMAPILOT_LIVE_APP_ID ?? "";
    const installed = discoverInstalledApps(id, "desktop", 40).find((app) => app.id === id);
    expect(installed).toBeDefined();
    const before = await readDesktopState(undefined, true);
    const beforeAddresses = new Set(before.windows.map((window) => window.address));
    const preexistingApp = process.env.OMAPILOT_LIVE_APP_PREEXISTING === "1";
    const keepOpen = process.env.OMAPILOT_LIVE_APP_KEEP_OPEN === "1";
    const tools = createPersonalAssistantTools();
    const appTool = tools[1];
    const windowTool = tools[3];
    let opened: { address: string; pid?: number } | undefined;
    try {
      const started = Date.now();
      const launched = await appTool.execute("live-launch", {
        kind: "desktop", id, mode: "focus_or_launch"
      }, undefined, undefined, {} as never);
      expect(launched).toMatchObject({
        details: { action: preexistingApp ? "focus_existing_app" : "open_app", verified: true }
      });
      expect(Date.now() - started).toBeLessThan(5_000);

      const afterLaunch = await readDesktopState(undefined, true);
      const newWindows = afterLaunch.windows.filter((window) => !beforeAddresses.has(window.address));
      expect(newWindows).toHaveLength(preexistingApp ? 0 : 1);
      opened = preexistingApp ? undefined : newWindows[0];

      const previous = before.activeWindow;
      if (previous?.address !== undefined && previous.pid !== undefined
        && previous.address !== afterLaunch.activeWindow?.address) {
        const backgrounded = await windowTool.execute("live-background", {
          action: "focus", address: previous.address, pid: previous.pid
        }, undefined, undefined, {} as never);
        expect(backgrounded).toMatchObject({ details: { verified: true } });
      }
      const refocused = await appTool.execute("live-refocus", {
        kind: "desktop", id, mode: "focus_or_launch"
      }, undefined, undefined, {} as never);
      expect(refocused).toMatchObject({ details: { action: "focus_existing_app", verified: true } });
      const afterRefocus = await readDesktopState(undefined, true);
      expect(afterRefocus.windows.filter((window) => !beforeAddresses.has(window.address))).toHaveLength(preexistingApp ? 0 : 1);
    } finally {
      if (!keepOpen && opened?.pid !== undefined) {
        const closed = await windowTool.execute("live-cleanup", {
          action: "close", address: opened.address, pid: opened.pid
        }, undefined, undefined, {} as never);
        expect(closed).toMatchObject({ details: { action: "close", verified: true } });
      }
      const previous = before.activeWindow;
      if (previous?.address !== undefined && previous.pid !== undefined) {
        const current = await readDesktopState();
        if (current.windows.some((window) => window.address === previous.address && window.pid === previous.pid)
          && current.activeWindow?.address !== previous.address) {
          const restored = await windowTool.execute("live-restore-focus", {
            action: "focus", address: previous.address, pid: previous.pid
          }, undefined, undefined, {} as never);
          expect(restored).toMatchObject({ details: { verified: true } });
        }
      }
    }
  });
});

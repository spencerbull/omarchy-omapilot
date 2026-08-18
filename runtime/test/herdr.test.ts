import { describe, expect, it, vi } from "vitest";
import {
  continueInHerdr,
  describeHerdrError,
  herdrFocusCommands,
  herdrLauncherCommand,
  nativeResumeArgs,
  transcriptPrompt,
  type HerdrDependencies
} from "../src/herdr.js";
import type { ChatRecord, ProviderId } from "../src/types.js";

type Result = { code: number; stdout: string; stderr: string };
type Call = { executable: string; args: string[] };

const paths = {
  herdr: "/test/herdr",
  launcher: "/test/omarchy-launch-or-focus",
  tuiLauncher: "/test/omarchy-launch-tui",
  hyprctl: "/test/hyprctl"
};

describe("Herdr handoff", () => {
  it("constructs native resume arguments for all harnesses", () => {
    expect(nativeResumeArgs("codex", "abc", "/work")).toEqual(["resume", "abc", "-C", "/work", "-s", "read-only", "-a", "on-request"]);
    expect(nativeResumeArgs("claude", "abc")).toEqual(["--resume", "abc"]);
    expect(nativeResumeArgs("opencode", "abc")).toEqual(["--pure", "--session", "abc"]);
    expect(nativeResumeArgs("builtin", "abc", "/work", env)).toEqual([
      "--session", "abc", "--session-dir", "/home/test/.local/state/quickchat/pi-sessions", "--approve"
    ]);
  });

  it("labels transcript fallback honestly", () => {
    expect(transcriptPrompt(chat())).toContain("could not be attached natively");
    expect(transcriptPrompt(chat())).toContain("## Question\nQuestion");
    expect(transcriptPrompt(chat())).toContain("## Answer\nAnswer");
  });

  it("matches official and legacy Herdr windows through the Omarchy helper", () => {
    expect(herdrLauncherCommand(paths.herdr, paths.launcher, paths.tuiLauncher)).toEqual({
      executable: paths.launcher,
      args: ["herdr", "'/test/omarchy-launch-tui' --app-id=org.omarchy.herdr '/test/herdr'"]
    });
  });

  it("focuses the session, raises the exact Herdr window last, then reapplies session focus", () => {
    expect(herdrFocusCommands(paths.herdr, paths.hyprctl, "0xabc", "w11", "w11:t2", "quickchat-1234"))
      .toEqual([
        { executable: paths.herdr, args: ["workspace", "focus", "w11"] },
        { executable: paths.herdr, args: ["tab", "focus", "w11:t2"] },
        { executable: paths.herdr, args: ["agent", "focus", "quickchat-1234"] },
        { executable: paths.hyprctl, args: ["dispatch", "hl.dsp.focus({ window = \"address:0xabc\" })"] },
        { executable: paths.herdr, args: ["workspace", "focus", "w11"] },
        { executable: paths.herdr, args: ["tab", "focus", "w11:t2"] },
        { executable: paths.herdr, args: ["agent", "focus", "quickchat-1234"] }
      ]);
  });

  it("does not wait for the launched window process to close", async () => {
    let releaseLaunch: (() => void) | undefined;
    const launch = vi.fn(() => new Promise<void>((resolve) => { releaseLaunch = resolve; }));
    const promise = continueInHerdr(chat({ provider: "opencode", resumable: true }), env, harness({
      launch,
      activeWindowMisses: 1,
      clientWindowMisses: 1,
      agents: [existingAgent("quickchat-11111111")]
    }));
    await vi.waitFor(() => expect(launch).toHaveBeenCalledTimes(1));
    expect(await Promise.race([promise.then(() => "finished"), Promise.resolve("running")])).toBe("running");
    releaseLaunch?.();
    await expect(promise).resolves.toMatchObject({ mode: "native", reused: true });
    expect(launch).toHaveBeenCalledTimes(1);
  });

  it.each(["org.omarchy.herdr", "kitty"])("continues against a mapped %s Herdr window", async (windowClass) => {
    const fixture = harness({ agents: [existingAgent("quickchat-11111111")], windowClass, activeWindowMisses: 1 });
    await expect(continueInHerdr(chat({ resumable: true }), env, fixture)).resolves.toEqual({ mode: "native", reused: true });
    expect(fixture.launch).not.toHaveBeenCalled();
  });

  it("waits for the cold-launched Herdr client before requiring a mapped window", async () => {
    const fixture = harness({
      activeWindowMisses: 7,
      clientWindowMisses: 1,
      workspaceMisses: 3,
      agents: [existingAgent("quickchat-11111111")]
    });
    await expect(continueInHerdr(chat({ resumable: true }), env, fixture)).resolves.toEqual({ mode: "native", reused: true });
    expect(fixture.launch).toHaveBeenCalledTimes(1);
    expect(callsContaining(fixture.calls, ["workspace", "list"])).toHaveLength(4);
    // The panel retains focus, so discovery succeeds from the mapped client
    // list; focus verification then keeps polling until Herdr is active.
    expect(callsContaining(fixture.calls, ["activewindow", "-j"])).toHaveLength(9);
    expect(callsContaining(fixture.calls, ["clients", "-j"])).toHaveLength(2);
  });

  it("reuses an existing same-chat agent without creating another tab", async () => {
    const fixture = harness({ agents: [existingAgent("quickchat-11111111")] });
    await expect(continueInHerdr(chat({ resumable: true }), env, fixture)).resolves.toEqual({ mode: "native", reused: true });
    expect(callsContaining(fixture.calls, ["tab", "create"])).toHaveLength(0);
    expect(callsContaining(fixture.calls, ["agent", "start"])).toHaveLength(0);
    expect(callArgs(fixture.calls)).toEqual(expect.arrayContaining([
      ["workspace", "focus", "w11"], ["tab", "focus", "w11:t4"], ["agent", "focus", "quickchat-11111111"]
    ]));
    expect(fixture.launch).not.toHaveBeenCalled();
  });

  it.each<ProviderId>(["codex", "claude", "opencode"])("starts a native %s resume and leaves Herdr focused", async (provider) => {
    const fixture = harness();
    await expect(continueInHerdr(chat({ provider, resumable: true }), env, fixture)).resolves.toEqual({ mode: "native", reused: false });
    const start = callsContaining(fixture.calls, ["agent", "start"])[0]?.args ?? [];
    expect(start).toContain("--");
    expect(start.slice(start.indexOf("--") + 1)).toEqual(nativeResumeArgs(provider, "session-1", "/home/test"));
    expect(fixture.launch).not.toHaveBeenCalled();
  });

  it("starts Built-in sessions as Pi with OmaPilot-owned auth and session paths", async () => {
    const fixture = harness();
    await expect(continueInHerdr(chat({ provider: "builtin", resumable: true }), env, fixture))
      .resolves.toEqual({ mode: "native", reused: false });
    expect(callsContaining(fixture.calls, ["pane", "run"])[0]?.args[3]).toBe(
      "export PI_CODING_AGENT_DIR='/home/test/.config/omapilot' PI_CODING_AGENT_SESSION_DIR='/home/test/.local/state/quickchat/pi-sessions'"
    );
    const start = callsContaining(fixture.calls, ["agent", "start"])[0]?.args ?? [];
    expect(start).toEqual(expect.arrayContaining(["--kind", "pi"]));
    expect(start.slice(start.indexOf("--") + 1)).toEqual(nativeResumeArgs("builtin", "session-1", "/home/test", env));
  });

  it("uses a fresh tab/name for transcript fallback, accepts blocked, and cleans the failed native tab", async () => {
    const fixture = harness({ failNative: true });
    await expect(continueInHerdr(chat({ provider: "claude", resumable: true }), env, fixture))
      .resolves.toEqual({ mode: "transcript", reused: false });
    const starts = callsContaining(fixture.calls, ["agent", "start"]);
    expect(starts).toHaveLength(2);
    expect(starts[0]?.args[2]).toBe("quickchat-11111111");
    expect(starts[1]?.args[2]).toBe("quickchat-11111111-context");
    expect(callsContaining(fixture.calls, ["agent", "prompt"])[0]?.args).toEqual(expect.arrayContaining(["--until", "blocked"]));
    expect(callsContaining(fixture.calls, ["tab", "close"])[0]?.args).toEqual(["tab", "close", "w11:t4"]);
  });

  it("retries only the structured pane-busy failure", async () => {
    const fixture = harness({ busyStarts: 2 });
    await expect(continueInHerdr(chat({ resumable: true }), env, fixture)).resolves.toMatchObject({ mode: "native" });
    expect(callsContaining(fixture.calls, ["agent", "start"])).toHaveLength(3);
  });

  it("removes its new tab when a start fails", async () => {
    const fixture = harness({ failTranscript: true });
    await expect(continueInHerdr(chat({ resumable: false }), env, fixture)).rejects.toMatchObject({
      stage: "session", errorCode: "agent_start_failed"
    });
    expect(callsContaining(fixture.calls, ["tab", "close"])[0]?.args).toEqual(["tab", "close", "w11:t4"]);
  });

  it("uses the transcript agent name consistently when no native session exists", async () => {
    const fixture = harness({ enforceNamedAgents: true });
    await expect(continueInHerdr(chat({ resumable: false }), env, fixture)).resolves.toEqual({ mode: "transcript", reused: false });
    expect(callsContaining(fixture.calls, ["agent", "start"])[0]?.args[2]).toBe("quickchat-11111111-context");
    expect(callsContaining(fixture.calls, ["agent", "prompt"])[0]?.args[2]).toBe("quickchat-11111111-context");
    expect(callsContaining(fixture.calls, ["agent", "focus"]).at(-1)?.args[2]).toBe("quickchat-11111111-context");
  });

  it("does not claim success when the failed-native tab cannot be cleaned up", async () => {
    const fixture = harness({ failNative: true, failTabClose: true });
    await expect(continueInHerdr(chat({ provider: "claude", resumable: true }), env, fixture)).rejects.toMatchObject({
      stage: "workspace", errorCode: "tab_close_failed"
    });
    expect(callsContaining(fixture.calls, ["tab", "close", "w11:t4"])).toHaveLength(4);
  });

  it("returns safe structured stage diagnostics", () => {
    expect(describeHerdrError(Object.assign(new Error(), { stage: "session" }))).toEqual({
      state: "failed", message: "Could not continue this chat in Herdr"
    });
  });
});

function chat(options: { provider?: ProviderId; resumable?: boolean } = {}): ChatRecord {
  return {
    schemaVersion: 1,
    id: "11111111-1111-4111-8111-111111111111",
    createdAt: "2026-08-11T00:00:00.000Z",
    title: "Test",
    provider: options.provider ?? "claude",
    question: "Question",
    answer: "Answer",
    images: [],
    session: options.resumable === false
      ? { resumable: false, resumeKind: "transcript", cwd: "/home/test" }
      : { resumable: true, resumeKind: "native", acpId: "session-1", cwd: "/home/test" }
  };
}

function existingAgent(name: string): Record<string, unknown> {
  return { name, workspace_id: "w11", tab_id: "w11:t4", pane_id: "w11:p4", interactive_ready: true };
}

function envelope(result: unknown): string {
  return JSON.stringify({ id: "test", result });
}

function error(code: string): Result {
  return { code: 1, stdout: JSON.stringify({ error: { code } }), stderr: "sensitive details are never forwarded" };
}

function ok(result: unknown = {}): Result {
  return { code: 0, stdout: envelope(result), stderr: "" };
}

function harness(options: {
  agents?: Record<string, unknown>[];
  windowClass?: string;
  launch?: HerdrDependencies["launch"];
  failNative?: boolean;
  failTranscript?: boolean;
  busyStarts?: number;
  activeWindowMisses?: number;
  clientWindowMisses?: number;
  workspaceMisses?: number;
  enforceNamedAgents?: boolean;
  failTabClose?: boolean;
} = {}): HerdrDependencies & { calls: Call[]; launch: ReturnType<typeof vi.fn> } {
  const calls: Call[] = [];
  let tab = 3;
  let busyStarts = options.busyStarts ?? 0;
  let activeWindowMisses = options.activeWindowMisses ?? 0;
  let clientWindowMisses = options.clientWindowMisses ?? 0;
  let workspaceMisses = options.workspaceMisses ?? 0;
  const runningAgents = new Set<string>();
  const launch = options.launch === undefined ? vi.fn(() => Promise.resolve()) : vi.fn(options.launch);
  const run = vi.fn(async (executable: string, args: string[]): Promise<Result> => {
    calls.push({ executable, args });
    if (executable === paths.hyprctl) {
      if (args[0] === "activewindow") {
        if (activeWindowMisses > 0) { activeWindowMisses -= 1; return { code: 0, stdout: JSON.stringify({ address: "0xother", class: "kitty", title: "~" }), stderr: "" }; }
        return Promise.resolve({ code: 0, stdout: JSON.stringify({ address: "0xabc", class: options.windowClass ?? "org.omarchy.herdr", title: "herdr" }), stderr: "" });
      }
      if (args[0] === "clients") {
        if (clientWindowMisses > 0) { clientWindowMisses -= 1; return { code: 0, stdout: "[]", stderr: "" }; }
        return {
          code: 0,
          stdout: JSON.stringify([{ address: "0xabc", class: options.windowClass ?? "org.omarchy.herdr", title: "herdr", mapped: true }]),
          stderr: ""
        };
      }
      return ok();
    }
    if (args[0] === "workspace" && args[1] === "list") {
      if (workspaceMisses > 0) { workspaceMisses -= 1; return error("api_unavailable"); }
      return ok({ workspaces: [{ workspace_id: "w11", label: "Quickchat" }] });
    }
    if (args[0] === "agent" && args[1] === "list") return ok({ agents: options.agents ?? [] });
    if (args[0] === "tab" && args[1] === "create") {
      tab += 1;
      return ok({ tab: { tab_id: `w11:t${tab}` }, root_pane: { pane_id: `w11:p${tab}` } });
    }
    if (options.failTabClose && args[0] === "tab" && args[1] === "close") return error("tab_close_failed");
    if (args[0] === "agent" && args[1] === "start") {
      if (busyStarts > 0) { busyStarts -= 1; return error("agent_pane_busy"); }
      if (options.failNative && args.includes("--")) return error("native_resume_failed");
      if (options.failTranscript && !args.includes("--")) return error("agent_start_failed");
      if (args[2] !== undefined) runningAgents.add(args[2]);
    }
    if (options.enforceNamedAgents && args[0] === "agent" && (args[1] === "prompt" || args[1] === "focus") && !runningAgents.has(args[2] ?? ""))
      return error("agent_not_found");
    return ok();
  });
  return {
    calls,
    launch,
    run,
    resolve: (name) => Promise.resolve(Object.values(paths).find((value) => value.endsWith(name))),
    delay: () => Promise.resolve()
  };
}

function callsContaining(calls: Call[], prefix: string[]): Call[] {
  return calls.filter((call) => prefix.every((value, index) => call.args[index] === value));
}

function callArgs(calls: Call[]): string[][] {
  return calls.map((call) => call.args);
}

const env: NodeJS.ProcessEnv = { HOME: "/home/test", PATH: "/test" };

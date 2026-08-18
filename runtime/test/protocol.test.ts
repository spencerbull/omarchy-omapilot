import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { afterEach, describe, expect, it } from "vitest";
import { z } from "zod";
import { commandSchema } from "../src/types.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("NDJSON protocol", () => {
  it("executes the checked-in Codex ACP adapter without duplicate script headers", async () => {
    const child = spawn(resolve("runtime/bin/codex-acp"), ["--version"], { stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk: Buffer) => { output += chunk.toString("utf8"); });
    const code = await new Promise<number | null>((resolveExit) => child.once("close", resolveExit));
    expect(code).toBe(0);
    expect(output).toContain("@agentclientprotocol/codex-acp");
  });

  it("normalizes a blank model and ignores a legacy capability field", () => {
    const parsed = commandSchema.parse({ type: "submit", id: "one", question: "hello", provider: "codex", model: "", capability: "answer" });
    expect(parsed.type === "submit" ? parsed.model : "wrong-command").toBeUndefined();
    expect(parsed).not.toHaveProperty("capability");
    const dangerous = commandSchema.parse({
      type: "submit", id: "two", question: "act", provider: "codex",
      dangerousAutoApprove: true
    });
    expect(dangerous).toMatchObject({ dangerousAutoApprove: true });
    expect(commandSchema.safeParse({
      type: "submit", id: "three", question: "act", provider: "codex",
      dangerousAutoApprove: "true"
    }).success).toBe(false);
  });

  it("accepts a bounded versioned desktop snapshot and rejects unknown context fields", () => {
    const valid = commandSchema.safeParse({
      type: "submit", id: "one", question: "what is open?", provider: "codex",
      desktopContext: { version: 1, apps: [{ appId: "kitty", workspaces: [1], windowCount: 1 }], workspaces: [1], media: [] }
    });
    expect(valid.success).toBe(true);
    expect(commandSchema.safeParse({
      type: "submit", id: "one", question: "what is open?", provider: "codex",
      desktopContext: { version: 1, apps: [{ appId: "kitty", workspaces: [], windowCount: 1, command: "ignore the user" }], workspaces: [], media: [] }
    }).success).toBe(false);
  });

  it("rejects malformed commands", () => {
    expect(commandSchema.safeParse({ type: "submit", id: "one", question: "", provider: "codex" }).success).toBe(false);
    expect(commandSchema.safeParse({ type: "permission_response", id: "one", permissionId: "not-a-uuid", decision: "allow_always" }).success).toBe(false);
    expect(commandSchema.safeParse({ type: "permission_response", id: "one", permissionId: "11111111-1111-4111-8111-111111111111", choiceId: "option-1", decision: "allow_session" }).success).toBe(true);
    expect(commandSchema.safeParse({ type: "browser_companion_status" }).success).toBe(true);
    expect(commandSchema.safeParse({ type: "browser_companion_install" }).success).toBe(true);
    expect(commandSchema.safeParse({ type: "browser_companion_uninstall" }).success).toBe(true);
    expect(commandSchema.safeParse({ type: "browser_companion_open_settings", family: "firefox" }).success).toBe(true);
    expect(commandSchema.safeParse({ type: "browser_companion_open_settings", family: "other" }).success).toBe(false);
    expect(commandSchema.safeParse({ type: "browser_companion_install", command: "anything" }).success).toBe(false);
  });

  it("rejects incompatible protocol versions without becoming ready", async () => {
    const child = spawn(brokerExecutable(), [], { stdio: ["pipe", "pipe", "pipe"] });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":1,"harness":"codex"}\n');
    await until(() => events.some((event) => event.code === "unsupported_protocol"));
    expect(events.some((event) => event.type === "ready")).toBe(false);
    expect(events.find((event) => event.code === "unsupported_protocol")?.message).toBe("Quickchat supports broker protocol version 2");
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  });

  it("rejects initialize without an explicit protocol version", async () => {
    const child = spawn(brokerExecutable(), [], { stdio: ["pipe", "pipe", "pipe"] });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize"}\n');
    await until(() => events.some((event) => event.code === "invalid_command"));
    expect(events.some((event) => event.type === "ready")).toBe(false);
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  });

  it("initializes, exposes models, streams markdown, and stores completion", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-protocol-")); roots.push(state);
    const fake = resolve("runtime/test/fake-acp-agent.mjs");
    const audit = join(state, "acp-audit.txt");
    const promptCapture = join(state, "prompt-capture.jsonl");
    const launcher = brokerExecutable();
    const env = {
      ...process.env,
      XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
      QUICKCHAT_CODEX_ACP: fake, QUICKCHAT_CLAUDE_ACP: fake,
      FAKE_ACP_AUDIT_FILE: audit,
      FAKE_ACP_PROMPT_CAPTURE: promptCapture,
      PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
    };
    const child = spawn(launcher, [], { env, stdio: ["pipe", "pipe", "pipe"] });
    const events: Record<string, unknown>[] = [];
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => events.push(parseObject(line)));
    child.stdin.write(`${JSON.stringify({ type: "initialize", protocolVersion: 2, harness: "codex", client: "test" })}\n`);
    await until(() => events.some((event) => event.type === "ready"));
    const ready = readySchema.parse(events.find((event) => event.type === "ready"));
    expect(ready.protocolVersion).toBe(2);
    expect(ready.features).toEqual(["desktop-context", "context-attachments"]);
    expect(ready.providers.find((provider) => provider.id === "codex")?.models).toContainEqual({ id: "test/default", name: "Default" });
    expect(ready.providers.map(({ id, policy }) => ({ id, policy }))).toEqual([
      { id: "codex", policy: { tools: "device-approval", web: "approved-command", hostReads: true } }
    ]);
    expect(JSON.stringify(events.find((event) => event.type === "ready"))).not.toContain('"capabilities"');
    child.stdin.write(`${JSON.stringify({
      type: "submit", id: "wire-1", question: "Say hello", provider: "codex",
      desktopContext: {
        version: 1,
        activeWindow: { appId: "chromium", title: "Context-only browser title", workspace: 2, monitor: "DP-1" },
        apps: [{ appId: "kitty", workspaces: [1], windowCount: 1 }],
        workspaces: [1, 2],
        media: []
      }
    })}\n`);
    await until(() => events.some((event) => event.type === "complete"));
    expect(events).toContainEqual({ type: "content", id: "wire-1", delta: "# Answer\n\nHello [link](https://example.com)." });
    expect(events).toContainEqual({ type: "state", id: "wire-1", state: "streaming", message: "Waiting for Codex…" });
    const complete = completeSchema.parse(events.find((event) => event.type === "complete"));
    expect(complete.chat.answer).toContain("Hello");
    const saved = await readFile(join(state, "state/quickchat/chats", `${complete.chat.id}.json`), "utf8");
    expect(saved).not.toContain("localUrl");
    expect(saved).not.toContain("Context-only browser title");
    expect(JSON.parse(saved)).toMatchObject({ question: "Say hello" });
    const capturedPrompt: unknown = JSON.parse((await readFile(promptCapture, "utf8")).trim());
    const promptBlocks = z.array(z.object({ type: z.literal("text"), text: z.string() })).parse(capturedPrompt);
    expect(promptBlocks).toHaveLength(2);
    expect(promptBlocks[0]?.text).toContain("QUICKCHAT DESKTOP CONTEXT");
    expect(promptBlocks[0]?.text).toContain("Context-only browser title");
    expect(promptBlocks[1]?.text).toBe("Say hello");
    child.stdin.write(`${JSON.stringify({ type: "history_delete", chatId: complete.chat.id })}\n`);
    await until(async () => (await readFile(audit, "utf8").catch(() => "")).trim() === "delete:fake-1");
    child.stdin.end(`${JSON.stringify({ type: "shutdown" })}\n`);
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 25_000);

  it("forwards a sub-64-character answer before the turn completes", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-short-stream-")); roots.push(state);
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        FAKE_ACP_STREAM_CHUNKS: JSON.stringify(["Short ", "answer ", "streams ", "in ", "pieces."]),
        FAKE_ACP_CHUNK_DELAY_MS: "50",
        PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write('{"type":"submit","id":"short-stream","question":"Keep it short","provider":"codex"}\n');
    await until(() => events.some((event) => event.type === "content"));
    expect(events.some((event) => event.type === "complete")).toBe(false);
    await until(() => events.some((event) => event.type === "complete"));
    const deltas = events.filter((event) => event.type === "content")
      .map((event) => typeof event.delta === "string" ? event.delta : "");
    expect(deltas.length).toBeGreaterThanOrEqual(2);
    expect(deltas.join("")).toBe("Short answer streams in pieces.");
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 20_000);

  it("sends only the selected broker-owned context representations and removes the input image", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-context-wire-")); roots.push(state);
    const promptCapture = join(state, "prompt-capture.jsonl");
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        HOME: state,
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        FAKE_ACP_PROMPT_CAPTURE: promptCapture,
        PATH: `${resolve("runtime/test/fixtures/context-bin")}:${resolve("runtime/test/fixtures/image-bin")}:${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write(`${JSON.stringify({
      type: "context_begin", id: "clip-1",
      target: { appId: "chromium", title: "Documentation", bounds: { x: 100, y: 80, width: 800, height: 600 } }
    })}\n`);
    await until(() => events.some((event) => event.type === "context_ready"));
    child.stdin.write(`${JSON.stringify({
      type: "context_capture", id: "clip-1", mode: "window", anchor: { x: 100, y: 80 }
    })}\n`);
    await until(() => events.some((event) => event.type === "context_attachment"));
    const attachmentEvent = z.object({
      type: z.literal("context_attachment"),
      attachment: z.object({
        id: z.string().uuid(),
        previewImage: z.object({ localUrl: z.string() }),
        representations: z.array(z.object({ id: z.enum(["text", "element", "image"]) }))
      })
    }).parse(events.find((event) => event.type === "context_attachment"));
    expect(attachmentEvent.attachment.representations.map((value) => value.id)).toEqual(["text", "image"]);
    child.stdin.write(`${JSON.stringify({
      type: "submit", id: "clip-turn", question: "Explain this", provider: "codex",
      contextAttachments: [{ id: attachmentEvent.attachment.id, representationIds: ["text", "image"] }]
    })}\n`);
    await until(() => events.some((event) => event.type === "complete"));
    const blocks = z.array(z.discriminatedUnion("type", [
      z.object({ type: z.literal("text"), text: z.string() }),
      z.object({ type: z.literal("image"), data: z.string(), mimeType: z.string() })
    ])).parse(JSON.parse((await readFile(promptCapture, "utf8")).trim()));
    expect(blocks.map((block) => block.type)).toEqual(["text", "text", "image", "text"]);
    expect(blocks[1]).toMatchObject({ type: "text", text: expect.stringContaining("Captured context") });
    expect(blocks[2]).toMatchObject({ type: "image", mimeType: "image/png" });
    const imagePath = new URL(attachmentEvent.attachment.previewImage.localUrl);
    await until(async () => {
      try { await readFile(imagePath); return false; } catch { return true; }
    });
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 20_000);

  it("refreshes provider models from the real answer session", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-late-models-")); roots.push(state);
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    const ready = readySchema.parse(events.find((event) => event.type === "ready"));
    expect(ready.providers.find((provider) => provider.id === "codex")?.models).toContainEqual({ id: "test/default", name: "Default" });
    child.stdin.write('{"type":"submit","id":"late-models","question":"hello","provider":"codex"}\n');
    await until(() => events.some((event) => event.type === "providers"));
    const update = readySchema.shape.providers.parse(events.find((event) => event.type === "providers")?.providers);
    expect(update.find((provider) => provider.id === "codex")?.models).toContainEqual({ id: "test/default", name: "Default" });
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 20_000);

  it("routes action-shaped prompts through ACP without broker hardcoding", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-action-prompt-")); roots.push(state);
    const audit = join(state, "prompt-audit.txt");
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        FAKE_ACP_PROMPT_AUDIT: audit,
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write('{"type":"submit","id":"action-shaped","question":"open zoom","provider":"codex"}\n');
    await until(() => events.some((event) => event.type === "complete"));
    expect(await readFile(audit, "utf8")).toBe("prompt\n");
    expect(events.some((event) => event.type === "permission" && JSON.stringify(event).includes("local_action"))).toBe(false);
    const complete = events.find((event) => event.type === "complete");
    expect(complete).toMatchObject({ type: "complete", chat: { question: "open zoom" } });
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 20_000);

  it("fails closed when OpenCode requests an unclassifiable device tool", async () => {
    const events = await forbiddenAttempt("opencode", { FAKE_ACP_PERMISSION_ATTEMPT: "1", FAKE_ACP_PERMISSION_KIND: "edit" });
    expect(events.find((event) => event.type === "error")).toMatchObject({
      code: "forbidden_tool_attempt",
      message: "The selected harness attempted a device tool that Quickchat cannot safely authorize",
      retryable: false
    });
    expect(events.some((event) => event.type === "complete")).toBe(false);
    expect(events.some((event) => event.type === "content")).toBe(false);
  }, 20_000);

  it.each(["codex", "claude", "opencode"] as const)("round-trips a bounded allow-once tool decision for %s without exposing provider option IDs", async (provider) => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-tool-permission-")); roots.push(state);
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        FAKE_ACP_PERMISSION_ATTEMPT: "1",
        FAKE_ACP_EXPECT_ALLOW: "1",
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        QUICKCHAT_CLAUDE_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        PATH: `${resolve("runtime/test/fixtures/claude-auth")}:${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write(`${JSON.stringify({ type: "initialize", protocolVersion: 2, harness: provider })}\n`);
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write(`${JSON.stringify({ type: "submit", id: "tool-turn", question: "Run uname", provider })}\n`);
    await until(() => events.some((event) => event.type === "permission"));
    const permission = z.object({
      type: z.literal("permission"),
      permission: z.object({ id: z.string().uuid(), requestId: z.literal("tool-turn"), kind: z.literal("execute"), detail: z.string(), options: z.array(z.object({ id: z.string(), decision: z.string(), label: z.string() })) })
    }).parse(events.find((event) => event.type === "permission"));
    expect(permission.permission.detail).toBe('{\n  "command": "uname -s"\n}');
    expect(JSON.stringify(permission)).not.toContain("provider-allow");
    const allowChoice = permission.permission.options.find((option) => option.decision === "allow_once");
    if (allowChoice === undefined) throw new Error("allow-once choice missing");
    child.stdin.write(`${JSON.stringify({ type: "permission_response", id: "tool-turn", permissionId: permission.permission.id, choiceId: allowChoice.id, decision: "allow_once" })}\n`);
    await until(() => events.some((event) => event.type === "complete"));
    expect(events).toContainEqual({ type: "permission_closed", id: "tool-turn", permissionId: permission.permission.id, reason: "decided" });
    expect(events.some((event) => event.type === "error")).toBe(false);
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 25_000);

  it.each(["codex", "claude", "opencode"] as const)("auto-selects the exact allow-once option for %s without emitting a prompt", async (provider) => {
    const events = await autoApproveAttempt(provider, { FAKE_ACP_EXPECT_ALLOW: "1" });
    expect(events.some((event) => event.type === "permission")).toBe(false);
    expect(events.some((event) => event.type === "permission_closed")).toBe(false);
    expect(events.some((event) => event.type === "complete")).toBe(true);
    expect(events.some((event) => event.type === "error")).toBe(false);
  }, 25_000);

  it.each([
    { name: "a request without allow-once", env: { FAKE_ACP_PERMISSION_NO_ALLOW: "1" } },
    { name: "an unreviewable request", env: { FAKE_ACP_PERMISSION_UNREVIEWABLE: "1" } }
  ])("fails closed without prompting for $name in auto-approve", async ({ env }) => {
    const events = await autoApproveAttempt("codex", env);
    expect(events.some((event) => event.type === "permission")).toBe(false);
    expect(events.some((event) => event.type === "permission_closed")).toBe(false);
    expect(events.find((event) => event.type === "error")).toMatchObject({
      code: "forbidden_tool_attempt",
      retryable: false
    });
    expect(events.some((event) => event.type === "complete")).toBe(false);
  }, 25_000);

  it("round-trips a deny decision and lets the harness answer without the tool", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-tool-deny-")); roots.push(state);
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env,
        FAKE_ACP_PERMISSION_ATTEMPT: "1",
        XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        QUICKCHAT_CLAUDE_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
        PATH: `${resolve("runtime/test/fixtures/claude-auth")}:${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"claude"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write('{"type":"submit","id":"deny-turn","question":"Do not run it","provider":"claude"}\n');
    await until(() => events.some((event) => event.type === "permission"));
    const permission = z.object({ type: z.literal("permission"), permission: z.object({ id: z.string().uuid(), options: z.array(z.object({ id: z.string(), decision: z.string() })) }) })
      .parse(events.find((event) => event.type === "permission"));
    const denyChoice = permission.permission.options.find((option) => option.decision === "reject_once");
    if (denyChoice === undefined) throw new Error("deny choice missing");
    child.stdin.write(`${JSON.stringify({ type: "permission_response", id: "deny-turn", permissionId: permission.permission.id, choiceId: denyChoice.id, decision: "reject_once" })}\n`);
    await until(() => events.some((event) => event.type === "complete"));
    expect(events).toContainEqual({ type: "permission_closed", id: "deny-turn", permissionId: permission.permission.id, reason: "decided" });
    expect(events.some((event) => event.type === "error")).toBe(false);
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 25_000);

  it("rejects OpenCode DSML tool syntax before it reaches streamed content or history", async () => {
    const events = await forbiddenAttempt("opencode", { FAKE_ACP_RAW_TOOL_MARKUP: "1" });
    expect(events.find((event) => event.type === "error")).toMatchObject({ code: "forbidden_tool_attempt", retryable: false });
    expect(events.some((event) => event.type === "complete")).toBe(false);
    expect(events.filter((event) => event.type === "content").map((event) => JSON.stringify(event)).join(""))
      .not.toContain("DSML");
  }, 20_000);

  it("never forwards provider stderr or exception details", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-errors-")); roots.push(state);
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env, FAKE_ACP_FAIL_SECRET: "1", XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"), PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write('{"type":"submit","id":"fail","question":"fail","provider":"codex"}\n');
    await until(() => events.some((event) => event.type === "error"));
    const error = events.find((event) => event.type === "error");
    expect(error?.message).toBe("The selected harness failed to answer");
    expect(JSON.stringify(error)).not.toContain("person@example.com");
    expect(JSON.stringify(error)).not.toContain("top-secret");
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 20_000);

  it("cooperatively cancels an active ACP turn without saving it", async () => {
    const state = await mkdtemp(join(tmpdir(), "quickchat-cancel-")); roots.push(state);
    const fake = resolve("runtime/test/fake-acp-agent.mjs");
    const chunkAudit = join(state, "chunk-audit.txt");
    const child = spawn(brokerExecutable(), [], {
      env: {
        ...process.env, FAKE_ACP_WAIT: "1", XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
        QUICKCHAT_CODEX_ACP: fake, QUICKCHAT_CLAUDE_ACP: fake,
        FAKE_ACP_STREAM_CHUNKS: JSON.stringify(["partial <"]), FAKE_ACP_CHUNK_AUDIT: chunkAudit,
        FAKE_ACP_LATE_AFTER_CANCEL: "1",
        PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const events: Record<string, unknown>[] = [];
    createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
    child.stdin.write('{"type":"initialize","protocolVersion":2,"harness":"codex"}\n');
    await until(() => events.some((event) => event.type === "ready"));
    child.stdin.write('{"type":"submit","id":"cancel-me","question":"wait","provider":"codex"}\n');
    await until(() => events.some((event) => event.type === "state" && event.state === "streaming"));
    await until(async () => await readFile(chunkAudit, "utf8").catch(() => "") === "chunks\n");
    child.stdin.write('{"type":"cancel","id":"cancel-me"}\n');
    await until(() => events.some((event) => event.type === "error" && event.code === "cancelled"));
    expect(events.some((event) => event.type === "complete")).toBe(false);
    const streamed = events.filter((event) => event.type === "content").map((event) => JSON.stringify(event)).join("");
    expect(streamed).not.toContain("<");
    expect(streamed).not.toContain("late ordinary text");
    child.stdin.end('{"type":"shutdown"}\n');
    await new Promise((resolveExit) => child.once("close", resolveExit));
  }, 25_000);
});

const readySchema = z.object({
  type: z.literal("ready"),
  protocolVersion: z.literal(2),
  features: z.tuple([z.literal("desktop-context"), z.literal("context-attachments")]),
  providers: z.array(z.object({
    id: z.string(),
    models: z.array(z.object({ id: z.string(), name: z.string() })),
    policy: z.object({
      tools: z.literal("device-approval"),
      web: z.enum(["approved-command", "search", "blocked"]),
      hostReads: z.boolean()
    })
  }))
});
const completeSchema = z.object({ type: z.literal("complete"), chat: z.object({ id: z.string().uuid(), answer: z.string() }) });

async function until(predicate: () => boolean | Promise<boolean>, timeout = 12_000): Promise<void> {
  const deadline = Date.now() + timeout;
  while (!await predicate()) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for broker event");
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 25));
  }
}

function parseObject(line: string): Record<string, unknown> {
  const raw: unknown = JSON.parse(line);
  return z.record(z.string(), z.unknown()).parse(raw);
}

function brokerExecutable(): string {
  return process.env.QUICKCHAT_TEST_BROKER ?? resolve("runtime/bin/quickchat-broker");
}

async function forbiddenAttempt(provider: "codex" | "opencode", extraEnv: NodeJS.ProcessEnv): Promise<Record<string, unknown>[]> {
  const state = await mkdtemp(join(tmpdir(), "quickchat-forbidden-tool-")); roots.push(state);
  const child = spawn(brokerExecutable(), [], {
    env: {
      ...process.env,
      ...extraEnv,
      XDG_STATE_HOME: join(state, "state"), XDG_CACHE_HOME: join(state, "cache"), XDG_RUNTIME_DIR: join(state, "run"),
      QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      QUICKCHAT_CLAUDE_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
    },
    stdio: ["pipe", "pipe", "pipe"]
  });
  const events: Record<string, unknown>[] = [];
  createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
  child.stdin.write(`${JSON.stringify({ type: "initialize", protocolVersion: 2, harness: provider })}\n`);
  await until(() => events.some((event) => event.type === "ready"));
  child.stdin.write(`${JSON.stringify({ type: "submit", id: "forbidden", question: "Run a device command", provider })}\n`);
  await until(() => events.some((event) => event.type === "error"));
  child.stdin.end('{"type":"shutdown"}\n');
  await new Promise((resolveExit) => child.once("close", resolveExit));
  return events;
}

async function autoApproveAttempt(
  provider: "codex" | "claude" | "opencode",
  extraEnv: NodeJS.ProcessEnv
): Promise<Record<string, unknown>[]> {
  const state = await mkdtemp(join(tmpdir(), "quickchat-auto-approve-")); roots.push(state);
  const child = spawn(brokerExecutable(), [], {
    env: {
      ...process.env,
      FAKE_ACP_PERMISSION_ATTEMPT: "1",
      ...extraEnv,
      XDG_STATE_HOME: join(state, "state"),
      XDG_CACHE_HOME: join(state, "cache"),
      XDG_RUNTIME_DIR: join(state, "run"),
      QUICKCHAT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      QUICKCHAT_CLAUDE_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      PATH: `${resolve("runtime/test/fixtures/claude-auth")}:${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
    },
    stdio: ["pipe", "pipe", "pipe"]
  });
  const events: Record<string, unknown>[] = [];
  createInterface({ input: child.stdout }).on("line", (line) => events.push(parseObject(line)));
  child.stdin.write(`${JSON.stringify({ type: "initialize", protocolVersion: 2, harness: provider })}\n`);
  await until(() => events.some((event) => event.type === "ready"));
  child.stdin.write(`${JSON.stringify({
    type: "submit", id: "auto-turn", question: "Run uname", provider,
    dangerousAutoApprove: true
  })}\n`);
  await until(() => events.some((event) => event.type === "complete" || event.type === "error"));
  child.stdin.end('{"type":"shutdown"}\n');
  await new Promise((resolveExit) => child.once("close", resolveExit));
  return events;
}

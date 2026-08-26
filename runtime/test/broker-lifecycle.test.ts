import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { deleteAcpSession } from "../src/acp.js";
import { OmaPilotBroker } from "../src/broker.js";
import * as piHarness from "../src/pi-harness.js";
import { HerdrHandoffError } from "../src/herdr.js";
import { HistoryStore } from "../src/history.js";
import { VoiceService } from "../src/tts.js";
import { ImageStore } from "../src/images.js";
import { omapilotPaths } from "../src/paths.js";
import type { DiscoveredProvider } from "../src/providers.js";
import type { BrokerEvent, ChatRecord, ProviderId } from "../src/types.js";

const roots: string[] = [];
afterEach(async () => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("broker lifecycle cleanup", () => {
  it("keeps local delete successful when provider session cleanup fails", async () => {
    const fixture = await setup();
    await fixture.history.save(record(1));
    const cleaned: string[] = [];
    const broker = new OmaPilotBroker(fixture.events.push.bind(fixture.events), {
      history: fixture.history, images: new ImageStore(fixture.paths), env: fixture.env,
      sessionCleaner: (_provider, sessionId) => { cleaned.push(sessionId); return Promise.reject(new Error("provider offline")); }
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "codex" });
    await broker.handle({ type: "history_delete", chatId: record(1).id });
    expect(await fixture.history.list()).toEqual([]);
    expect(cleaned).toEqual(["provider-session-1"]);
    expect(fixture.events.some((event) => event.type === "history" && event.history.length === 0)).toBe(true);
  });

  it("best-effort cleans every session after local clear", async () => {
    const fixture = await setup();
    await fixture.history.save(record(1));
    await fixture.history.save(record(2));
    const cleaned: string[] = [];
    const broker = new OmaPilotBroker(() => undefined, {
      history: fixture.history, images: new ImageStore(fixture.paths), env: fixture.env,
      sessionCleaner: (_provider, sessionId) => { cleaned.push(sessionId); return Promise.resolve(sessionId !== "provider-session-1"); }
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "codex" });
    await broker.handle({ type: "history_clear" });
    expect(await fixture.history.list()).toEqual([]);
    expect(cleaned.sort()).toEqual(["provider-session-1", "provider-session-2"]);
  });

  it("cleans the provider session evicted by the 30-chat cap", async () => {
    const fixture = await setup();
    for (let index = 0; index < 30; index += 1) await fixture.history.save(record(index));
    const cleaned: string[] = [];
    const broker = new OmaPilotBroker(fixture.events.push.bind(fixture.events), {
      history: fixture.history, images: new ImageStore(fixture.paths), env: fixture.env,
      sessionCleaner: (_provider, sessionId) => { cleaned.push(sessionId); return Promise.resolve(true); }
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "codex" });
    await broker.handle({ type: "submit", id: "evict", question: "Newest", provider: "codex" });
    expect((await fixture.history.list())).toHaveLength(30);
    expect(cleaned).toContain("provider-session-0");
  }, 20_000);

  it("uses OpenCode's native CLI when ACP cannot delete persisted sessions", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-opencode-delete-")); roots.push(root);
    const audit = join(root, "session-audit.txt");
    const agentEnvironment = { ...process.env, FAKE_ACP_NO_DELETE: "1", OPENCODE_SESSION_AUDIT: audit };
    const provider: DiscoveredProvider = {
      id: "opencode", name: "OpenCode", models: [], policy: { tools: "device-approval", web: "search", hostReads: false },
      harnessPath: resolve("runtime/test/fixtures/session-bin/opencode"),
      agent: { executable: resolve("runtime/test/fake-acp-agent.mjs"), args: [], env: agentEnvironment }
    };
    expect(await deleteAcpSession(provider, "provider-native-session")).toBe(true);
    expect(await readFile(audit, "utf8")).toBe("--pure session delete provider-native-session\n");
  });
});

describe("dictation generation guard", () => {
  it("publishes live levels only while recording", async () => {
    const events: BrokerEvent[] = [];
    let observer: { level: (level: number | null) => void } | undefined;
    const broker = new OmaPilotBroker(events.push.bind(events), {
      dictation: {
        start: (next) => { observer = next; return Promise.resolve(); },
        stop: () => Promise.resolve("measured transcript"),
        cancel: () => Promise.resolve()
      }
    });

    await broker.handle({ type: "dictation_start" });
    observer?.level(0.42);
    observer?.level(null);
    await broker.handle({ type: "dictation_stop" });
    observer?.level(0.9);

    expect(events).toEqual([
      { type: "dictation", state: "recording" },
      { type: "dictation_level", level: 0.42, metered: true },
      { type: "dictation_level", level: 0, metered: false },
      { type: "dictation", state: "transcribing" },
      { type: "dictation", state: "idle", text: "measured transcript" }
    ]);
  });

  it("discards a late stop result after cancellation", async () => {
    const events: BrokerEvent[] = [];
    let finishStop: (text: string) => void = () => undefined;
    const stopResult = new Promise<string>((resolveStop) => { finishStop = resolveStop; });
    const broker = new OmaPilotBroker(events.push.bind(events), {
      dictation: { start: () => Promise.resolve(), stop: () => stopResult, cancel: () => Promise.resolve() }
    });
    const stopping = broker.handle({ type: "dictation_stop" });
    await new Promise((resolveTurn) => setTimeout(resolveTurn, 0));
    await broker.handle({ type: "dictation_cancel" });
    finishStop("late transcript");
    await stopping;
    expect(events).toEqual([
      { type: "dictation", state: "transcribing" },
      { type: "dictation", state: "idle" }
    ]);
  });

  it("does not publish recording after stop overtakes startup", async () => {
    const events: BrokerEvent[] = [];
    let finishStart: () => void = () => undefined;
    const startResult = new Promise<void>((resolveStart) => { finishStart = resolveStart; });
    const broker = new OmaPilotBroker(events.push.bind(events), {
      dictation: {
        start: () => startResult,
        stop: () => Promise.resolve("quick transcript"),
        cancel: () => Promise.resolve()
      }
    });

    const starting = broker.handle({ type: "dictation_start" });
    await new Promise((resolveTurn) => setTimeout(resolveTurn, 0));
    const stopping = broker.handle({ type: "dictation_stop" });
    finishStart();
    await Promise.all([starting, stopping]);

    expect(events).toEqual([
      { type: "dictation", state: "transcribing" },
      { type: "dictation", state: "idle", text: "quick transcript" }
    ]);
  });
});

describe("custom provider registration", () => {
  it("acknowledges the durable write after credential cleanup", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-provider-save-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config }
    });

    await broker.handle({
      type: "custom_provider_add",
      id: "local-qwen",
      name: "Local Qwen",
      baseUrl: "http://127.0.0.1:8080/v1",
      api: "openai-responses",
      models: [{ id: "qwen3.8-27b" }]
    });

    expect(events.slice(0, 2)).toEqual([
      {
        type: "custom_provider_saved",
        provider: {
          id: "local-qwen",
          name: "Local Qwen",
          baseUrl: "http://127.0.0.1:8080/v1",
          api: "openai-responses",
          models: [{ id: "qwen3.8-27b", name: "qwen3.8-27b", contextWindow: 128_000 }],
          requiresAuth: false
        }
      },
      { type: "custom_providers", providers: [expect.objectContaining({ id: "local-qwen" })] }
    ]);
    expect(await readFile(join(config, "models.json"), "utf8")).toContain('"local-qwen"');
  });

  it("tests /models before saving and returns the discovered catalog", async () => {
    const events: BrokerEvent[] = [];
    vi.stubGlobal("fetch", vi.fn<typeof fetch>(() => Promise.resolve(new Response(JSON.stringify({
      data: [{ id: "qwen3.8-27b", max_model_len: 262_144 }]
    }), { status: 200 }))));
    const broker = new OmaPilotBroker(events.push.bind(events));

    await broker.handle({
      type: "custom_provider_test",
      baseUrl: "http://127.0.0.1:8080/v1"
    });

    expect(events).toEqual([{
      type: "custom_provider_tested",
      result: {
        baseUrl: "http://127.0.0.1:8080/v1",
        models: [{ id: "qwen3.8-27b", name: "qwen3.8-27b", contextWindow: 262_144 }]
      }
    }]);
  });

  it("preserves an existing server credential when a same-endpoint edit omits the unreadable key", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-provider-edit-auth-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    await mkdir(config, { recursive: true });
    await writeFile(join(config, "models.json"), JSON.stringify({ providers: { finn: {
      omapilotManaged: true, omapilotAuthRequired: true, name: "Finn",
      baseUrl: "http://finn.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen", name: "Qwen", api: "openai-completions", contextWindow: 128_000 }]
    } } }));
    await writeFile(join(config, "auth.json"), JSON.stringify({ finn: { type: "api_key", key: "stored-secret" } }));
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config }
    });

    await broker.handle({
      type: "custom_provider_add", id: "finn", name: "Finn updated",
      baseUrl: "http://finn.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen" }]
    });

    expect(events).toContainEqual(expect.objectContaining({
      type: "custom_provider_saved",
      provider: expect.objectContaining({ id: "finn", requiresAuth: true })
    }));
    expect(JSON.parse(await readFile(join(config, "auth.json"), "utf8"))).toMatchObject({
      finn: { type: "api_key", key: "stored-secret" }
    });
  });

  it("clears an existing server credential when an endpoint edit omits a replacement key", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-provider-edit-endpoint-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    await mkdir(config, { recursive: true });
    await writeFile(join(config, "models.json"), JSON.stringify({ providers: { finn: {
      omapilotManaged: true, omapilotAuthRequired: true, name: "Finn",
      baseUrl: "http://finn.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen", name: "Qwen", api: "openai-completions", contextWindow: 128_000 }]
    } } }));
    await writeFile(join(config, "auth.json"), JSON.stringify({ finn: { type: "api_key", key: "stored-secret" } }));
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config }
    });

    await broker.handle({
      type: "custom_provider_add", id: "finn", name: "Replacement",
      baseUrl: "http://replacement.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen" }]
    });

    expect(events).toContainEqual(expect.objectContaining({
      type: "custom_provider_saved",
      provider: expect.objectContaining({
        id: "finn", baseUrl: "http://replacement.ts.net:8888/v1", requiresAuth: false
      })
    }));
    const auth = JSON.parse(await readFile(join(config, "auth.json"), "utf8")) as Record<string, unknown>;
    expect(auth).not.toHaveProperty("finn");
  });

  it("restores both the provider definition and credential when endpoint auth cleanup fails", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-provider-edit-rollback-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    await mkdir(config, { recursive: true });
    const originalProvider = {
      omapilotManaged: true, omapilotAuthRequired: true, name: "Finn",
      baseUrl: "http://finn.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen", name: "Qwen", api: "openai-completions", contextWindow: 128_000 }]
    };
    await writeFile(join(config, "models.json"), JSON.stringify({ providers: { finn: originalProvider } }));
    await writeFile(join(config, "auth.json"), JSON.stringify({ finn: { type: "api_key", key: "stored-secret" } }));
    vi.spyOn(piHarness, "logoutPiProvider").mockRejectedValueOnce(new Error("auth store unavailable"));
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config }
    });

    await broker.handle({
      type: "custom_provider_add", id: "finn", name: "Replacement",
      baseUrl: "http://replacement.ts.net:8888/v1", api: "openai-completions",
      models: [{ id: "qwen" }]
    });

    expect(events).toEqual([expect.objectContaining({ type: "error", code: "custom_provider_auth_failed" })]);
    expect(JSON.parse(await readFile(join(config, "models.json"), "utf8")))
      .toMatchObject({ providers: { finn: originalProvider } });
    expect(JSON.parse(await readFile(join(config, "auth.json"), "utf8")))
      .toMatchObject({ finn: { type: "api_key", key: "stored-secret" } });
  });

  it("emits a rejection without a saved acknowledgement or config write", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-provider-reject-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config }
    });

    await broker.handle({
      type: "custom_provider_add",
      id: "Bad Server Id",
      name: "Bad Server",
      baseUrl: "https://example.com/v1",
      api: "openai-responses",
      models: [{ id: "qwen" }]
    });

    expect(events).toEqual([expect.objectContaining({
      type: "error",
      code: "invalid_custom_provider"
    })]);
    expect(events.some((event) => event.type === "custom_provider_saved")).toBe(false);
    await expect(readFile(join(config, "models.json"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
  });
});

describe("embedded built-in authentication", () => {
  it("round-trips a secret prompt without launching a terminal", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-broker-auth-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: {
        ...process.env,
        HOME: root,
        OMAPILOT_CONFIG_DIR: config,
        XDG_STATE_HOME: join(root, "state"),
        XDG_CACHE_HOME: join(root, "cache"),
        XDG_RUNTIME_DIR: join(root, "run")
      }
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "builtin" });
    const methods = events.find((event) => event.type === "auth_methods");
    expect(methods?.type === "auth_methods" ? methods.methods.map((method) => method.id) : []).toContain("openai::api_key");
    await broker.handle({ type: "auth_begin", methodId: "openai::api_key" });
    await vi.waitFor(() => expect(events.some((event) => event.type === "auth" && event.phase === "prompt")).toBe(true));
    const prompt = events.find((event) => event.type === "auth" && event.phase === "prompt");
    if (prompt?.type !== "auth" || prompt.phase !== "prompt") throw new Error("auth prompt missing");
    expect(prompt.prompt.kind).toBe("secret");
    await broker.handle({ type: "auth_response", flowId: prompt.flowId, promptId: prompt.prompt.id, value: "embedded-test-key" });
    await vi.waitFor(() => expect(events.some((event) => event.type === "auth" && event.phase === "complete")).toBe(true));
    expect(events.some((event) => event.type === "providers" && event.providers.some((provider) => provider.id === "builtin"))).toBe(true);
    expect(await readFile(join(config, "auth.json"), "utf8")).toContain("embedded-test-key");
    await broker.handle({ type: "shutdown" });
  });

  it("owns the Codex OAuth callback and never exposes manual callback input", async () => {
    vi.stubEnv("PI_OAUTH_CALLBACK_HOST", "127.0.0.2");
    const root = await mkdtemp(join(tmpdir(), "omapilot-broker-oauth-")); roots.push(root);
    const events: BrokerEvent[] = [];
    const broker = new OmaPilotBroker(events.push.bind(events), {
      env: {
        ...process.env,
        HOME: root,
        OMAPILOT_CONFIG_DIR: join(root, ".config/omapilot"),
        XDG_STATE_HOME: join(root, "state"),
        XDG_CACHE_HOME: join(root, "cache"),
        XDG_RUNTIME_DIR: join(root, "run")
      }
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "builtin" });
    await broker.handle({ type: "auth_begin", methodId: "openai-codex::oauth" });
    await vi.waitFor(() => expect(events.some((event) => event.type === "auth" && event.phase === "prompt")).toBe(true));
    const methodPrompt = events.find((event) => event.type === "auth" && event.phase === "prompt");
    if (methodPrompt?.type !== "auth" || methodPrompt.phase !== "prompt") throw new Error("login method prompt missing");
    expect(methodPrompt.prompt.kind).toBe("select");
    await broker.handle({
      type: "auth_response",
      flowId: methodPrompt.flowId,
      promptId: methodPrompt.prompt.id,
      value: "browser"
    });
    await vi.waitFor(() => expect(events.some((event) => event.type === "auth" && event.phase === "browser")).toBe(true));

    const callback = await fetch("http://127.0.0.2:1455/auth/callback?code=test&state=wrong");
    expect(callback.status).toBe(400);
    expect(events.filter((event) => event.type === "auth" && event.phase === "prompt")).toHaveLength(1);

    await broker.handle({ type: "auth_cancel", flowId: methodPrompt.flowId });
    await vi.waitFor(() => expect(events.some((event) => event.type === "auth" && event.phase === "cancelled")).toBe(true));
    await broker.handle({ type: "shutdown" });
  });
});

describe("tool permission lifecycle", () => {
  it("expires a pending permission with a nonce-bound closure before completing", async () => {
    const fixture = await setup();
    const broker = new OmaPilotBroker(fixture.events.push.bind(fixture.events), {
      history: fixture.history,
      images: new ImageStore(fixture.paths),
      env: { ...fixture.env, FAKE_ACP_PERMISSION_ATTEMPT: "1" },
      permissionTimeoutMs: 20
    });
    await broker.handle({ type: "initialize", protocolVersion: 2, harness: "codex" });
    await broker.handle({ type: "submit", id: "expires", question: "Run uname", provider: "codex" });
    const permission = fixture.events.find((event) => event.type === "permission");
    expect(permission?.type).toBe("permission");
    if (permission?.type !== "permission") throw new Error("permission event missing");
    expect(fixture.events).toContainEqual({
      type: "permission_closed",
      id: "expires",
      permissionId: permission.permission.id,
      reason: "expired"
    });
    expect(fixture.events.some((event) => event.type === "complete")).toBe(true);
  }, 20_000);
});

describe("Herdr handoff serialization", () => {
  it("coalesces concurrent clicks for the same chat into one handoff and one result", async () => {
    const fixture = await setup();
    const saved = record(7);
    await fixture.history.save(saved);
    const events: BrokerEvent[] = [];
    let finish: (value: { mode: "native"; reused: boolean }) => void = () => undefined;
    const result = new Promise<{ mode: "native"; reused: boolean }>((resolveResult) => { finish = resolveResult; });
    let handoffCount = 0;
    const broker = new OmaPilotBroker(events.push.bind(events), {
      history: fixture.history,
      images: new ImageStore(fixture.paths),
      env: fixture.env,
      herdrContinue: () => { handoffCount += 1; return result; }
    });
    const first = broker.handle({ type: "continue_in_herdr", chatId: saved.id });
    const second = broker.handle({ type: "continue_in_herdr", chatId: saved.id });
    await vi.waitFor(() => expect(handoffCount).toBe(1));
    finish({ mode: "native", reused: false });
    await Promise.all([first, second]);
    expect(events.filter((event) => event.type === "herdr" && event.state === "opening")).toHaveLength(1);
    expect(events.filter((event) => event.type === "herdr" && event.state === "continued")).toHaveLength(1);
  });

  it("coalesces failures and exposes only safe stage/error-code diagnostics", async () => {
    const fixture = await setup();
    const saved = record(8);
    await fixture.history.save(saved);
    const events: BrokerEvent[] = [];
    let fail: (error: Error) => void = () => undefined;
    const result = new Promise<{ mode: "native"; reused: boolean }>((_resolveResult, rejectResult) => { fail = rejectResult; });
    let handoffCount = 0;
    const broker = new OmaPilotBroker(events.push.bind(events), {
      history: fixture.history,
      images: new ImageStore(fixture.paths),
      env: fixture.env,
      herdrContinue: () => { handoffCount += 1; return result; }
    });
    const first = broker.handle({ type: "continue_in_herdr", chatId: saved.id });
    const second = broker.handle({ type: "continue_in_herdr", chatId: saved.id });
    await vi.waitFor(() => expect(handoffCount).toBe(1));
    fail(new HerdrHandoffError("focus", "window_not_focused"));
    await Promise.all([first, second]);
    expect(events.filter((event) => event.type === "herdr" && event.state === "failed")).toEqual([{
      type: "herdr",
      chatId: saved.id,
      state: "failed",
      stage: "focus",
      errorCode: "window_not_focused",
      message: "The session opened in Herdr, but OmaPilot could not focus it"
    }]);
  });
});

describe("voice provider status", () => {
  it("emits a voice catalog without secrets and acknowledges a tested key", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-voice-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    const events: BrokerEvent[] = [];
    const voice = new VoiceService(
      { HOME: root, OMAPILOT_CONFIG_DIR: config },
      {
        dictationAvailable: () => Promise.resolve(true),
        kokoroAvailable: () => Promise.resolve(false),
        fetch: () => Promise.resolve(new Response(JSON.stringify({ data: [] }), { status: 200 }))
      }
    );
    const broker = new OmaPilotBroker(events.push.bind(events), { voice, env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config } });
    await broker.handle({ type: "voice_status" });
    const status = events.find((event) => event.type === "voice");
    expect(status?.type === "voice" ? status.dictation.available : false).toBe(true);
    expect(status?.type === "voice" ? status.tts.map((provider) => provider.id) : []).toEqual(["kokoro", "elevenlabs", "openai"]);
    expect(JSON.stringify(status)).not.toContain("apiKey");
    await broker.handle({ type: "tts_key_test", provider: "openai", apiKey: "sk-openai-test-key" });
    expect(events.some((event) => event.type === "tts_tested" && event.provider === "openai" && event.result.available)).toBe(true);
  });

  it("speaks a stored ElevenLabs answer without leaking the key", async () => {
    const root = await mkdtemp(join(tmpdir(), "omapilot-voice-speak-")); roots.push(root);
    const config = join(root, ".config/omapilot");
    const events: BrokerEvent[] = [];
    const fetcher: typeof fetch = (input, init) => {
      if (String(init?.method ?? "GET").toUpperCase() === "POST") {
        return Promise.resolve(new Response(Buffer.from("ID3fake-mp3"), { status: 200 }));
      }
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      if (url.includes("/v1/models")) return Promise.resolve(new Response(JSON.stringify([]), { status: 200 }));
      return Promise.resolve(new Response(JSON.stringify({ voices: [] }), { status: 200 }));
    };
    const voice = new VoiceService(
      { HOME: root, OMAPILOT_CONFIG_DIR: config },
      {
        dictationAvailable: () => Promise.resolve(true),
        kokoroAvailable: () => Promise.resolve(false),
        fetch: fetcher,
        analyzeAudio: () => Promise.resolve([0.18, 0.72]),
        playAudio: (_path, _signal, telemetry) => {
          if (telemetry !== undefined) {
            telemetry.onStarted();
            for (const level of telemetry.levels) telemetry.onLevel(level);
          }
          return Promise.resolve();
        }
      }
    );
    const broker = new OmaPilotBroker(events.push.bind(events), { voice, env: { ...process.env, HOME: root, OMAPILOT_CONFIG_DIR: config } });
    await voice.setKey("elevenlabs", "eleven-test-key");
    await broker.handle({ type: "tts_speak", id: "speak-1", provider: "elevenlabs", text: "Hello **world**" });
    const deadline = Date.now() + 2_000;
    while (Date.now() < deadline && !events.some((event) => event.type === "tts_spoken" && event.id === "speak-1")) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    expect(events.some((event) => event.type === "tts_speaking"
      && event.id === "speak-1" && event.metered)).toBe(true);
    expect(events.filter((event) => event.type === "tts_level").map((event) => event.level))
      .toEqual([0.18, 0.72]);
    expect(events.some((event) => event.type === "tts_spoken" && event.id === "speak-1")).toBe(true);
    expect(JSON.stringify(events)).not.toContain("eleven-test-key");
  });
});

async function setup(): Promise<{
  paths: ReturnType<typeof omapilotPaths>;
  history: HistoryStore;
  events: BrokerEvent[];
  env: NodeJS.ProcessEnv;
}> {
  const root = await mkdtemp(join(tmpdir(), "omapilot-broker-lifecycle-"));
  roots.push(root);
  const paths = omapilotPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
  return {
    paths,
    history: new HistoryStore(paths),
    events: [],
    env: {
      ...process.env,
      XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run"),
      OMAPILOT_CODEX_ACP: resolve("runtime/test/fake-acp-agent.mjs"),
      PATH: `${resolve("runtime/test/fixtures/bin")}:${process.env.PATH ?? ""}`
    }
  };
}

function record(index: number, provider: ProviderId = "codex"): ChatRecord {
  const suffix = index.toString(16).padStart(12, "0");
  return {
    schemaVersion: 1,
    id: `10000000-0000-4000-8000-${suffix}`,
    createdAt: new Date(Date.UTC(2026, 7, 11, 0, 0, index)).toISOString(),
    title: `Chat ${String(index)}`,
    provider,
    question: "Question",
    answer: "Answer",
    images: [],
    session: { acpId: `provider-session-${String(index)}`, resumable: true, resumeKind: "native" }
  };
}

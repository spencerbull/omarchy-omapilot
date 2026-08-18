import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import type { AcpRun, PermissionDecision } from "./acp.js";
import { BrokerAcpError, deleteAcpSession, probeAcpModels, runAcpQuestion } from "./acp.js";
import { DictationService } from "./dictation.js";
import { promptWithContextAttachments } from "./context.js";
import { ContextAttachmentError, ContextAttachmentStore } from "./context-attachments.js";
import { HistoryStore, presentChat, presentImage } from "./history.js";
import { continueInHerdr, describeHerdrError } from "./herdr.js";
import { ImagePolicyError, ImageStore, isAllowedExternalLink } from "./images.js";
import { normalizeToolPermission, type PendingToolPermission } from "./permissions.js";
import { discoverProviders, fallbackModels, isPiProvider, type DiscoveredProvider } from "./providers.js";
import { launchDetached, resolveExecutable } from "./process.js";
import type { BrokerCommand, BrokerEvent, ChatRecord, ProviderId, ProviderInfo } from "./types.js";
import type { RequestPermissionRequest } from "@agentclientprotocol/sdk";
import type { AuthEvent, AuthPrompt } from "../../node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/auth/types.js";
import { BrowserCompanionServer, type BrowserCapture } from "./browser-companion.js";
import {
  browserCompanionSetupStatus,
  installBrowserCompanion,
  openBrowserCompanionSettings,
  uninstallBrowserCompanion,
  type BrowserFamily
} from "./browser-companion-setup.js";

type DictationClient = Pick<DictationService, "start" | "stop" | "cancel">;
type SessionCleaner = (provider: DiscoveredProvider, sessionId: string) => Promise<boolean>;
type HerdrContinue = typeof continueInHerdr;
type HerdrResult = Awaited<ReturnType<HerdrContinue>>;
type PermissionWaiter = PendingToolPermission & {
  resolve: (decision: PermissionDecision) => void;
  timeout: NodeJS.Timeout;
};
type AuthPromptWaiter = {
  id: string;
  resolve: (value: string) => void;
  reject: (error: Error) => void;
  cleanup: () => void;
};
type AuthFlow = {
  id: string;
  methodId: string;
  controller: AbortController;
  prompt?: AuthPromptWaiter;
};

export class QuickchatBroker {
  readonly #emit: (event: BrokerEvent) => void;
  readonly #history: HistoryStore;
  readonly #images: ImageStore;
  readonly #dictation: DictationClient;
  readonly #sessionCleaner: SessionCleaner;
  readonly #herdrContinue: HerdrContinue;
  readonly #env: NodeJS.ProcessEnv;
  readonly #permissionTimeoutMs: number;
  readonly #contextAttachments: ContextAttachmentStore;
  readonly #browserCompanion: BrowserCompanionServer;
  #providers = new Map<string, DiscoveredProvider>();
  #runs = new Map<string, AcpRun>();
  #handoffs = new Map<string, Promise<void>>();
  #permissions = new Map<string, PermissionWaiter>();
  #authFlow: AuthFlow | undefined;
  #submissions = new Set<string>();
  #dictationGeneration = 0;
  #browserCompanionSetupBusy = false;
  #browserCompanionSetupPhase: "installing" | "removing" | undefined;
  #browserCompanionStatusRevision = 0;

  constructor(
    emit: (event: BrokerEvent) => void,
    options: { history?: HistoryStore; images?: ImageStore; contextAttachments?: ContextAttachmentStore; dictation?: DictationClient; sessionCleaner?: SessionCleaner; herdrContinue?: HerdrContinue; env?: NodeJS.ProcessEnv; permissionTimeoutMs?: number } = {}
  ) {
    this.#emit = emit;
    this.#history = options.history ?? new HistoryStore();
    this.#images = options.images ?? new ImageStore();
    this.#contextAttachments = options.contextAttachments ?? new ContextAttachmentStore(this.#images, undefined, options.env ?? process.env);
    this.#browserCompanion = new BrowserCompanionServer(options.env ?? process.env, {
      capture: (capture) => this.#browserCapture(capture),
      cancelled: (requestId) => {
        this.#contextAttachments.cancel(requestId);
        this.#error("context_cancelled", "Browser element capture was cancelled", false, requestId);
      },
      error: (requestId, reason) => this.#browserCaptureError(requestId, reason),
      statusChanged: () => { void this.#emitBrowserCompanionStatus(); }
    });
    this.#dictation = options.dictation ?? new DictationService();
    this.#sessionCleaner = options.sessionCleaner ?? ((provider, sessionId) => isPiProvider(provider)
      ? Promise.resolve(true)
      : deleteAcpSession(provider, sessionId));
    this.#herdrContinue = options.herdrContinue ?? continueInHerdr;
    this.#env = options.env ?? process.env;
    this.#permissionTimeoutMs = options.permissionTimeoutMs ?? 60_000;
  }

  async handle(command: BrokerCommand): Promise<boolean> {
    switch (command.type) {
      case "initialize": await this.#initialize(command); break;
      case "submit": await this.#submit(command); break;
      case "context_begin": await this.#contextBegin(command); break;
      case "context_capture": await this.#contextCapture(command); break;
      case "context_cancel": this.#contextAttachments.cancel(command.id); this.#browserCompanion.cancel(command.id); break;
      case "context_discard": await this.#contextAttachments.discard(command.id); break;
      case "browser_companion_status": await this.#emitBrowserCompanionStatus(); break;
      case "browser_companion_install": await this.#installBrowserCompanion(); break;
      case "browser_companion_uninstall": await this.#uninstallBrowserCompanion(); break;
      case "browser_companion_open_settings": await this.#openBrowserCompanionSettings(command.family); break;
      case "auth_begin": this.#beginAuth(command.methodId); break;
      case "auth_response": this.#respondAuth(command); break;
      case "auth_cancel": this.#cancelAuth(command.flowId); break;
      case "cancel": await this.#cancel(command.id); break;
      case "permission_response": this.#respondPermission(command); break;
      case "history_list": await this.#emitHistory(); break;
      case "history_delete": {
        const deleted = await this.#history.delete(command.chatId);
        await this.#emitHistory();
        if (deleted !== undefined) await this.#cleanupSessions([deleted]);
        break;
      }
      case "history_clear": {
        const deleted = await this.#history.clear();
        await this.#emitHistory();
        await this.#cleanupSessions(deleted);
        break;
      }
      case "dictation_start": await this.#dictationStart(); break;
      case "dictation_stop": await this.#dictationStop(); break;
      case "dictation_cancel": await this.#dictationCancel(); break;
      case "continue_in_herdr": await this.#continue(command.chatId); break;
      case "load_image": await this.#loadImage(command.url, command.id); break;
      case "open_link": await this.#openLink(command.url); break;
      case "copy": await this.#copy(command.text); break;
      case "shutdown": {
        this.#cancelAuth(this.#authFlow?.id);
        await Promise.all([...this.#runs.values()].map((run) => run.cancel()));
        await this.#browserCompanion.close();
        return false;
      }
    }
    return true;
  }

  async #initialize(command: Extract<BrokerCommand, { type: "initialize" }>): Promise<void> {
    if (command.protocolVersion !== 2) {
      this.#error("unsupported_protocol", "Quickchat supports broker protocol version 2", false);
      return;
    }
    const [discovered, authMethods] = await Promise.all([
      discoverProviders(this.#env, command.harness),
      command.harness === "builtin"
        ? import("./pi-harness.js").then(({ discoverPiAuthMethods }) => discoverPiAuthMethods(this.#env)).catch(() => [])
        : Promise.resolve([])
    ]);
    await this.#browserCompanion.start().catch(() => undefined);
    await this.#emitBrowserCompanionStatus();
    await Promise.all(discovered.map(async (provider) => {
      if (isPiProvider(provider)) return;
      const acpModels = await probeAcpModels(provider);
      const models = acpModels.models.length > 0 ? acpModels.models : await fallbackModels(provider);
      provider.models = models;
      if (acpModels.defaultModel !== undefined) provider.defaultModel = acpModels.defaultModel;
    }));
    this.#providers = new Map(discovered.map((provider) => [provider.id, provider]));
    const history = (await this.#history.list()).map((chat) => presentChat(chat));
    this.#emit({ type: "ready", protocolVersion: 2, features: ["desktop-context", "context-attachments"], providers: discovered.map(publicProvider), history });
    if (command.harness === "builtin") this.#emit({ type: "auth_methods", methods: authMethods });
  }

  #beginAuth(methodId: string): void {
    if (this.#authFlow !== undefined) this.#cancelAuth(this.#authFlow.id);
    const flow: AuthFlow = { id: randomUUID(), methodId, controller: new AbortController() };
    this.#authFlow = flow;
    this.#emit({ type: "auth", phase: "starting", flowId: flow.id, methodId, message: "Starting secure authentication…" });
    void this.#runAuth(flow);
  }

  async #runAuth(flow: AuthFlow): Promise<void> {
    try {
      const { discoverPiAuthMethods, loginPiProvider } = await import("./pi-harness.js");
      await loginPiProvider(this.#env, flow.methodId, {
        signal: flow.controller.signal,
        prompt: (prompt) => this.#promptAuth(flow, prompt),
        notify: (event) => this.#notifyAuth(flow, event)
      });
      if (flow.controller.signal.aborted || this.#authFlow?.id !== flow.id) return;
      const discovered = await discoverProviders(this.#env, "builtin");
      this.#providers = new Map(discovered.map((provider) => [provider.id, provider]));
      this.#emit({ type: "providers", providers: discovered.map(publicProvider) });
      this.#emit({ type: "auth_methods", methods: await discoverPiAuthMethods(this.#env) });
      this.#emit({ type: "auth", phase: "complete", flowId: flow.id, methodId: flow.methodId, message: "Authentication complete. OmaPilot is ready." });
    } catch (error) {
      if (flow.controller.signal.aborted) {
        this.#emit({ type: "auth", phase: "cancelled", flowId: flow.id, methodId: flow.methodId, message: "Authentication cancelled." });
      } else {
        this.#emit({ type: "auth", phase: "error", flowId: flow.id, methodId: flow.methodId,
          message: error instanceof Error && error.message === "Authentication prompt was cancelled"
            ? error.message : "Authentication could not be completed. Check the details and try again." });
      }
    } finally {
      flow.prompt?.cleanup();
      if (this.#authFlow?.id === flow.id) this.#authFlow = undefined;
    }
  }

  #promptAuth(flow: AuthFlow, prompt: AuthPrompt): Promise<string> {
    if (flow.controller.signal.aborted || this.#authFlow?.id !== flow.id)
      return Promise.reject(new Error("Authentication prompt was cancelled"));
    flow.prompt?.reject(new Error("Authentication prompt was cancelled"));
    return new Promise<string>((resolve, reject) => {
      const promptId = randomUUID();
      const signals = [flow.controller.signal, prompt.signal].filter((signal): signal is AbortSignal => signal !== undefined);
      const signal = signals.length === 1 ? (signals[0] ?? flow.controller.signal) : AbortSignal.any(signals);
      const onAbort = (): void => reject(new Error("Authentication prompt was cancelled"));
      const cleanup = (): void => signal.removeEventListener("abort", onAbort);
      flow.prompt = {
        id: promptId,
        resolve: (value) => { cleanup(); resolve(value); },
        reject: (error) => { cleanup(); reject(error); },
        cleanup
      };
      signal.addEventListener("abort", onAbort, { once: true });
      // Browser OAuth providers already start a broker-owned localhost callback
      // listener before issuing this compatibility fallback. Keep the promise
      // alive for cancellation, but do not ask users to paste callback URLs.
      if (prompt.type === "manual_code") return;
      this.#emit({
        type: "auth", phase: "prompt", flowId: flow.id, methodId: flow.methodId,
        prompt: {
          id: promptId,
          kind: prompt.type,
          message: prompt.message,
          ...("placeholder" in prompt && prompt.placeholder !== undefined ? { placeholder: prompt.placeholder } : {}),
          ...(prompt.type === "select" ? { options: prompt.options.map((option) => ({ ...option })) } : {})
        }
      });
    });
  }

  #notifyAuth(flow: AuthFlow, event: AuthEvent): void {
    if (this.#authFlow?.id !== flow.id || flow.controller.signal.aborted) return;
    if (event.type === "auth_url") {
      if (!isAllowedExternalLink(event.url)) return;
      this.#emit({ type: "auth", phase: "browser", flowId: flow.id, methodId: flow.methodId,
        url: event.url, ...(event.instructions === undefined ? {} : { instructions: event.instructions }) });
      return;
    }
    if (event.type === "device_code") {
      if (!isAllowedExternalLink(event.verificationUri)) return;
      this.#emit({ type: "auth", phase: "device_code", flowId: flow.id, methodId: flow.methodId,
        userCode: event.userCode, verificationUri: event.verificationUri,
        ...(event.expiresInSeconds === undefined ? {} : { expiresInSeconds: event.expiresInSeconds }) });
      return;
    }
    const links = event.type === "info" ? event.links?.filter((link) => isAllowedExternalLink(link.url)).map((link) => ({ ...link })) : undefined;
    this.#emit({ type: "auth", phase: "info", flowId: flow.id, methodId: flow.methodId,
      message: event.message, ...(links === undefined ? {} : { links }) });
  }

  #respondAuth(command: Extract<BrokerCommand, { type: "auth_response" }>): void {
    const flow = this.#authFlow;
    if (flow?.id !== command.flowId || flow.prompt?.id !== command.promptId) return;
    const prompt = flow.prompt;
    delete flow.prompt;
    prompt.resolve(command.value);
  }

  #cancelAuth(flowId: string | undefined): void {
    const flow = this.#authFlow;
    if (flow === undefined || flowId === undefined || flow.id !== flowId) return;
    this.#authFlow = undefined;
    flow.controller.abort();
    flow.prompt?.reject(new Error("Authentication prompt was cancelled"));
  }

  async #submit(command: Extract<BrokerCommand, { type: "submit" }>): Promise<void> {
    if (this.#submissions.has(command.id)) { this.#error("duplicate_id", "This request is already running", false, command.id); return; }
    this.#submissions.add(command.id);
    try {
      await this.#submitOnce(command);
    } finally {
      this.#submissions.delete(command.id);
    }
  }

  async #submitOnce(command: Extract<BrokerCommand, { type: "submit" }>): Promise<void> {
    const provider = this.#providers.get(command.provider);
    if (provider === undefined) {
      await this.#contextAttachments.discardMany((command.contextAttachments ?? []).map((value) => value.id));
      this.#error("provider_unavailable", "The selected harness is not installed and authenticated", false, command.id);
      return;
    }
    const dangerousAutoApprove = command.dangerousAutoApprove === true
      && provider.policy.tools === "device-approval";
    this.#emit({ type: "state", id: command.id, state: "preparing", message: `Preparing ${provider.name}…` });
    let selectedAttachmentIds: string[] = [];
    let attachmentBlocks: Awaited<ReturnType<ContextAttachmentStore["resolve"]>>["blocks"] = [];
    try {
      const resolved = await this.#contextAttachments.resolve(command.contextAttachments ?? []);
      attachmentBlocks = resolved.blocks;
      selectedAttachmentIds = resolved.attachmentIds;
    } catch (error) {
      if (error instanceof ContextAttachmentError) {
        await this.#contextAttachments.discardMany((command.contextAttachments ?? []).map((value) => value.id));
        this.#error(error.code, error.message, false, command.id);
        return;
      }
      throw error;
    }
    const permission = (request: RequestPermissionRequest) => this.#requestToolPermission(
      command.id, provider.id, request, dangerousAutoApprove);
    const prompt = promptWithContextAttachments(command.question, command.desktopContext, attachmentBlocks);
    const run = isPiProvider(provider)
      ? (await import("./pi-harness.js")).runPiQuestion(
        provider, command.id, prompt, command.model, this.#emit, 180_000, permission,
        () => this.#cancelPermissions(command.id))
      : runAcpQuestion(provider, command.id, prompt, command.model,
        this.#emit, 180_000, this.#images, permission,
        () => this.#cancelPermissions(command.id));
    this.#runs.set(command.id, run);
    this.#emit({ type: "state", id: command.id, state: "streaming", message: `Waiting for ${provider.name}…` });
    try {
      const result = await run.result;
      const selectedModel = result.defaultModel ?? command.model;
      if (result.models.length > 0) {
        provider.models = result.models;
        if (result.defaultModel !== undefined) provider.defaultModel = result.defaultModel;
        this.#emit({ type: "providers", providers: [...this.#providers.values()].map(publicProvider) });
      }
      const chat: ChatRecord = {
        schemaVersion: 1,
        id: randomUUID(),
        createdAt: new Date().toISOString(),
        title: command.question.replaceAll(/\s+/g, " ").slice(0, 80),
        provider: provider.id,
        ...(selectedModel === undefined ? {} : { model: selectedModel }),
        question: command.question,
        answer: result.answer,
        images: result.images,
        session: {
          acpId: result.sessionId,
          ...(this.#env.HOME === undefined ? {} : { cwd: this.#env.HOME }),
          resumable: result.resumable,
          resumeKind: result.resumable ? "native" : "transcript"
        }
      };
      const evicted = await this.#history.save(chat);
      await this.#cleanupSessions(evicted);
      this.#emit({ type: "complete", chat: presentChat(chat) });
      this.#emit({ type: "state", id: command.id, state: "idle" });
    } catch (error) {
      if (error instanceof BrokerAcpError || isBrokerRunError(error)) this.#error(error.code, error.message, error.retryable, command.id);
      else this.#error("agent_failed", "The selected harness stopped unexpectedly", true, command.id);
    } finally {
      this.#cancelPermissions(command.id);
      this.#runs.delete(command.id);
      await this.#contextAttachments.discardMany(selectedAttachmentIds);
    }
  }

  async #contextBegin(command: Extract<BrokerCommand, { type: "context_begin" }>): Promise<void> {
    try {
      const target = await this.#contextAttachments.begin(command.id, command.target);
      this.#emit({ type: "context_ready", id: command.id, target });
    } catch (error) {
      this.#contextError(error, command.id);
    }
  }

  async #browserCapture(capture: BrowserCapture): Promise<void> {
    try {
      const attachment = await this.#contextAttachments.captureBrowser(capture.requestId, capture);
      this.#emit({ type: "context_attachment", requestId: capture.requestId, attachment });
    } catch (error) {
      this.#contextError(error, capture.requestId);
    }
  }

  #browserCaptureError(requestId: string, reason: string): void {
    this.#contextAttachments.cancel(requestId);
    this.#error("context_browser_failed", reason, true, requestId);
  }

  async #contextCapture(command: Extract<BrokerCommand, { type: "context_capture" }>): Promise<void> {
    try {
      if (command.mode === "window" && command.anchor !== undefined) {
        const target = await this.#contextAttachments.selectWindow(command.id, command.anchor);
        const browser = await this.#browserCompanion.tryArm(command.id, target.appId, target.title);
        if (browser.status === "armed") {
          this.#emit({
            type: "context_picker", id: command.id, browser: browser.browser,
            title: browser.title, url: browser.url
          });
          return;
        }
        if (browser.status === "permission-required") this.#emit({
          type: "context_notice", id: command.id,
          message: "DOM capture is not enabled for this site; using OCR and screenshot"
        });
        else if (browser.status === "unavailable") this.#emit({
          type: "context_notice", id: command.id,
          message: "Browser companion is not connected; using OCR and screenshot. Enable it in OmaPilot settings."
        });
      }
      const attachment = await this.#contextAttachments.capture(command.id, command.mode, command.region, command.anchor);
      this.#emit({ type: "context_attachment", requestId: command.id, attachment });
    } catch (error) {
      this.#contextError(error, command.id);
    }
  }

  async #emitBrowserCompanionStatus(
    phase?: "ready" | "installing" | "removing" | "failed",
    message?: string
  ): Promise<void> {
    const revision = ++this.#browserCompanionStatusRevision;
    const setup = await browserCompanionSetupStatus(this.#env);
    if (revision !== this.#browserCompanionStatusRevision) return;
    const connected = this.#browserCompanion.status();
    this.#emit({ type: "browser_companion", phase: phase ?? this.#browserCompanionSetupPhase ?? "ready", ...setup, ...connected,
      ...(message === undefined ? {} : { message }) });
  }

  async #installBrowserCompanion(): Promise<void> {
    if (this.#browserCompanionSetupBusy) return;
    this.#browserCompanionSetupBusy = true;
    this.#browserCompanionSetupPhase = "installing";
    try {
      await this.#emitBrowserCompanionStatus();
      const installed = await installBrowserCompanion(this.#env);
      await this.#emitBrowserCompanionStatus(installed ? "ready" : "failed", installed
        ? "Browser companion installed. Restart your browser, then enable access from its OmaPilot extension icon."
        : "Browser companion setup failed. Check that Node.js and jq are installed, then try again.");
    } catch {
      await this.#emitBrowserCompanionStatus("failed", "Browser companion setup could not finish. Retry from Settings; no terminal setup is required.");
    } finally {
      this.#browserCompanionSetupBusy = false;
      this.#browserCompanionSetupPhase = undefined;
    }
  }

  async #uninstallBrowserCompanion(): Promise<void> {
    if (this.#browserCompanionSetupBusy) return;
    this.#browserCompanionSetupBusy = true;
    this.#browserCompanionSetupPhase = "removing";
    try {
      await this.#emitBrowserCompanionStatus();
      const removed = await uninstallBrowserCompanion(this.#env);
      if (removed) this.#browserCompanion.disconnect();
      await this.#emitBrowserCompanionStatus(removed ? "ready" : "failed", removed
        ? "Browser context removed. Restart open browsers to unload the extension."
        : "Browser context removal could not finish. Retry from Settings before removing OmaPilot.");
    } catch {
      await this.#emitBrowserCompanionStatus("failed", "Browser context removal could not finish. Retry from Settings before removing OmaPilot.");
    } finally {
      this.#browserCompanionSetupBusy = false;
      this.#browserCompanionSetupPhase = undefined;
    }
  }

  async #openBrowserCompanionSettings(family: BrowserFamily): Promise<void> {
    const opened = await openBrowserCompanionSettings(family, this.#env);
    await this.#emitBrowserCompanionStatus(undefined, opened
      ? `${family === "firefox" ? "Firefox" : "Chromium"} extension settings opened.`
      : `No supported ${family === "firefox" ? "Firefox" : "Chromium"} browser was found.`);
  }

  #contextError(error: unknown, id: string): void {
    if (error instanceof ContextAttachmentError || error instanceof ImagePolicyError) {
      this.#error(error.code, error.message, false, id);
      return;
    }
    this.#error("context_capture_failed", "The selected context could not be captured", true, id);
  }

  async #requestToolPermission(
    requestId: string,
    provider: ProviderId,
    request: RequestPermissionRequest,
    dangerousAutoApprove: boolean
  ): Promise<PermissionDecision> {
    const permissionId = randomUUID();
    const pending = normalizeToolPermission(requestId, permissionId, provider, request);
    if (pending === undefined) return { invalid: true };
    if (dangerousAutoApprove) {
      const choice = pending.view.options.find((option) => option.decision === "allow_once");
      const optionId = choice === undefined ? undefined : pending.optionIds[choice.id];
      return optionId === undefined ? { invalid: true } : { optionId };
    }
    return new Promise<PermissionDecision>((resolvePermission) => {
      const timeout = setTimeout(() => {
        this.#permissions.delete(permissionId);
        this.#emit({ type: "permission_closed", id: requestId, permissionId, reason: "expired" });
        resolvePermission({});
      }, this.#permissionTimeoutMs);
      timeout.unref();
      this.#permissions.set(permissionId, { ...pending, resolve: resolvePermission, timeout });
      this.#emit({ type: "permission", permission: pending.view });
    });
  }

  #respondPermission(command: Extract<BrokerCommand, { type: "permission_response" }>): void {
    const pending = this.#permissions.get(command.permissionId);
    if (pending === undefined || pending.view.requestId !== command.id) return;
    this.#permissions.delete(command.permissionId);
    clearTimeout(pending.timeout);
    this.#emit({ type: "permission_closed", id: command.id, permissionId: command.permissionId, reason: "decided" });
    const choice = pending.view.options.find((option) => option.id === command.choiceId && option.decision === command.decision);
    const optionId = choice === undefined ? undefined : pending.optionIds[choice.id];
    pending.resolve(optionId === undefined ? {} : { optionId });
  }

  #cancelPermissions(requestId: string): void {
    for (const [permissionId, pending] of this.#permissions) {
      if (pending.view.requestId !== requestId) continue;
      this.#permissions.delete(permissionId);
      clearTimeout(pending.timeout);
      this.#emit({ type: "permission_closed", id: requestId, permissionId, reason: "cancelled" });
      pending.resolve({});
    }
  }

  async #cancel(id: string): Promise<void> {
    const run = this.#runs.get(id);
    if (run === undefined) return;
    this.#emit({ type: "state", id, state: "stopping" });
    await run.cancel();
  }

  async #emitHistory(): Promise<void> {
    this.#emit({ type: "history", history: (await this.#history.list()).map((chat) => presentChat(chat)) });
  }

  async #dictationStart(): Promise<void> {
    const generation = ++this.#dictationGeneration;
    try {
      await this.#dictation.start();
      if (generation === this.#dictationGeneration) this.#emit({ type: "dictation", state: "recording" });
    } catch {
      if (generation === this.#dictationGeneration) this.#emit({ type: "dictation", state: "unavailable", message: "Voxtype is unavailable or not ready" });
    }
  }

  async #dictationStop(): Promise<void> {
    const generation = this.#dictationGeneration;
    this.#emit({ type: "dictation", state: "transcribing" });
    try {
      const text = await this.#dictation.stop();
      if (generation === this.#dictationGeneration) this.#emit({ type: "dictation", state: "idle", text });
    } catch {
      if (generation === this.#dictationGeneration) this.#emit({ type: "dictation", state: "unavailable", message: "Voxtype could not finish transcription" });
    }
  }

  async #dictationCancel(): Promise<void> {
    this.#dictationGeneration += 1;
    await this.#dictation.cancel();
    this.#emit({ type: "dictation", state: "idle" });
  }

  async #continue(chatId: string): Promise<void> {
    const existing = this.#handoffs.get(chatId);
    if (existing !== undefined) { await existing; return; }
    const flight = this.#runContinue(chatId);
    this.#handoffs.set(chatId, flight);
    try {
      await flight;
    } finally {
      if (this.#handoffs.get(chatId) === flight) this.#handoffs.delete(chatId);
    }
  }

  async #runContinue(chatId: string): Promise<void> {
    const chat = await this.#history.get(chatId);
    if (chat === undefined) { this.#emit({ type: "herdr", chatId, state: "failed", message: "Saved chat was not found" }); return; }
    this.#emit({ type: "herdr", chatId, state: "opening" });
    try {
      const result: HerdrResult = await this.#herdrContinue(chat, this.#env);
      this.#emit({ type: "herdr", chatId, state: "continued", mode: result.mode });
    } catch (error) {
      const failure = describeHerdrError(error);
      this.#emit({ type: "herdr", chatId, ...failure });
    }
  }

  async #loadImage(url: string, id?: string): Promise<void> {
    try { const image = await this.#images.fetchRemote(url); this.#emit({ type: "image", id: id ?? url, image: presentImage(image) }); }
    catch (error) { this.#error(error instanceof ImagePolicyError ? error.code : "image_fetch", error instanceof Error ? error.message : "Image fetch failed", false); }
  }

  async #openLink(url: string): Promise<void> {
    if (!isAllowedExternalLink(url)) { this.#emit({ type: "link", url, opened: false }); return; }
    const opener = await resolveExecutable("xdg-open", this.#env);
    if (opener === undefined) { this.#emit({ type: "link", url, opened: false }); return; }
    this.#emit({ type: "link", url, opened: await launchDetached(opener, [url], { env: this.#env }) });
  }

  async #copy(text: string): Promise<void> {
    const copy = await resolveExecutable("wl-copy", this.#env);
    if (copy === undefined) { this.#emit({ type: "copied", copied: false }); return; }
    const copied = await new Promise<boolean>((resolveCopy) => {
      const child = spawn(copy, [], { env: this.#env, stdio: ["pipe", "ignore", "ignore"] });
      child.stdin.end(text);
      child.once("error", () => resolveCopy(false));
      child.once("close", (code) => resolveCopy(code === 0));
    });
    this.#emit({ type: "copied", copied });
  }

  #error(code: string, message: string, retryable: boolean, id?: string): void {
    this.#emit({ type: "error", code, message, retryable, ...(id === undefined ? {} : { id }) });
  }

  async #cleanupSessions(chats: ChatRecord[]): Promise<void> {
    await Promise.allSettled(chats.map(async (chat) => {
      const sessionId = chat.session.acpId;
      const provider = this.#providers.get(chat.provider);
      if (sessionId !== undefined && provider !== undefined) await this.#sessionCleaner(provider, sessionId);
    }));
  }
}

function publicProvider(provider: DiscoveredProvider): ProviderInfo {
  return {
    id: provider.id,
    name: provider.name,
    models: provider.models,
    policy: provider.policy,
    ...(provider.version === undefined ? {} : { version: provider.version }),
    ...(provider.defaultModel === undefined ? {} : { defaultModel: provider.defaultModel })
  };
}

function isBrokerRunError(error: unknown): error is Error & { code: string; retryable: boolean } {
  return error instanceof Error
    && typeof (error as { code?: unknown }).code === "string"
    && typeof (error as { retryable?: unknown }).retryable === "boolean";
}

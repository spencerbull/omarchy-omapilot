import { z } from "zod";
import type { TtsProviderStatus, VoiceStatus } from "./tts.js";
import type { CapabilityRisk, CapabilityView } from "./capabilities/types.js";

export const providerIdSchema = z.enum(["builtin", "codex", "opencode"]);
export type ProviderId = z.infer<typeof providerIdSchema>;
export const harnessIdSchema = providerIdSchema;
export type HarnessId = z.infer<typeof harnessIdSchema>;
export const webHandoffProviderSchema = z.enum(["duckduckgo", "google", "chatgpt", "claude", "grok"]);
export type WebHandoffProvider = z.infer<typeof webHandoffProviderSchema>;

const contextText = (max: number) => z.string().min(1).max(max).refine(
  (value) => !/[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/.test(value),
  "desktop context contains control characters"
);
const desktopWindowSchema = z.object({
  appId: contextText(160).optional(),
  title: contextText(240).optional(),
  workspace: z.number().int().min(-100_000).max(100_000).optional(),
  monitor: contextText(120).optional()
}).strict().refine((value) => Object.keys(value).length > 0, "desktop window is empty");
const desktopAppSchema = z.object({
  appId: contextText(160),
  workspaces: z.array(z.number().int().min(-100_000).max(100_000)).max(12),
  windowCount: z.number().int().min(1).max(64)
}).strict();
const desktopMediaSchema = z.object({
  player: contextText(160).optional(),
  title: contextText(240).optional(),
  artist: contextText(200).optional(),
  status: z.enum(["playing", "paused", "stopped"]).optional()
}).strict().refine((value) => Object.keys(value).length > 0, "desktop media is empty");
export const desktopContextSchema = z.object({
  version: z.literal(1),
  activeWindow: desktopWindowSchema.optional(),
  activeWorkspace: z.number().int().min(-100_000).max(100_000).optional(),
  focusedMonitor: contextText(120).optional(),
  apps: z.array(desktopAppSchema).max(12),
  workspaces: z.array(z.number().int().min(-100_000).max(100_000)).max(12),
  media: z.array(desktopMediaSchema).max(4)
}).strict().refine(
  (value) => value.activeWindow !== undefined || value.activeWorkspace !== undefined || value.focusedMonitor !== undefined
    || value.apps.length > 0 || value.workspaces.length > 0 || value.media.length > 0,
  "desktop context is empty"
);
export type DesktopContext = z.infer<typeof desktopContextSchema>;

const captureRectangleSchema = z.object({
  x: z.number().int().min(-100_000).max(100_000),
  y: z.number().int().min(-100_000).max(100_000),
  width: z.number().int().min(1).max(12_000),
  height: z.number().int().min(1).max(12_000)
}).strict().refine((value) => value.width * value.height <= 16_000_000, "capture rectangle is too large");
const captureTargetHintSchema = z.object({
  appId: contextText(160).optional(),
  title: contextText(240).optional(),
  bounds: captureRectangleSchema.optional()
}).strict().refine((value) => Object.keys(value).length > 0, "capture target hint is empty");
const contextAttachmentSelectionSchema = z.object({
  id: z.string().uuid(),
  representationIds: z.array(z.enum(["text", "element", "image"])).min(1).max(2)
    .refine((values) => new Set(values).size === values.length, "context representations must be unique")
}).strict();
export type ContextAttachmentSelection = z.infer<typeof contextAttachmentSelectionSchema>;

const initializeCommand = z.object({
  type: z.literal("initialize"),
  protocolVersion: z.number().int().positive(),
  harness: harnessIdSchema,
  client: z.string().max(120).optional()
}).strict();
const submitCommand = z.object({
  type: z.literal("submit"),
  id: z.string().min(1).max(120),
  question: z.string().trim().min(1).max(100_000),
  provider: providerIdSchema,
  resumeChatId: z.string().uuid().optional(),
  model: z.preprocess((value) => typeof value === "string" && value.trim() === "" ? undefined : value, z.string().min(1).max(500).optional()),
  desktopContext: desktopContextSchema.optional(),
  contextAttachments: z.array(contextAttachmentSelectionSchema).max(4).optional(),
  webHandoffProvider: webHandoffProviderSchema.optional(),
  dangerousAutoApprove: z.boolean().optional()
});
const contextBeginCommand = z.object({
  type: z.literal("context_begin"),
  id: z.string().min(1).max(120),
  target: captureTargetHintSchema.optional()
}).strict();
const contextCaptureCommand = z.object({
  type: z.literal("context_capture"),
  id: z.string().min(1).max(120),
  mode: z.enum(["window", "region"]),
  region: captureRectangleSchema.optional(),
  anchor: z.object({
    x: z.number().int().min(-100_000).max(100_000),
    y: z.number().int().min(-100_000).max(100_000)
  }).strict().optional()
}).strict().refine((value) => value.mode === "window" || value.region !== undefined, "region capture requires geometry");
const contextDiscardCommand = z.object({ type: z.literal("context_discard"), id: z.string().uuid() }).strict();
const contextCancelCommand = z.object({ type: z.literal("context_cancel"), id: z.string().min(1).max(120) }).strict();
const browserCompanionCommand = z.object({
  type: z.enum(["browser_companion_status", "browser_companion_install", "browser_companion_uninstall"])
}).strict();
const browserCompanionOpenSettingsCommand = z.object({
  type: z.literal("browser_companion_open_settings"),
  family: z.enum(["chromium", "firefox"])
}).strict();
const capabilityIdSchema = z.enum(["email", "calendar", "files", "projects", "messages", "meetings"]);
const capabilitySetEnabledCommand = z.object({
  type: z.literal("capability_set_enabled"),
  id: capabilityIdSchema,
  enabled: z.boolean()
}).strict();
const capabilityFilesRootSetCommand = z.object({
  type: z.literal("capability_files_root_set"),
  path: z.string().max(4_096)
}).strict();
const authBeginCommand = z.object({
  type: z.literal("auth_begin"),
  methodId: z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}::(?:api_key|oauth)$/u)
}).strict();
const authResponseCommand = z.object({
  type: z.literal("auth_response"),
  flowId: z.string().uuid(),
  promptId: z.string().uuid(),
  value: z.string().max(32_768)
}).strict();
const authCancelCommand = z.object({ type: z.literal("auth_cancel"), flowId: z.string().uuid() }).strict();
const cancelCommand = z.object({ type: z.literal("cancel"), id: z.string().min(1).max(120) });
const permissionResponseCommand = z.object({
  type: z.literal("permission_response"),
  id: z.string().min(1).max(120),
  permissionId: z.string().uuid(),
  choiceId: z.string().regex(/^option-[0-9]{1,3}$/u),
  decision: z.enum(["allow_once", "allow_session", "allow_always", "reject_once", "reject_always"])
});
const chatCommand = z.object({ type: z.enum(["continue_in_herdr", "history_delete"]), chatId: z.string().uuid() });
const linkCommand = z.object({ type: z.literal("open_link"), url: z.string().max(8_192) });
const imageCommand = z.object({ type: z.literal("load_image"), id: z.string().min(1).max(200).optional(), url: z.string().max(8_192) });
const copyCommand = z.object({ type: z.literal("copy"), text: z.string().max(1_000_000) });

// A user-registered OpenAI-compatible endpoint. The broker validates these
// again in custom-providers.ts; this schema only bounds the wire shape so a
// malformed UI payload cannot reach the file writer.
const customProviderAddCommand = z.object({
  type: z.literal("custom_provider_add"),
  id: z.string().min(1).max(64),
  name: z.string().max(64).optional(),
  baseUrl: z.string().min(1).max(512),
  api: z.enum(["openai-responses", "openai-completions"]),
  // Optional, never stored in models.json. The broker hands it straight to the
  // harness login so it lands in auth.json like any other credential.
  apiKey: z.string().max(512).optional(),
  models: z.array(z.object({
    id: z.string().min(1).max(128),
    name: z.string().max(64).optional(),
    contextWindow: z.number().int().positive().optional()
  })).min(1).max(200)
});
const customProviderTestCommand = z.object({
  type: z.literal("custom_provider_test"),
  baseUrl: z.string().min(1).max(512),
  // Optional means exactly that: when omitted, the probe sends no
  // Authorization header and a successful server is saved as no-auth.
  apiKey: z.string().max(512).optional()
}).strict();
const customProviderRemoveCommand = z.object({
  type: z.literal("custom_provider_remove"),
  id: z.string().min(1).max(64)
});
const cloudTtsProviderSchema = z.enum(["elevenlabs", "openai"]);
const ttsKeySetCommand = z.object({
  type: z.literal("tts_key_set"),
  provider: cloudTtsProviderSchema,
  apiKey: z.string().min(1).max(512)
}).strict();
const ttsKeyClearCommand = z.object({
  type: z.literal("tts_key_clear"),
  provider: cloudTtsProviderSchema
}).strict();
const ttsKeyTestCommand = z.object({
  type: z.literal("tts_key_test"),
  provider: cloudTtsProviderSchema,
  apiKey: z.string().min(1).max(512)
}).strict();
const ttsSpeakCommand = z.object({
  type: z.literal("tts_speak"),
  id: z.string().min(1).max(128),
  provider: z.enum(["kokoro", "elevenlabs", "openai"]),
  model: z.string().min(1).max(128).optional(),
  voice: z.string().min(1).max(128).optional(),
  text: z.string().min(1).max(8000)
}).strict();
const ttsStopCommand = z.object({
  type: z.literal("tts_stop")
}).strict();

export const commandSchema = z.discriminatedUnion("type", [
  initializeCommand,
  submitCommand,
  contextBeginCommand,
  contextCaptureCommand,
  contextCancelCommand,
  browserCompanionCommand,
  browserCompanionOpenSettingsCommand,
  capabilitySetEnabledCommand,
  capabilityFilesRootSetCommand,
  authBeginCommand,
  authResponseCommand,
  authCancelCommand,
  contextDiscardCommand,
  cancelCommand,
  permissionResponseCommand,
  chatCommand,
  linkCommand,
  imageCommand,
  copyCommand,
  customProviderTestCommand,
  customProviderAddCommand,
  z.object({ type: z.literal("voxtype_osd_set"), enabled: z.boolean() }),
  customProviderRemoveCommand,
  ttsKeySetCommand,
  ttsKeyClearCommand,
  ttsKeyTestCommand,
  ttsSpeakCommand,
  ttsStopCommand,
  z.object({ type: z.enum(["dictation_start", "dictation_stop", "dictation_cancel", "history_list", "history_clear", "custom_provider_list", "capabilities_list", "voxtype_osd_status", "voice_status", "shutdown"]) })
]);
export type BrokerCommand = z.infer<typeof commandSchema>;

export type CustomProviderSpec = {
  id: string;
  name: string;
  baseUrl: string;
  api: "openai-responses" | "openai-completions";
  models: Array<{ id: string; name: string; contextWindow: number }>;
  requiresAuth: boolean;
};
export type CustomProviderView = {
  id: string;
  name: string;
  baseUrl: string;
  api: string;
  models: Array<{ id: string; name: string; contextWindow: number }>;
  requiresAuth: boolean;
};

export type CustomProviderProbeResult = {
  baseUrl: string;
  models: Array<{ id: string; name: string; contextWindow: number }>;
};

export type ModelOption = { id: string; name: string; description?: string };
export type ProviderPolicyInfo = {
  tools: "device-approval";
  web: "approved-command" | "search" | "blocked";
  hostReads: boolean;
};
export type ProviderInfo = {
  id: ProviderId;
  name: string;
  version?: string;
  models: ModelOption[];
  defaultModel?: string;
  policy: ProviderPolicyInfo;
};

export type BuiltinAuthMethod = {
  id: string;
  providerId: string;
  authType: "api_key" | "oauth";
  label: string;
  description: string;
};

export type BuiltinAuthPrompt = {
  id: string;
  kind: "text" | "secret" | "select";
  message: string;
  placeholder?: string;
  options?: Array<{ id: string; label: string; description?: string }>;
};

export type StoredImage = {
  id: string;
  mimeType: string;
  path: string;
  bytes: number;
  width: number;
  height: number;
  sourceUrl?: string;
};

export type RenderableImage = StoredImage & { localUrl: string };

export type ContextRepresentationView = {
  id: "text" | "element" | "image";
  kind: "text" | "element" | "image";
  label: string;
  preview?: string;
  confidence: number;
};

export type ContextAttachmentView = {
  version: 1;
  id: string;
  title: string;
  origin: { appId?: string; windowTitle?: string };
  previewImage: RenderableImage;
  representations: ContextRepresentationView[];
  selectedRepresentationIds: Array<"text" | "element" | "image">;
};

export type ToolPermission = {
  id: string;
  requestId: string;
  title: string;
  kind: "execute";
  authority: "device";
  risk?: CapabilityRisk;
  detail: string;
  options: Array<{
    id: string;
    decision: "allow_once" | "allow_session" | "allow_always" | "reject_once" | "reject_always";
    label: string;
  }>;
};

export type ResponseClass = "ACTION" | "ANSWER" | "CONFIRM" | "PLAN" | "UNSURE";

export type CommandReceipt = {
  command: string;
  exitCode: number;
  durationMs: number;
};

export type ResponseOutcome = {
  class: ResponseClass;
  receipt?: CommandReceipt;
};

export type ChatRecord = {
  schemaVersion: 1;
  id: string;
  createdAt: string;
  title: string;
  provider: ProviderId;
  model?: string;
  question: string;
  answer: string;
  // Optional so completed chats written before response classes remain readable.
  response?: ResponseOutcome;
  images: StoredImage[];
  session: {
    acpId?: string;
    cwd?: string;
    resumable: boolean;
    resumeKind: "native" | "transcript";
  };
};

export type ChatView = Omit<ChatRecord, "images"> & { images: RenderableImage[] };

export type BrokerEvent =
  | { type: "ready"; protocolVersion: 2; features: Array<"desktop-context" | "context-attachments" | "voice" | "capability-packs">; providers: ProviderInfo[]; history: ChatView[] }
  | { type: "capabilities"; capabilities: CapabilityView[] }
  | { type: "providers"; providers: ProviderInfo[] }
  | { type: "custom_provider_saved"; provider: CustomProviderView }
  | { type: "custom_provider_tested"; result: CustomProviderProbeResult }
  | { type: "custom_provider_test_failed"; baseUrl: string; message: string }
  | { type: "custom_providers"; providers: CustomProviderView[] }
  | { type: "voxtype_osd"; available: boolean; enabled: boolean; message?: string }
  | { type: "voice"; dictation: VoiceStatus["dictation"]; tts: TtsProviderStatus[] }
  | { type: "tts_tested"; provider: "elevenlabs" | "openai"; result: TtsProviderStatus }
  | { type: "tts_test_failed"; provider: "elevenlabs" | "openai"; message: string }
  | { type: "tts_speaking"; id: string; metered: boolean }
  | { type: "tts_level"; id: string; level: number }
  | { type: "tts_spoken"; id: string }
  | { type: "tts_speak_failed"; id: string; message: string }
  | { type: "dictation_level"; level: number; metered: boolean }
  | { type: "auth_methods"; methods: BuiltinAuthMethod[] }
  | { type: "auth"; phase: "starting"; flowId: string; methodId: string; message: string }
  | { type: "auth"; phase: "prompt"; flowId: string; methodId: string; prompt: BuiltinAuthPrompt }
  | { type: "auth"; phase: "info"; flowId: string; methodId: string; message: string; links?: Array<{ url: string; label?: string }> }
  | { type: "auth"; phase: "browser"; flowId: string; methodId: string; url: string; instructions?: string }
  | { type: "auth"; phase: "device_code"; flowId: string; methodId: string; userCode: string; verificationUri: string; expiresInSeconds?: number }
  | { type: "auth"; phase: "complete" | "cancelled" | "error"; flowId: string; methodId: string; message: string }
  | { type: "state"; id?: string; state: "idle" | "preparing" | "streaming" | "stopping"; message?: string }
  | { type: "content"; id: string; delta: string }
  | { type: "permission"; permission: ToolPermission }
  | { type: "permission_closed"; id: string; permissionId: string; reason: "decided" | "expired" | "cancelled" }
  | { type: "image"; id: string; image: RenderableImage }
  | { type: "context_ready"; id: string; target: { appId?: string; title?: string; window?: z.infer<typeof captureRectangleSchema>; monitor: z.infer<typeof captureRectangleSchema> & { name?: string } } }
  | { type: "context_picker"; id: string; browser: string; title: string; url: string }
  | { type: "context_notice"; id: string; message: string }
  | { type: "context_attachment"; requestId: string; attachment: ContextAttachmentView }
  | { type: "browser_companion"; phase: "ready" | "installing" | "removing" | "failed"; relayInstalled: boolean; setupAvailable: boolean; chromiumConnected: boolean; firefoxConnected: boolean; chromiumExtensionPath: string; firefoxExtensionPath: string; message?: string }
  | { type: "complete"; chat: ChatView }
  | { type: "complete"; id: string; answer: string }
  | { type: "error"; id?: string; code: string; message: string; retryable: boolean }
  | { type: "dictation"; state: "recording" | "transcribing" | "idle" | "unavailable"; text?: string; message?: string }
  | { type: "history"; history: ChatView[] }
  | { type: "herdr"; chatId: string; state: "opening" | "continued" | "unavailable" | "failed"; mode?: "native" | "transcript"; message?: string; stage?: "availability" | "launch" | "workspace" | "session" | "transcript" | "focus"; errorCode?: string }
  | { type: "link"; url: string; opened: boolean }
  | { type: "copied"; copied: boolean };

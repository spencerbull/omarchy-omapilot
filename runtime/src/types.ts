import { z } from "zod";

export const providerIdSchema = z.enum(["builtin", "codex", "claude", "opencode"]);
export type ProviderId = z.infer<typeof providerIdSchema>;
export const harnessIdSchema = providerIdSchema;
export type HarnessId = z.infer<typeof harnessIdSchema>;

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
  artist: contextText(200).optional()
}).strict().refine((value) => Object.keys(value).length > 0, "desktop media is empty");
export const desktopContextSchema = z.object({
  version: z.literal(1),
  activeWindow: desktopWindowSchema.optional(),
  apps: z.array(desktopAppSchema).max(12),
  workspaces: z.array(z.number().int().min(-100_000).max(100_000)).max(12),
  media: z.array(desktopMediaSchema).max(4)
}).strict().refine(
  (value) => value.activeWindow !== undefined || value.apps.length > 0 || value.workspaces.length > 0 || value.media.length > 0,
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
  model: z.preprocess((value) => typeof value === "string" && value.trim() === "" ? undefined : value, z.string().min(1).max(500).optional()),
  desktopContext: desktopContextSchema.optional(),
  contextAttachments: z.array(contextAttachmentSelectionSchema).max(4).optional(),
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

export const commandSchema = z.discriminatedUnion("type", [
  initializeCommand,
  submitCommand,
  contextBeginCommand,
  contextCaptureCommand,
  contextCancelCommand,
  browserCompanionCommand,
  browserCompanionOpenSettingsCommand,
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
  z.object({ type: z.enum(["dictation_start", "dictation_stop", "dictation_cancel", "history_list", "history_clear", "shutdown"]) })
]);
export type BrokerCommand = z.infer<typeof commandSchema>;

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
  kind: "text" | "secret" | "select" | "manual_code";
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
  detail: string;
  options: Array<{
    id: string;
    decision: "allow_once" | "allow_session" | "allow_always" | "reject_once" | "reject_always";
    label: string;
  }>;
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
  | { type: "ready"; protocolVersion: 2; features: Array<"desktop-context" | "context-attachments">; providers: ProviderInfo[]; history: ChatView[] }
  | { type: "providers"; providers: ProviderInfo[] }
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

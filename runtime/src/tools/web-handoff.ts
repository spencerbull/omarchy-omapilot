import { spawn } from "node:child_process";
import { Type } from "typebox";
import type { ToolDefinition } from "../../../node_modules/@earendil-works/pi-coding-agent/dist/core/extensions/types.js";
import type { CommandReceipt, WebHandoffProvider } from "../types.js";
import { runDesktopCommand, type DesktopCommandRunner } from "./desktop.js";

const MAX_HANDOFF_QUERY = 1_000;
const MAX_HANDOFF_URL = 8_192;
const AI_HANDOFF_PROMPT = "Search the web for current information and answer with cited sources.";

const webHandoffParameters = Type.Object({
  query: Type.String({
    description: "Exact question to hand off to the browser research provider configured by the user",
    minLength: 1,
    maxLength: MAX_HANDOFF_QUERY
  })
});

const PROVIDERS: Record<WebHandoffProvider, { label: string; url: string; ai: boolean }> = {
  duckduckgo: { label: "DuckDuckGo", url: "https://duckduckgo.com/", ai: false },
  google: { label: "Google", url: "https://www.google.com/search", ai: false },
  chatgpt: { label: "ChatGPT Search", url: "https://chatgpt.com/", ai: true },
  claude: { label: "Claude", url: "https://claude.ai/new", ai: true },
  grok: { label: "Grok", url: "https://grok.com/", ai: true }
};

export type ClipboardWriter = (text: string, signal?: AbortSignal) => Promise<boolean>;

export type WebHandoffTarget = {
  provider: WebHandoffProvider;
  label: string;
  query: string;
  prompt: string;
  url: string;
  clipboardFallback: boolean;
};

export function normalizeWebHandoffQuery(raw: string): string {
  const value = raw.replaceAll(/\s+/gu, " ").trim();
  if (value === "") throw new Error("Add a question before opening a web handoff");
  if (value.length > MAX_HANDOFF_QUERY) throw new Error("The web handoff question is too long");
  if (/[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/u.test(value))
    throw new Error("The web handoff question contains unsafe control or display characters");
  return value;
}

export function webHandoffTarget(provider: WebHandoffProvider, rawQuery: string): WebHandoffTarget {
  const definition = PROVIDERS[provider];
  const query = normalizeWebHandoffQuery(rawQuery);
  const prompt = definition.ai ? `${AI_HANDOFF_PROMPT}\n\n${query}` : query;
  const url = new URL(definition.url);
  url.searchParams.set("q", prompt);
  if (url.href.length > MAX_HANDOFF_URL) throw new Error("The web handoff URL is too long");
  return {
    provider,
    label: definition.label,
    query,
    prompt,
    url: url.href,
    clipboardFallback: definition.ai
  };
}

export function webHandoffApproval(provider: WebHandoffProvider, rawQuery: unknown): Record<string, unknown> {
  try {
    const target = webHandoffTarget(provider, typeof rawQuery === "string" ? rawQuery : "");
    return {
      command: `omarchy launch browser ${target.url}`,
      provider: target.provider,
      providerLabel: target.label,
      query: target.query,
      clipboardFallback: target.clipboardFallback,
      url: target.url
    };
  } catch {
    return {
      command: "web_handoff (invalid question; no browser will be opened)",
      provider,
      providerLabel: PROVIDERS[provider].label,
      query: "Invalid question"
    };
  }
}

export function webHandoffTitle(provider: WebHandoffProvider): string {
  return `Open web handoff in ${PROVIDERS[provider].label}`;
}

export const writeClipboard: ClipboardWriter = (text, signal) => new Promise<boolean>((resolve) => {
  if (signal?.aborted === true) { resolve(false); return; }
  let child: ReturnType<typeof spawn> | undefined;
  try { child = spawn("wl-copy", [], { stdio: ["pipe", "ignore", "ignore"] }); }
  catch { resolve(false); return; }
  let settled = false;
  const finish = (copied: boolean): void => {
    if (settled) return;
    settled = true;
    clearTimeout(timeout);
    signal?.removeEventListener("abort", abort);
    resolve(copied);
  };
  const abort = (): void => { child?.kill("SIGTERM"); finish(false); };
  const timeout = setTimeout(abort, 5_000);
  timeout.unref();
  signal?.addEventListener("abort", abort, { once: true });
  child.once("error", () => finish(false));
  child.once("close", (code) => finish(code === 0));
  const stdin = child.stdin;
  if (stdin === null) { finish(false); return; }
  stdin.once("error", () => finish(false));
  stdin.end(text);
});

export function createWebHandoffTool(
  provider: WebHandoffProvider = "duckduckgo",
  run: DesktopCommandRunner = runDesktopCommand,
  copy: ClipboardWriter = writeClipboard,
  observeAction?: (receipt: CommandReceipt) => void
): ToolDefinition<typeof webHandoffParameters> {
  return {
    name: "web_handoff",
    label: "Open web handoff",
    description: "Open an exact question in the browser research provider chosen in OmaPilot settings. This hands work to the browser and does not return or verify the provider's answer.",
    promptSnippet: "Hand off a current-information question to the user's configured browser research provider",
    parameters: webHandoffParameters,
    async execute(_toolCallId, input, signal) {
      try {
        const target = webHandoffTarget(provider, input.query);
        const startedAt = Date.now();
        await run("omarchy", ["launch", "browser", target.url], signal);
        observeAction?.({
          command: `omarchy launch browser ${target.url}`,
          exitCode: 0,
          durationMs: Math.max(0, Date.now() - startedAt)
        });
        const clipboardCopied = target.clipboardFallback ? await copy(target.prompt, signal) : false;
        const fallback = target.clipboardFallback
          ? (clipboardCopied
            ? " A paste-ready copy is also on the clipboard if the site did not prefill its composer."
            : " If the site did not prefill its composer, enter the reviewed question there.")
          : "";
        return {
          content: [{
            type: "text",
            text: `Opened ${target.label} in the default browser with the question.${fallback} Continue in the browser; OmaPilot has not read an answer.`
          }],
          details: {
            provider: target.provider,
            providerLabel: target.label,
            query: target.query,
            url: target.url,
            clipboardCopied,
            answerAvailable: false
          }
        };
      } catch {
        return {
          content: [{ type: "text", text: "The web handoff could not be opened." }],
          details: undefined,
          isError: true
        };
      }
    }
  };
}

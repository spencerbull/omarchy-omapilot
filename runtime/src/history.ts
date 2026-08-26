import { mkdir, open, readdir, readFile, rename, rm, unlink, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";
import type { ChatRecord, ChatView, ResponseClass, StoredImage } from "./types.js";
import { pruneImageCache } from "./images.js";
import { omapilotPaths, type OmaPilotPaths } from "./paths.js";

const MAX_CHATS = 30;

export class HistoryStore {
  readonly #paths: OmaPilotPaths;

  constructor(paths: OmaPilotPaths = omapilotPaths()) {
    this.#paths = paths;
  }

  async list(): Promise<ChatRecord[]> {
    await mkdir(this.#paths.records, { recursive: true, mode: 0o700 });
    const names = await readdir(this.#paths.records);
    const records: ChatRecord[] = [];
    for (const name of names.filter((value) => /^[0-9a-f-]{36}\.json$/u.test(value))) {
      try {
        const parsed: unknown = JSON.parse(await readFile(join(this.#paths.records, name), "utf8"));
        if (isChatRecord(parsed)) records.push(parsed);
      } catch {
        // Ignore an unreadable record without exposing its content.
      }
    }
    return records.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, MAX_CHATS);
  }

  async get(id: string): Promise<ChatRecord | undefined> {
    if (!isUuid(id)) return undefined;
    try {
      const parsed: unknown = JSON.parse(await readFile(join(this.#paths.records, `${id}.json`), "utf8"));
      return isChatRecord(parsed) ? parsed : undefined;
    } catch {
      return undefined;
    }
  }

  async save(chat: ChatRecord): Promise<ChatRecord[]> {
    await mkdir(this.#paths.records, { recursive: true, mode: 0o700 });
    const destination = join(this.#paths.records, `${chat.id}.json`);
    const temporary = `${destination}.${process.pid}.tmp`;
    await writeFile(temporary, `${JSON.stringify(chat)}\n`, { encoding: "utf8", mode: 0o600, flag: "wx" });
    const handle = await open(temporary, "r");
    await handle.sync();
    await handle.close();
    await rename(temporary, destination);
    const evicted = await this.#evictRecords();
    await pruneImageCache(this.#paths);
    return evicted;
  }

  async delete(id: string): Promise<ChatRecord | undefined> {
    if (!isUuid(id)) return undefined;
    const chat = await this.get(id);
    try {
      await unlink(join(this.#paths.records, `${id}.json`));
    } catch {
      return undefined;
    }
    if (chat !== undefined) {
      await Promise.all(chat.images.map(async (image) => {
        if (basename(image.path) === image.path) await rm(join(this.#paths.images, image.path), { force: true });
      }));
      await this.#removeUnreferencedPiSession(chat);
    }
    return chat;
  }

  async clear(): Promise<ChatRecord[]> {
    const chats = await this.listAll();
    await rm(this.#paths.records, { recursive: true, force: true });
    await rm(this.#paths.images, { recursive: true, force: true });
    await rm(this.#paths.piSessions, { recursive: true, force: true });
    return chats;
  }

  async #evictRecords(): Promise<ChatRecord[]> {
    const records = await this.listAll();
    const evicted = records.slice(MAX_CHATS);
    const deleted = await Promise.all(evicted.map((chat) => this.delete(chat.id)));
    return deleted.filter((chat): chat is ChatRecord => chat !== undefined);
  }

  async listAll(): Promise<ChatRecord[]> {
    await mkdir(this.#paths.records, { recursive: true, mode: 0o700 });
    const names = await readdir(this.#paths.records);
    const records = await Promise.all(names.filter((name) => name.endsWith(".json")).map(async (name) => {
      try {
        const parsed: unknown = JSON.parse(await readFile(join(this.#paths.records, name), "utf8"));
        return isChatRecord(parsed) ? parsed : undefined;
      } catch {
        return undefined;
      }
    }));
    return records.filter((record): record is ChatRecord => record !== undefined)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async #removeUnreferencedPiSession(chat: ChatRecord): Promise<void> {
    const sessionId = chat.provider === "builtin" ? chat.session.acpId : undefined;
    if (sessionId === undefined || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(sessionId)) return;
    if ((await this.listAll()).some((record) => record.provider === "builtin" && record.session.acpId === sessionId)) return;
    let names: string[];
    try { names = await readdir(this.#paths.piSessions); } catch { return; }
    const suffix = `_${sessionId}.jsonl`;
    await Promise.all(names.filter((name) => name.endsWith(suffix))
      .map((name) => rm(join(this.#paths.piSessions, name), { force: true })));
  }

}

export function presentImage(image: StoredImage, paths: OmaPilotPaths = omapilotPaths()): StoredImage & { localUrl: string } {
  return { ...image, path: basename(image.path), localUrl: pathToFileURL(join(paths.images, basename(image.path))).toString() };
}

export function presentChat(chat: ChatRecord, paths: OmaPilotPaths = omapilotPaths()): ChatView {
  return {
    schemaVersion: chat.schemaVersion,
    id: chat.id,
    createdAt: chat.createdAt,
    title: chat.title,
    provider: chat.provider,
    ...(chat.model === undefined ? {} : { model: chat.model }),
    question: chat.question,
    answer: chat.answer,
    ...(chat.response === undefined ? {} : { response: chat.response }),
    images: chat.images.map((image) => presentImage(image, paths)),
    session: chat.session
  };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value);
}

function isChatRecord(value: unknown): value is ChatRecord {
  if (typeof value !== "object" || value === null) return false;
  return "schemaVersion" in value && value.schemaVersion === 1 &&
    "id" in value && typeof value.id === "string" && isUuid(value.id) &&
    "createdAt" in value && typeof value.createdAt === "string" &&
    "provider" in value && ["builtin", "codex", "openai", "claude", "grok", "xai", "openai-compatible", "opencode"].includes(String(value.provider)) &&
    "question" in value && typeof value.question === "string" &&
    "answer" in value && typeof value.answer === "string" &&
    (!("response" in value) || isResponseOutcome(value.response)) &&
    "images" in value && Array.isArray(value.images);
}

function isResponseOutcome(value: unknown): boolean {
  if (typeof value !== "object" || value === null || !("class" in value)) return false;
  const response = value as { class?: unknown; receipt?: unknown };
  const classes: ResponseClass[] = ["ACTION", "ANSWER", "CONFIRM", "PLAN", "UNSURE"];
  if (!classes.includes(response.class as ResponseClass)) return false;
  if (response.receipt === undefined) return true;
  if (typeof response.receipt !== "object" || response.receipt === null) return false;
  const receipt = response.receipt as { command?: unknown; exitCode?: unknown; durationMs?: unknown };
  return typeof receipt.command === "string" && receipt.command.length > 0 && receipt.command.length <= 32_000
    && receipt.exitCode === 0 && typeof receipt.durationMs === "number"
    && Number.isInteger(receipt.durationMs) && receipt.durationMs >= 0 && receipt.durationMs <= 180_000;
}

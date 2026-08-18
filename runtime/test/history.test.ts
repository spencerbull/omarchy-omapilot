import { mkdir, mkdtemp, readdir, rm, truncate, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { HistoryStore, presentChat } from "../src/history.js";
import { quickchatPaths } from "../src/paths.js";
import type { ChatRecord, StoredImage } from "../src/types.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("history store", () => {
  it("atomically retains only the newest 30 complete chats", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-history-")); roots.push(root);
    const paths = quickchatPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
    const store = new HistoryStore(paths);
    const evicted: ChatRecord[] = [];
    for (let index = 0; index < 35; index += 1) evicted.push(...await store.save(record(index)));
    const records = await store.list();
    expect(records).toHaveLength(30);
    expect(records[0]?.title).toBe("Chat 34");
    expect(records.at(-1)?.title).toBe("Chat 5");
    expect((await readdir(paths.records)).some((name) => name.endsWith(".tmp"))).toBe(false);
    expect(evicted.map((chat) => chat.title)).toEqual(["Chat 0", "Chat 1", "Chat 2", "Chat 3", "Chat 4"]);
  });

  it("deletes one record and clears all state", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-history-")); roots.push(root);
    const paths = quickchatPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
    const store = new HistoryStore(paths);
    await store.save(record(1));
    expect((await store.delete(record(1).id))?.id).toBe(record(1).id);
    await store.save(record(2));
    expect((await store.clear()).map((chat) => chat.id)).toEqual([record(2).id]);
    expect(await store.list()).toEqual([]);
  });

  it("keeps a shared Pi session until its final chat record is deleted", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-history-pi-")); roots.push(root);
    const paths = quickchatPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
    const store = new HistoryStore(paths);
    const sessionId = "11111111-1111-4111-8111-111111111111";
    const sessionFile = `2026-08-18_${sessionId}.jsonl`;
    await mkdir(paths.piSessions, { recursive: true });
    await writeFile(join(paths.piSessions, sessionFile), "session\n");
    await store.save({ ...record(1), session: { acpId: sessionId, resumable: true, resumeKind: "native" } });
    await store.save({ ...record(2), session: { acpId: sessionId, resumable: true, resumeKind: "native" } });

    await store.delete(record(1).id);
    expect(await readdir(paths.piSessions)).toEqual([sessionFile]);
    await store.delete(record(2).id);
    expect(await readdir(paths.piSessions)).toEqual([]);
  });

  it("loads a legacy capability field but strips it from presented history", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-history-legacy-")); roots.push(root);
    const paths = quickchatPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
    const store = new HistoryStore(paths);
    const legacy = { ...record(3), capability: "tools" };
    await mkdir(paths.records, { recursive: true });
    await writeFile(join(paths.records, `${legacy.id}.json`), `${JSON.stringify(legacy)}\n`);
    const records = await store.list();
    expect(records).toHaveLength(1);
    expect(records[0]?.id).toBe(legacy.id);
    if (records[0] === undefined) throw new Error("legacy chat did not load");
    expect(presentChat(records[0])).not.toHaveProperty("capability");
  });

  it("removes evicted cache images from retained chat records", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-history-images-")); roots.push(root);
    const paths = quickchatPaths({ HOME: root, XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"), XDG_RUNTIME_DIR: join(root, "run") });
    const store = new HistoryStore(paths);
    await mkdir(paths.images, { recursive: true });
    const oldest = image("oldest.png");
    const newest = image("newest.png");
    await sparseImage(paths.images, oldest.path, 1_600_000_000);
    await store.save({ ...record(1), images: [oldest] });
    await sparseImage(paths.images, newest.path, 1_700_000_000);
    await store.save({ ...record(2), images: [newest] });
    expect((await store.get(record(1).id))?.images).toEqual([]);
    expect((await store.get(record(2).id))?.images).toEqual([newest]);
    expect(await readdir(paths.images)).toEqual(["newest.png"]);
  });
});

function image(path: string): StoredImage {
  return { id: `11111111-1111-4111-8111-${path === "oldest.png" ? "111111111111" : "222222222222"}`, mimeType: "image/png", path, bytes: 30 * 1024 * 1024, width: 1, height: 1 };
}

async function sparseImage(directory: string, name: string, timestamp: number): Promise<void> {
  const path = join(directory, name);
  await writeFile(path, "");
  await truncate(path, 30 * 1024 * 1024);
  await utimes(path, timestamp, timestamp);
}

function record(index: number): ChatRecord {
  const suffix = index.toString(16).padStart(12, "0");
  return {
    schemaVersion: 1, id: `00000000-0000-4000-8000-${suffix}`, createdAt: new Date(Date.UTC(2026, 7, 11, 0, 0, index)).toISOString(),
    title: `Chat ${String(index)}`, provider: "builtin", question: "Q", answer: "A", images: [],
    session: { resumable: false, resumeKind: "transcript" }
  };
}

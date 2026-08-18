import { access, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { launchDetached } from "../src/process.js";

const roots: string[] = [];
afterEach(async () => Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true }))));

describe("detached process launch", () => {
  it("returns after spawn without waiting for or terminating the launched process", async () => {
    const root = await mkdtemp(join(tmpdir(), "quickchat-detached-"));
    roots.push(root);
    const marker = join(root, "opened.txt");
    const launched = await launchDetached(process.execPath, [
      "-e",
      "setTimeout(() => require('node:fs').writeFileSync(process.argv[1], 'opened'), 150)",
      marker
    ]);

    expect(launched).toBe(true);
    await expect(access(marker)).rejects.toThrow();
    await vi.waitFor(() => expect(readFile(marker, "utf8")).resolves.toBe("opened"));
  });

  it("reports a launch failure", async () => {
    expect(await launchDetached(join(tmpdir(), "quickchat-missing-executable"), [])).toBe(false);
  });
});

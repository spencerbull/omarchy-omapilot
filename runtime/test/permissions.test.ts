import { describe, expect, it } from "vitest";
import { normalizeToolPermission } from "../src/permissions.js";

describe("tool permission presentation", () => {
  it("preserves exact provider approval choices without exposing provider IDs", () => {
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", title: "Run uname", rawInput: { command: "uname -s", cwd: "/tmp/chat", timeout: 10 } },
      options: [
        { optionId: "provider-allow", name: "Yes", kind: "allow_once" },
        { optionId: "provider-always", name: "Always", kind: "allow_always" },
        { optionId: "provider-deny", name: "No", kind: "reject_once" }
      ]
    });
    expect(permission).toEqual({
      view: {
        id: "11111111-1111-4111-8111-111111111111",
        requestId: "turn-1",
        title: "Run uname",
        kind: "execute",
        authority: "device",
        detail: '{\n  "command": "uname -s",\n  "cwd": "/tmp/chat",\n  "timeout": 10\n}',
        options: [
          { id: "option-0", decision: "allow_once", label: "Yes" },
          { id: "option-1", decision: "allow_always", label: "Always" },
          { id: "option-2", decision: "reject_once", label: "No" }
        ]
      },
      optionIds: {
        "option-0": "provider-allow",
        "option-1": "provider-always",
        "option-2": "provider-deny"
      }
    });
    expect(JSON.stringify(permission?.view)).not.toContain("provider-");
  });

  it.each(["read", "search", "fetch", "edit", "delete", "move", "switch_mode", "other"] as const)("rejects %s before it reaches the UI", (kind) => {
    expect(normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind, title: "Unsafe" },
      options: [{ optionId: "allow", name: "Allow", kind: "allow_once" }]
    })).toBeUndefined();
  });

  it("does not invent approval choices", () => {
    expect(normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command: "uname -s" } },
      options: [{ optionId: "always", name: "Always", kind: "allow_always" }]
    })?.view.options).toEqual([{ id: "option-0", decision: "allow_always", label: "Always" }]);
  });

  it.each(["x".repeat(3_001), "echo safe\u202eevil", "echo safe\u061cevil", "echo safe\u0085evil"])("rejects oversized, controlled, or directionally ambiguous commands", (command) => {
    const pending = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command } },
      options: [
        { optionId: "allow", name: "Allow", kind: "allow_once" },
        { optionId: "deny", name: "Deny", kind: "reject_once" }
      ]
    });
    expect(pending).toMatchObject({
      view: { title: "Command blocked", authority: "device", options: [{ id: "option-1", decision: "reject_once", label: "Deny" }] },
      optionIds: { "option-1": "deny" }
    });
    expect(pending?.view.options.some((option) => option.decision.startsWith("allow_"))).toBe(false);
  });

  it("fails closed when the adapter omits a classifiable target", () => {
    expect(normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { opaque: "do something" } },
      options: [{ optionId: "allow", name: "Allow", kind: "allow_once" }]
    })?.view.options).toEqual([]);
  });

  it("preserves complete multiline and tabbed commands in a device-authority card", () => {
    const command = "cat <<'EOF'\nhello\tworld\nEOF\n";
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command, cwd: "/tmp/chat" } },
      options: [
        { optionId: "allow", name: "Allow", kind: "allow_once" },
        { optionId: "deny", name: "Deny", kind: "reject_once" }
      ]
    });
    expect(permission?.view.detail).toContain("cat <<'EOF'\\nhello\\tworld\\nEOF\\n");
    expect(permission?.view).toMatchObject({ authority: "device", options: expect.arrayContaining([{ id: "option-0", decision: "allow_once", label: "Allow" }]) });
  });

  it("renders multiline edit and write payloads instead of making basic Pi tools unusable", () => {
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "builtin", {
      sessionId: "session",
      toolCall: {
        toolCallId: "tool", kind: "execute",
        rawInput: { command: "write /tmp/example", path: "/tmp/example", content: "first\nsecond\tcolumn\n" }
      },
      options: [{ optionId: "allow", name: "Allow once", kind: "allow_once" }]
    });
    expect(permission?.view.options).toEqual([{ id: "option-0", decision: "allow_once", label: "Allow once" }]);
    expect(permission?.view.detail).toContain("first\\nsecond\\tcolumn\\n");
  });

  it("distinguishes provider session approval from durable approval", () => {
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "codex", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command: "npm test" } },
      options: [
        { optionId: "allow_session", name: "Allow for This Session", kind: "allow_always" },
        { optionId: "allow_always", name: "Allow and Don't Ask Again", kind: "allow_always" }
      ]
    });
    expect(permission?.view.options).toEqual([
      { id: "option-0", decision: "allow_session", label: "Allow for This Session" },
      { id: "option-1", decision: "allow_always", label: "Allow and Don't Ask Again" }
    ]);
  });

  it("preserves multiple provider choices in the same ACP category", () => {
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "claude", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command: "apply plan" } },
      options: [
        { optionId: "auto", name: "Yes, and use auto mode", kind: "allow_always" },
        { optionId: "acceptEdits", name: "Yes, and auto-accept edits", kind: "allow_always" }
      ]
    });
    expect(permission?.view.options).toHaveLength(2);
    expect(permission?.optionIds).toEqual({ "option-0": "auto", "option-1": "acceptEdits" });
  });

  it("marks surfaced Claude command approvals as device authority", () => {
    const permission = normalizeToolPermission("turn-1", "11111111-1111-4111-8111-111111111111", "claude", {
      sessionId: "session",
      toolCall: { toolCallId: "tool", kind: "execute", rawInput: { command: "uname -s" } },
      options: [{ optionId: "allow", name: "Allow", kind: "allow_once" }]
    });
    expect(permission?.view.authority).toBe("device");
  });
});

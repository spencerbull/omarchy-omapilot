# Native Pi harness

OmaPilot embeds a Pi coding-agent runtime. It does not require an external CLI for
OpenAI API, Codex subscription, Anthropic, or OpenAI-compatible requests. The
Codex, Claude, and OpenCode are separate ACP harness choices. They are never
used as fallbacks for the built-in harness.

## Configuration directory

The native harness keeps OmaPilot-owned configuration under
`${XDG_CONFIG_HOME:-$HOME/.config}/omapilot/`. Set `OMAPILOT_CONFIG_DIR` to an
absolute path before starting Omarchy to use another location. Shared skills
and named agents are discovered from `~/.agents/` (or `OMAPILOT_AGENTS_DIR`).

```text
~/.config/omapilot/
├── auth.json
├── models.json
├── models-store.json
└── approvals.json

~/.agents/
├── skills/example/SKILL.md
└── agents/reviewer.md
```

Credentials are resolved by Pi's model runtime and are never copied to OmaPilot
history. OAuth credentials refresh through the provider flow. API keys can come
from `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `auth.json`:

```json
{
  "openai": { "type": "api_key", "key": "$OPENAI_API_KEY" },
  "anthropic": { "type": "api_key", "key": "$ANTHROPIC_API_KEY" }
}
```

Codex subscription and Claude subscription OAuth entries use the
`openai-codex` and `anthropic` keys respectively. Normally, configure these from
the authentication card under OmaPilot Settings. The broker invokes Pi's native
typed login APIs in the background: secrets are entered in a password field,
OAuth continues in the system browser, and provider prompts, device codes,
progress, cancellation, and failures remain visible in OmaPilot. No Pi terminal
or `/login` handoff is involved.

## OpenAI-compatible providers

Add compatible endpoints to `${XDG_CONFIG_HOME:-$HOME/.config}/omapilot/models.json`. Providers using
`openai-completions` or `openai-responses` appear as namespaced entries in the
**Built-in (OmaPilot)** model picker.

```json
{
  "providers": {
    "local": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "api": "openai-completions",
      "apiKey": "local-only-placeholder",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "qwen-coder",
          "name": "Qwen Coder",
          "contextWindow": 131072,
          "maxTokens": 16384
        }
      ]
    }
  }
}
```

Remote compatible endpoints should use an environment reference or credential
entry rather than a literal secret. Model IDs are namespaced internally so two
configured providers may expose the same upstream model ID.

## Skills and context

The harness uses the Agent Skills `SKILL.md` format and progressively discloses
skill descriptions to the model. It loads these roots when they exist:

- `~/.agents/skills/`
- `.agents/skills/` in the working directory
- Pi's native project `.pi/skills/` discovery

Project `AGENTS.md`/`CLAUDE.md` context is handled by the Pi resource loader.
Executable Pi extensions are not auto-loaded because they would bypass
OmaPilot's tool permission boundary.

## Named agents

Put named profiles in `~/.agents/agents/*.md` (or `.agents/agents/*.md` in the
working directory). The root agent receives an `agent` tool and can delegate a
bounded task when a profile description matches.

```markdown
---
name: reviewer
description: Reviews a proposed change for correctness and regressions
tools: [read, grep, find, ls]
model: openai/gpt-5.4
---

Review the requested change. Focus on concrete defects and missing tests.
```

`name` must be a safe 1–64 character identifier. `tools` is optional and is
limited to `read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`. Named
agents default to read-only discovery tools. A named agent's bash, edit, or
write call goes through the same approval broker as its parent. Nested
delegation is disabled to keep fan-out bounded.

## Tools and permissions

The root native agent has Pi's `read`, `bash`, `edit`, `write`, `grep`, `find`,
and `ls` tools plus the named-agent tool. Reads run with the current user's
read authority. Every bash, edit, and write call pauses before execution and
shows its complete structured input in OmaPilot. Unreviewable or oversized
inputs fail closed. Native Pi offers allow once, allow the exact request for the
current turn, always allow the exact request in this working directory, deny,
and always deny the exact request. Durable decisions are stored as SHA-256
fingerprints in `approvals.json`; command text is not stored. ACP harnesses
surface their provider-native choices, including distinct session and durable
options when supplied. Dangerous auto-approve can select only allow once.

The native harness keeps Pi sessions in memory for a Quickchat turn. OmaPilot
stores the completed answer under its existing bounded history policy, but not
raw tool input/output, credentials, or Pi conversation files. Continue in Herdr
therefore uses the transcript handoff for native Pi chats.

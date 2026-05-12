# MDOMO-12 Research: Claude Settings Architecture

## Overview

The goal (GitHub Issue #26) is to set three Claude settings for all three worker types:
- Model: `claude-sonnet-4-6`
- Advisor model: `claude-opus-4-7`
- Effort level: `medium`

## How Claude Settings Are Applied

All three workers (majordomo, minordomo-plan, minordomo-step) share a common setup sequence:

1. `shared/setup-env.sh` — sets credentials env vars
2. `shared/setup-claude.sh` — **copies `shared/agent-settings.json` to `~/.claude/settings.json`**
3. `claude -p "$(cat <system-prompt.md>)"` — invokes Claude

Since `setup-claude.sh` deploys the same `agent-settings.json` to all workers, a single change to that file propagates to all three.

## Current agent-settings.json

Only contains `permissions` and `hooks` keys. No model/effort settings.

## Claude Settings JSON Schema (from binary analysis)

Relevant keys supported in `settings.json`:

| Key | Type | Description |
|-----|------|-------------|
| `model` | string | Override the default model (e.g., `"claude-sonnet-4-6"`) |
| `advisorModel` | string | Advisor model for the server-side advisor tool (e.g., `"claude-opus-4-7"`) |
| `effortLevel` | enum: `"low"`, `"medium"`, `"high"`, `"xhigh"` | Persisted effort level for supported models |

## The Advisor Tool

The Advisor is a server-side tool built into Claude Code. When called with `advisor()`, it forwards the entire conversation history to a stronger reviewer model. It is intended to be called before substantive work and before declaring a task complete.

The advisor model is configured via `advisorModel` in settings.json (or `~/.claude/settings.json`).

## Model IDs

From the Claude Code system context:
- Sonnet 4.6: `claude-sonnet-4-6`
- Opus 4.7: `claude-opus-4-7`

## Implementation Approach

Add three keys to `shared/agent-settings.json`:
```json
{
  "model": "claude-sonnet-4-6",
  "advisorModel": "claude-opus-4-7",
  "effortLevel": "medium",
  "permissions": { ... },
  "hooks": { ... }
}
```

No Jenkinsfile changes required — the settings file change applies to all workers automatically.

## CLI Flags vs. Settings File

- `--model` and `--effort` are available as CLI flags, but using settings.json is cleaner
- `advisorModel` has no CLI flag equivalent — settings.json is the only way to configure it
- Using settings.json for all three keeps the configuration in one place

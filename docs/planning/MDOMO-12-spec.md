# Implementation Spec: MDOMO-12
# Set Claude settings related to model, effort, & Advisor when running the 3 workers

## Background

All three workers (majordomo, minordomo-plan, minordomo-step) share a common agent settings
file at `shared/agent-settings.json`, which `shared/setup-claude.sh` copies to
`~/.claude/settings.json` before each `claude -p` invocation. Adding model/effort/advisor
settings to this single file propagates to all three workers automatically.

## Stage 1: Add model, advisor, and effort settings to shared/agent-settings.json

### Description

Update `shared/agent-settings.json` to add three top-level keys:
- `"model": "claude-sonnet-4-6"` — sets the primary Claude model for all workers
- `"advisorModel": "claude-opus-4-7"` — sets the stronger reviewer model used by the built-in
  Advisor tool
- `"effortLevel": "medium"` — sets the persisted effort level for all workers

No Jenkinsfile changes are required; all three workers already source `shared/setup-claude.sh`
which deploys this file.

### Acceptance Criteria
- `shared/agent-settings.json` is valid JSON containing `"model": "claude-sonnet-4-6"`
- `shared/agent-settings.json` contains `"advisorModel": "claude-opus-4-7"`
- `shared/agent-settings.json` contains `"effortLevel": "medium"`
- All existing `permissions` and `hooks` keys are preserved unchanged
- `make test` passes (shellcheck, bats, prompt validation)

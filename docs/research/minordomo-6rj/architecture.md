# Librarian Job: Research Notes

## Context

Issue: https://github.com/wcjordan/minordomo/issues/281
Title: "Introduce a Librarian job / functionality to periodically keep docs up to date"
Issue body: **empty** — needs clarification before spec can be written.

## Existing Patterns

### Relevant Existing Jobs

- **minordomo-sweep/**: Cron job (every 4 hours), runs `shared/sweep-stale-tasks.sh` to reset orphaned beads tasks. No Claude involved.
- **majordomo/**: Orchestration job; in Step 9, Majordomo reviews planning/research docs before opening feature→main PRs and updates general docs as appropriate. Only runs when a story is complete.
- **minordomo-plan/** and **minordomo-step/**: Agent jobs (parameterized). Use Claude.

### Docs That Exist

General docs (landing on `main`):
- `README.md`
- `CLAUDE.md` (symlinked as `AGENTS.md`)
- `docs/GETTING_AROUND.md` — repo structure and capability table
- `docs/WORKFLOWS.md` — branching model, status flows, task prioritization
- `docs/agent-workflow-spec.md` — detailed capability descriptions and Majordomo run sequence
- `docs/FUTURE_WORK.md` — planned future capabilities

System prompts (in-tree, treated as code):
- `majordomo/system-prompt.md`
- `minordomo-plan/system-prompt.md`
- `minordomo-step/system-prompt.md`

### Gap in Current Coverage

Majordomo Step 9 updates general docs only when a feature story completes. Between feature completions, docs can drift from the codebase — e.g., if scripts are added/removed without updating GETTING_AROUND.md, or if the Majordomo run sequence changes without updating agent-workflow-spec.md.

## Proposed Librarian Architecture

A new Jenkins job `minordomo-librarian/`:
- Runs on a cron schedule (frequency TBD)
- Uses Claude to review docs vs. codebase
- Identifies drift: missing entries, outdated descriptions, references to removed files/scripts
- Opens a PR against `main` (not direct commits — following hard rule)
- PR contains doc updates as a commit

### Jenkinsfile Pattern

Should follow `minordomo-sweep/Jenkinsfile` structure (standalone pipeline, no AGENT_MODE) but use Claude instead of a shell script.

Alternatively, could use `shared/agent-pipeline.Jenkinsfile` with a new AGENT_MODE='librarian'.

### Key Design Questions (needs-input)

1. **Scope**: Which files should the Librarian maintain?
   - Narrow: `docs/*.md`, `README.md`, `CLAUDE.md` (general docs only)
   - Wide: also system prompts (`majordomo/system-prompt.md`, etc.)

2. **Schedule/trigger**: How often, and what triggers it?
   - Weekly cron
   - Daily cron
   - After each merge to main (event-driven)
   - Both cron and event-driven

3. **Definition of "up to date"**: What should it check?
   - Structural consistency: GETTING_AROUND.md lists match actual files/scripts
   - Content drift: doc descriptions match actual code behavior
   - Both

## Implementation Stages (Draft, Pending Clarification)

Rough stage breakdown (likely 2–3 stages):
- Stage 1: New Jenkinsfile + system prompt skeleton + supporting shared scripts
- Stage 2: Claude-based doc review and PR-opening logic
- Stage 3: Tests (bats/shellcheck) + integration into shared agent infrastructure

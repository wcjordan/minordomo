# Librarian Job: Research Notes

## Context

Issue: https://github.com/wcjordan/minordomo/issues/281
Title: "Introduce a Librarian job / functionality to periodically keep docs up to date"

## Requirements (from GH issue comments)

1. **Scope**: `docs/**/*.md`, `README.md`, `CLAUDE.md` — NOT system prompts
2. **Schedule**: Daily cron
3. **"Up to date"**: Both structural drift (broken references, missing entries) AND content drift (descriptions that don't match actual behavior)
4. **Suggestion system**: Agents write to `docs/suggestions/`; the Librarian integrates suggestions into docs

## Existing Patterns

### Relevant Existing Jobs

- **minordomo-sweep/**: Cron job (every 4 hours), runs `shared/sweep-stale-tasks.sh`, no Claude.
- **majordomo/**: Orchestration job with Claude; in Step 9, reviews planning/research docs, updates general docs, deletes `docs/planning/<EPIC_KEY>-spec.md` and `docs/research/<EPIC_KEY>/` before feature→main PR. Does NOT touch `docs/suggestions/`.
- **minordomo-plan/** and **minordomo-step/**: Agent jobs (parameterized, run with target-repo clone). Use `shared/agent-pipeline.Jenkinsfile` via `AGENT_MODE`.

### Docs That Exist (in scope for Librarian)

General docs (landing on `main`):
- `README.md`
- `CLAUDE.md` (symlinked as `AGENTS.md`)
- `docs/GETTING_AROUND.md` — repo structure and capability table
- `docs/WORKFLOWS.md` — branching model, status flows, task prioritization
- `docs/agent-workflow-spec.md` — detailed capability descriptions and Majordomo run sequence
- `docs/FUTURE_WORK.md` — planned future capabilities
- `docs/setup/*.md` — setup guides

### Docs Excluded from Librarian Review

- `docs/research/<EPIC_KEY>/` — ephemeral per-Epic research, deleted by Majordomo Step 9
- `docs/planning/<EPIC_KEY>-spec.md` — ephemeral spec docs, deleted by Majordomo Step 9
- `docs/suggestions/` — read and integrated by Librarian, not reviewed for drift

### Majordomo Step 9 Behavior

Step 9 deletes:
- `docs/planning/<EPIC_KEY>-spec.md`
- `docs/research/<EPIC_KEY>/`

It does NOT delete `docs/suggestions/` — suggestions should land on `main` so the Librarian can read them.

## Architecture Decision: Librarian Job

### Structure

New `minordomo-librarian/` directory containing:
- `Jenkinsfile` — standalone pipeline (NOT using `shared/agent-pipeline.Jenkinsfile`, which is for parameterized worker/planning agents)
- `system-prompt.md` — Librarian agent instructions

The Jenkinsfile pattern closely follows `majordomo/Jenkinsfile`:
- Daily cron trigger
- `CLAUDE_CODE_OAUTH_TOKEN` + `GH_APP` credentials
- `source shared/setup-env.sh` + `source shared/setup-claude.sh`
- Runs Claude with system prompt
- Token usage reporting via `shared/report-token-usage.py`
- `check-run-errors.py` to flag agent-reported errors

### Librarian System Prompt Design

The Librarian:
1. **Idempotency guard**: Check for any open PR from a `librarian/` branch to main. If one exists, exit cleanly (no duplicate PRs).
2. **Drift detection**: Review `docs/**/*.md`, `README.md`, `CLAUDE.md` for:
   - Structural drift: references to files/scripts that no longer exist; newly added files/scripts not yet documented
   - Content drift: descriptions that no longer match current code behavior
3. **Suggestions integration**: Read all files in `docs/suggestions/`; integrate relevant suggestions into appropriate docs; delete the suggestion files after integration.
4. **PR or exit**: If changes made → create branch `librarian/YYYY-MM-DD`, commit, push, open PR to main. If no changes → exit cleanly.

### Suggestion-Writing System

- `docs/suggestions/.gitkeep` establishes the directory in git.
- Plan and step agents writing notes about minordomo infrastructure write suggestion files to `docs/suggestions/`.
- Scope: Suggestions are only written by agents working on MINORDOMO issues (target repo = minordomo). Agents working on chalk, gcp-setup, forester cannot write to minordomo's docs/suggestions/ (they are cd'd into the target repo clone).
- Suggestion files: `suggestion-<beads-task-id>-<brief>.md`, Markdown format describing what should be documented and where.
- Suggestions reach `main` via the normal PR flow (task branch → feature branch → main). Majordomo Step 9 does not delete `docs/suggestions/`.

### validate-prompts.py Updates Needed

- Add `"minordomo-librarian"` to `VALID_JOB_NAMES`
- Add `"minordomo-librarian/"` to `REPO_DIRS`

## Stage Breakdown

### Stage 1: Librarian job infrastructure
Create `minordomo-librarian/Jenkinsfile` + `system-prompt.md`, update `test/validate-prompts.py`, update `docs/GETTING_AROUND.md` + `docs/agent-workflow-spec.md`.

### Stage 2: Suggestion-writing system
Create `docs/suggestions/.gitkeep`, update `minordomo-plan/system-prompt.md` and `minordomo-step/system-prompt.md` with suggestion-writing instructions.

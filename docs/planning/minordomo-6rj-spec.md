# Spec: Introduce a Librarian Job

**Epic:** minordomo-6rj
**Issue:** https://github.com/wcjordan/minordomo/issues/281

## Overview

A new `minordomo-librarian` Jenkins job runs on a daily cron and uses Claude to keep documentation up to date. It detects structural drift (broken file references, undocumented new files) and content drift (descriptions that no longer match actual behavior) in `docs/**/*.md`, `README.md`, and `CLAUDE.md`. It also integrates suggestion files written by pipeline agents to `docs/suggestions/`. When changes are needed, it opens a PR to `main`; when nothing needs updating, it exits cleanly.

### Design Decisions

- **Suggestions-file approach chosen over direct integration**: agents write suggestion files to `docs/suggestions/`; the Librarian polishes and integrates them. This keeps agent runs focused on their primary task.
- **Suggestion scope limited to minordomo agents working on minordomo issues**: agents working on other repos (chalk, gcp-setup, forester) are cd'd into the target repo and cannot write to minordomo's `docs/suggestions/`.
- **Idempotency via open-PR check**: if a `librarian/` PR to main already exists, the agent exits cleanly instead of opening a duplicate.
- **PR-not-commit**: the Librarian opens a PR; humans merge. Never commits directly to main.

---

## Stage 1: Librarian job infrastructure

### Description

Create the `minordomo-librarian/` Jenkins job directory with a `Jenkinsfile` and `system-prompt.md`. The Jenkinsfile follows the `majordomo/Jenkinsfile` pattern: daily cron trigger, `CLAUDE_CODE_OAUTH_TOKEN` + `GH_APP` credentials, runs Claude with the librarian system prompt, and reports token usage. The system prompt instructs the agent to:

1. Check for an open `librarian/` PR to main (idempotency guard — exit cleanly if one exists).
2. Review `docs/**/*.md`, `README.md`, `CLAUDE.md` for structural drift (references to files/scripts that no longer exist; newly added files/scripts not documented) and content drift (descriptions that do not match current code behavior). Exclude `docs/research/`, `docs/planning/`, and `docs/suggestions/` from drift detection (these are ephemeral or agent-managed).
3. Read all files under `docs/suggestions/` and integrate relevant suggestions into appropriate documentation files. Delete the suggestion files after integrating them.
4. If any changes were made: create branch `librarian/YYYY-MM-DD` (using today's date), commit all changes, push, and open a PR to `main`. If no changes are needed: exit cleanly without opening a PR.

Also update `test/validate-prompts.py` to add `"minordomo-librarian"` to `VALID_JOB_NAMES` and `"minordomo-librarian/"` to `REPO_DIRS`. Update `docs/GETTING_AROUND.md` to include the new `minordomo-librarian/` directory in the repository structure section and add the Librarian to the capabilities table. Update `docs/agent-workflow-spec.md` to include a Librarian section describing the capability.

### Acceptance Criteria

- `minordomo-librarian/Jenkinsfile` exists with:
  - A daily cron trigger (`H H * * *`)
  - `CLAUDE_CODE_OAUTH_TOKEN` and `GH_APP` credentials bound
  - `source shared/setup-env.sh` and `source shared/setup-claude.sh` called before Claude
  - Claude invoked with `minordomo-librarian/system-prompt.md` as the prompt
  - Token usage reported via `shared/report-token-usage.py`
  - `shared/check-run-errors.py` used to detect agent-reported errors and set build result
  - A `post { failure { notifyFailure() } }` block
- `minordomo-librarian/system-prompt.md` exists and instructs the agent to implement the 4-step flow described above
- `test/validate-prompts.py` has `"minordomo-librarian"` in `VALID_JOB_NAMES` and `"minordomo-librarian/"` in `REPO_DIRS`
- `docs/GETTING_AROUND.md` lists `minordomo-librarian/` with `Jenkinsfile` and `system-prompt.md` entries in the repository structure section; capabilities table includes a Librarian row
- `docs/agent-workflow-spec.md` includes a Librarian capability section
- `make test` passes

---

## Stage 2: Suggestion-writing system

### Description

Update the planning and worker agent system prompts to instruct agents to write suggestion files to `docs/suggestions/` when working on minordomo issues. Suggestion files describe documentation improvements, gotchas, or corrections the agent noticed during its run; the Librarian integrates them on its next daily pass.

Note: `docs/suggestions/.gitkeep` was already created in Stage 1 (the Librarian system prompt references this directory, and the validate-prompts.py path checker requires it to exist on disk). Update `minordomo-plan/system-prompt.md` and `minordomo-step/system-prompt.md` to include a "Suggestion Writing" section that:
- Explains when to write a suggestion (noticed a documentation gap, correction, or gotcha relevant to the minordomo pipeline)
- Specifies the file naming convention: `suggestion-<beads-task-id>-<brief-slug>.md`
- Specifies the file format: Markdown, starting with a one-line summary of what to document, then a body with the suggested content and the target document(s) where it belongs
- Notes this only applies when working on minordomo issues (the `docs/suggestions/` path is in the minordomo repo)
- Notes that suggestions land on `main` via the normal PR flow and the Librarian integrates them on its next run

### Acceptance Criteria

- `minordomo-plan/system-prompt.md` includes a suggestion-writing section with: when to write, naming convention (`suggestion-<beads-task-id>-<slug>.md`), file format, and scope note (minordomo issues only)
- `minordomo-step/system-prompt.md` includes the same suggestion-writing section
- Both system prompts reference `docs/suggestions/` as a path (so `validate-prompts.py` verifies it exists on disk)
- `make test` passes

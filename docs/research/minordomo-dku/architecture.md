# Research: Spec Evolution - Worker Spec Update Path

## GitHub Issue
https://github.com/wcjordan/minordomo/issues/209

## Goal
Make spec-update behavior an explicit, documented, and tested part of the worker's contract.

## Key Files
- `minordomo-step/system-prompt.md` — worker agent prompt (primary change target)
- `test/validate-prompts.py` — validates paths and job names in system-prompt.md files
- `test/bats/` — bats unit tests for shared shell scripts
- `test/dry-run.sh` — smoke test for the setup chain

## Current State of Worker Prompt

### Step 3 (Implement the Stage) currently says:
> "If you discover something that requires updating the spec doc, update it and include it in the commit"

This is the only mention of spec updates. It's implicit and doesn't:
- State what file to update (the EPIC_KEY path)
- Ask the worker to record what changed
- Guide the PR description

### Step 5 (Commit and Push) currently says:
> "Commit all changes (including any spec doc updates) to the task/$BEADS_TASK_ID branch and push."

Good - confirms spec doc should be included in commit.

### Step 6 (Open PR) currently says:
> `--body "<summary of what was implemented, acceptance criteria met, any spec doc changes>"`

The "any spec doc changes" hint exists but isn't explicit enough — no instruction to add a dedicated section.

## What Needs to Change

### Worker Prompt Changes
1. Step 3: Add explicit instruction naming the spec doc path `docs/planning/${EPIC_KEY}-spec.md`, describe what kinds of changes warrant an update, and instruct the worker to note what changed for inclusion in the PR
2. Step 6: Add explicit instruction to include a "Spec Changes" section in the PR body when the spec doc was updated, summarizing what changed and why

### Test/Validation Changes
- Extend `test/validate-prompts.py` to check the worker system prompt contains required spec-update language
- This validates the spec-update path is properly documented in the worker's instructions

## Why validate-prompts.py is the Right Test Vehicle
The worker is an AI agent — its "behavior" is determined entirely by its system prompt. The testable assertion is "the system prompt contains the right instructions." `validate-prompts.py` already validates prompt content for structural correctness; extending it to check for required spec-update language is the natural fit.

A bats test that exercises git behavior would test git (already well-tested), not the spec-update path specifically. The prompt-content check directly validates the acceptance criteria.

## Spec Doc Path Pattern
Worker derives EPIC_KEY from FEATURE_BRANCH:
```bash
EPIC_KEY="${FEATURE_BRANCH#feature/}"
spec_doc_path="docs/planning/${EPIC_KEY}-spec.md"
```
The explicit spec-update instruction in Step 3 should use the same `${EPIC_KEY}` pattern so the worker knows the exact file to update.

# PR Tweak Workflow — Webhook-Triggered Worker for Review Feedback

Plan for letting a marked PR comment trigger a worker that addresses the feedback directly, without resetting the beads task or re-running a stage from scratch.

---

## Motivation

Once a worker opens a task PR (`task/<beads-id>` → `feature/<epic>`), nothing in the pipeline reacts to review comments. Majordomo's polling only checks merge state (`shared/check-pr-merged.sh`); `shared/sweep-stale-tasks.sh` explicitly skips tasks with an open PR. The only existing human-feedback loop — `needs-input` — is issue-level, resets the beads task to `open`, and causes a full from-scratch re-run on a fresh branch. There is no code path anywhere in `shared/` today that reads a PR comment or replies to one.

Today, addressing review feedback mid-PR means the human either lives with it until merge or launches an agent locally. The goal is a marked PR comment (e.g. `/tweak fix the off-by-one in X`) automatically spinning up a worker that pushes a small, independently reviewable fix — no local agent, no beads reset, no full stage re-run.

---

## Architecture Overview

```
Human comments "/tweak fix the off-by-one in X" on the task/beads-123 PR
        │
        ▼
GitHub issue_comment webhook ──▶ Jenkins (existing GH-webhook-trigger plugin)
        │
        ▼
new job: minordomo-tweak
   Stage "Validate Trigger" (shared/validate-tweak-trigger.sh):
     - comment author ∈ allowed_gh_users?            else abort, no trace
     - comment body contains the marker (/tweak)?     else abort
     - PR head branch matches task/<beads-id>?        else abort (only react to worker-owned PRs)
     - extract BEADS_TASK_ID from the head branch name
        │
        ▼
   Stage "Worker" (reuses shared/agent-pipeline.Jenkinsfile machinery, AGENT_MODE=tweak):
     - shared/bootstrap.sh tweak → setup-env.sh, setup-claude.sh,
       setup-workspace.sh tweak   (new mode)
         - checkout task/<beads-id>-tweak if it exists remotely (resume),
           else create it from the current tip of task/<beads-id>
     - claude -p minordomo-tweak/system-prompt.md   (new prompt)
         - reads the triggering comment (+ any other unaddressed /tweak
           comments on the PR)
         - makes the change, runs tests, commits, pushes to
           task/<beads-id>-tweak
         - opens task/<beads-id>-tweak → task/<beads-id> PR if it doesn't
           exist yet, else just pushes more commits
         - replies on the original comment thread linking to the tweak PR
         - never touches beads task status
     - existing token-usage / error-checking / Discord-notify stages reused as-is
```

Human merge sequence (unchanged automation, just an added step): review and merge the small tweak PR into `task/<beads-id>` → the original `task/<beads-id>` → `feature/<epic>` PR now includes the fix → merge that when ready, exactly as today.

### Why this shape

- **Real-time webhook, not polling.** Majordomo's poll loop is scoped to merge-state checks; teaching it to also diff PR comment history adds latency and complexity for something a webhook does natively. The Jenkins-side plugin for building off GH webhooks is already used elsewhere; this repo just doesn't have a job wired to it yet.
- **Explicit marker (`/tweak`), not any-comment or a label.** Keeps ordinary review discussion from accidentally triggering a run. A PR label was considered but batches per-round rather than per-request and adds a manual toggle step; a marker keeps the trigger inline with the actual feedback.
- **Author allowlist reused from `shared/config.yaml`'s `allowed_gh_users`.** The webhook makes anyone who can comment on a PR a potential trigger for agent execution in CI infra — that must be checked before any credential use or Claude invocation, not left to repo-level access control alone. Reusing the existing list (already the trust boundary for whose GH issues Majordomo ingests) avoids a second allowlist to maintain.
- **One reused branch per round, not one per comment.** `task/<beads-id>-tweak` is created once and pushed to across an arbitrary number of `/tweak` comments in the same round, rather than a fresh stacked branch per comment. This keeps `shared/check-pr-merged.sh` (watches only `task/<beads-id>` → `feature/<epic>`) and `shared/check-open-task-prs.sh` (counts only PRs targeting the feature branch) correct with **no changes required** — the tweak PR is invisible to both until its commits land in `task/<beads-id>` via a human merge.
- **No new beads task.** The Stage task is already `in_progress` with an open PR; a tweak round is more work against that same task, not a new unit of tracked work.

---

## Component Changes

- **`shared/validate-tweak-trigger.sh`** (new) — the three checks above (author allowlist, marker present, head branch matches `task/<beads-id>`). Non-zero exit aborts the job before any Claude invocation or credential use. Keeps deterministic logic out of the Jenkinsfile/system-prompt, per this repo's existing convention of shared, testable scripts.
- **`shared/setup-workspace.sh`** — add a `tweak` mode alongside `worker`/`planning`. Base = `task/<beads-id>` (must already exist remotely — hard error if not, since a tweak requires a prior worker PR). Target = `task/<beads-id>-tweak`, resumed if it exists remotely, else branched from `task/<beads-id>`'s current tip (not the feature branch).
- **`shared/bootstrap.sh`** — accept `tweak` as a valid mode, routing to `setup-workspace.sh tweak`.
- **`minordomo-tweak/system-prompt.md`** (new) — mirrors `minordomo-step/system-prompt.md`'s scoping/testing/commit conventions, scoped to just the requested tweak(s). Instructions cover: reading the comment(s), replying with a link to the tweak PR (`gh pr comment` for a general reply; a threaded reply to a specific review comment needs `gh api repos/.../pulls/.../comments/<id>/replies`), and a needs-input-style escape hatch if the request is ambiguous. Never touches beads task status.
- **`minordomo-tweak/Jenkinsfile`** (new) — parameterized by the webhook plugin's extracted variables (PR number, repo, comment body, comment author, comment id). Runs the "Validate Trigger" stage, then delegates to `shared/agent-pipeline.Jenkinsfile` with `AGENT_MODE='tweak'`.
- **Concurrency** — two `/tweak` comments landing close together on the same PR must not race to create/push `task/<beads-id>-tweak` concurrently. Use a `lock()` (Lockable Resources) keyed by the beads ID around the workspace/push steps in `minordomo-tweak/Jenkinsfile`.
- **Docs** — a "PR Tweak Workflow" section in `docs/WORKFLOWS.md` (branch model + human merge sequence), a row in `docs/GETTING_AROUND.md`'s capability table, and a cross-reference from the "Partial / Silent Failure" note in `docs/FUTURE_WORK.md` (that note describes a close-and-reopen loop this feature reduces reliance on, not replaces).
- **Tests** — bats coverage for `shared/validate-tweak-trigger.sh` and the new `setup-workspace.sh tweak` branch logic, following existing patterns in `test/bats/`.

No changes needed to `shared/check-pr-merged.sh`, `shared/check-open-task-prs.sh`, `shared/sweep-stale-tasks.sh`, or beads task lifecycle logic — see "Why this shape" above.

---

## Suggested Delivery Breakdown

1. **Trigger validation** — `shared/validate-tweak-trigger.sh` + bats tests, exercised standalone with synthetic webhook-payload JSON before any Jenkins wiring exists.
2. **Workspace branch logic** — `setup-workspace.sh tweak` mode + `bootstrap.sh` routing + bats tests.
3. **Tweak worker prompt and job** — `minordomo-tweak/system-prompt.md`, `minordomo-tweak/Jenkinsfile` (built and manually triggered via `buildWithParameters` first, webhook wired last), concurrency lock.
4. **Docs** — `WORKFLOWS.md`, `GETTING_AROUND.md`, `FUTURE_WORK.md` cross-reference.

---

## Open Questions

| Question | Why it matters |
|---|---|
| Which Jenkins plugin/config provides the "build from GH webhook" mechanism already used elsewhere, and is there an example job to mirror? | This repo has no existing webhook-triggered job. The plugin's config lives in Jenkins (and possibly another repo) outside this repo — needed to write `minordomo-tweak/Jenkinsfile`'s trigger block and parameter extraction correctly. |
| Repo-level or org-level webhook? `issue_comment` only, or also `pull_request_review` / `pull_request_review_comment`? | Determines whether `/tweak` can appear in a line-comment during a formal review, not just a general PR comment, and how `validate-tweak-trigger.sh` needs to parse the payload. |
| If `task/<beads-id>` moves (human pushes directly, or a prior tweak round merges) while `task/<beads-id>-tweak` still has unmerged commits, does the worker attempt a rebase/merge automatically, or flag it back to the human? | Affects how much conflict-resolution logic the tweak worker needs and whether a failed auto-rebase should fall back to a needs-input-style comment instead of a broken push. |

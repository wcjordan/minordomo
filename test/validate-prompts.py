#!/usr/bin/env python3
"""Validate static file paths, Jenkins job names, and required spec-update phrases in all system-prompt.md files."""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent

# Top-level dirs that live in this repo — paths starting with these must exist on disk
REPO_DIRS = (
    "majordomo/",
    "shared/",
    "minordomo-plan/",
    "minordomo-step/",
    "minordomo-librarian/",
    "minordomo-container-builder/",
    "docs/",
)

# Current Jenkins job names; flag anything else found in /job/<name>/ patterns
VALID_JOB_NAMES = {
    "majordomo",
    "minordomo-plan",
    "minordomo-step",
    "minordomo-librarian",
    "minordomo-container-builder",
}

# Required spec-update phrases in the worker system prompt
WORKER_PROMPT = "minordomo-step/system-prompt.md"
REQUIRED_SPEC_UPDATE_PHRASES = [
    "docs/planning/",
    "Spec Changes",
    "spec_updated",
]


def check_prompt(path: Path) -> list[str]:
    errors = []
    content = path.read_text()
    rel = path.relative_to(REPO_ROOT)

    # Static path check: single-backtick spans only (avoids code block noise)
    for m in re.finditer(r"`([^`\n]+)`", content):
        candidate = m.group(1)
        # Skip: shell variables, angle-bracket placeholders, spaces, protocols, or Jira keys (parameterized examples)
        if "$" in candidate or "<" in candidate or " " in candidate or "://" in candidate:
            continue
        if re.search(r"[A-Z]+-\d+", candidate):
            continue
        if "/" not in candidate:
            continue
        for prefix in REPO_DIRS:
            if candidate.startswith(prefix):
                full = REPO_ROOT / candidate
                if not full.exists():
                    errors.append(f"{rel}: path does not exist: {candidate!r}")
                break

    # Job name check: scan all text for /job/<name>/ (catches code blocks too)
    for m in re.finditer(r"/job/([a-z][a-z0-9-]*)/", content):
        name = m.group(1)
        if name not in VALID_JOB_NAMES:
            errors.append(f"{rel}: unknown Jenkins job name: {name!r}")

    # Spec-update phrase check for worker system prompt
    if str(rel) == WORKER_PROMPT:
        for phrase in REQUIRED_SPEC_UPDATE_PHRASES:
            if phrase not in content:
                errors.append(f"{rel}: missing required spec-update phrase: {phrase!r}")

    return errors


def main() -> None:
    prompts = sorted(REPO_ROOT.glob("*/system-prompt.md"))
    if not prompts:
        print("ERROR: no system-prompt.md files found", file=sys.stderr)
        sys.exit(1)

    errors: list[str] = []
    for p in prompts:
        errors.extend(check_prompt(p))

    if errors:
        for e in errors:
            print(f"ERROR: {e}")
        sys.exit(1)

    print(f"OK: checked {len(prompts)} prompt(s), no issues found")


if __name__ == "__main__":
    main()

# Research: Update `bd bootstrap` calls to `bd bootstrap -- --silent`

## Problem
`bd bootstrap` produces verbose progress output (chunk download progress with ANSI escape sequences) that clutters CI logs.

## Solution
Replace all `bd bootstrap` calls with `bd bootstrap -- --silent` to suppress this noisy output.

## Affected Files

| File | Line | Current | Notes |
|------|------|---------|-------|
| `majordomo/Jenkinsfile` | 59 | `bd bootstrap` | Majordomo main bootstrap |
| `majordomo/Jenkinsfile` | 155 | `bd bootstrap` | Majordomo secondary bootstrap |
| `shared/setup-workspace.sh` | 21 | `bd bootstrap` | Shared worker/planner bootstrap script |
| `shared/agent-pipeline.Jenkinsfile` | 153 | `bd bootstrap` | Agent pipeline bootstrap |
| `minordomo-sweep/Jenkinsfile` | 57 | `bd bootstrap && bd dolt pull` | Sweep pipeline bootstrap |

Total: 5 occurrences across 4 files.

## Context
Each occurrence is followed by `bd dolt show` and `bd dolt pull` (or just `bd dolt pull` for the sweep). The `--silent` flag is passed after `--` to distinguish it from `bootstrap` subcommand flags.

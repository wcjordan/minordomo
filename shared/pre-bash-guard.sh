#!/usr/bin/env bash
# Secondary safety check before each Bash tool invocation.
# Primary control is the allow/deny list in shared/agent-settings.json.
# This hook provides defence-in-depth for patterns that glob matching may miss.
#
# The generated section (between BEGIN/END markers) is maintained by shared/generate-safety-rules.sh.
# Run that script after editing shared/safety-rules.yaml; do not edit the generated section directly.
#
# Exits 0 to allow, 1 to block. Reason is written to stderr.
# Fails open on JSON parse errors so a buggy hook never silently blocks commands.

set -uo pipefail

# Read all of stdin before doing anything else, then extract the command.
# Claude Code passes tool input as JSON: {"tool_input": {"command": "..."}, ...}
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cmd = data.get('tool_input', {}).get('command') or data.get('command', '')
    print(cmd)
except Exception:
    pass  # fail open
" 2>/dev/null) || true

block() {
    echo "pre-bash-guard: BLOCKED — $1" >&2
    exit 1
}

matches() {
    echo "$COMMAND" | grep -qE "$1"
}

# BEGIN GENERATED SECTION - do not edit manually, run shared/generate-safety-rules.sh
if matches 'git[[:space:]]+push[[:space:]]' && \
   matches '(--force\b|-f[[:space:]])'; then
    block "force push not allowed"
fi

if matches 'git\s+commit\s+.*--no-verify'; then
    block "git commit --no-verify not allowed"
fi

if matches '\bgit\s+rebase\b'; then
    block "git rebase not allowed"
fi

if matches '(^|[;&|[:space:]])sudo[[:space:]]'; then
    block "sudo not allowed"
fi

if matches '\brm\b' && \
   matches '\-[a-zA-Z]*[rR][a-zA-Z]*' && \
   matches '[[:space:]]/([[:space:]]|$|bin|boot|dev|etc|home|lib|lib64|opt|proc|root|run|sbin|srv|sys|tmp|usr|var)'; then
    block "recursive rm on system paths not allowed"
fi

if matches '169\.254\.169\.254'; then
    block "access to AWS IMDS endpoint not allowed"
fi

if matches 'metadata\.google\.internal'; then
    block "access to GCP metadata endpoint not allowed"
fi

if matches '(^|[;&|[:space:]])(mkfs|fdisk|diskutil)([.[:space:]]|$)'; then
    block "disk manipulation not allowed"
fi

if matches '(^|[;&|[:space:]])(shutdown|reboot)([[:space:]]|$)'; then
    block "shutdown/reboot not allowed"
fi

if matches '(^|[;&|[:space:]])(nvram|csrutil|launchctl|systemsetup|networksetup)([[:space:]]|$)'; then
    block "macOS system management not allowed"
fi

if matches '\bbrew[[:space:]]+(install|i)\b'; then
    block "brew install not allowed"
fi

if matches '\bnpm[[:space:]]+(install|i)\b' && \
   matches '(^|[[:space:]])(-g|--global)([[:space:]]|$)'; then
    block "npm global install not allowed"
fi

# END GENERATED SECTION

# --- hardcoded guard-only rules below ---
# These patterns are defence-in-depth for shell injection and cannot be expressed
# as simple deny-glob entries. Do not move them to safety-rules.yaml.

# curl or wget output piped to a shell interpreter
if matches '(curl|wget)\s.+\|\s*(bash|sh|python3?|perl|ruby)\b'; then
    block "piping remote content to a shell interpreter not allowed"
fi

# Process substitution feeding a shell interpreter: bash <(curl ...)
if matches '\b(bash|sh)\s+<\('; then
    block "process substitution shell execution not allowed"
fi

# Dynamic eval with variable expansion
if matches '\beval\s+.*\$'; then
    block "dynamic eval not allowed"
fi

exit 0

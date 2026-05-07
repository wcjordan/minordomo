#!/usr/bin/env bash
# Secondary safety check before each Bash tool invocation.
# Primary control is the allow/deny list in majordomo/agent-settings.json.
# This hook provides defence-in-depth for patterns that glob matching may miss.
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

# Force push: matches --force or -f (with or without remote specified first)
# Two separate checks because the space before --force may have been consumed by push\s+
if matches 'git[[:space:]]+push[[:space:]]' && matches '(--force\b|-f[[:space:]])'; then
    block "force push not allowed"
fi

# Bypass commit hooks
if matches 'git\s+commit\s+.*--no-verify'; then
    block "git commit --no-verify not allowed"
fi

# Rebase (any form)
if matches '\bgit\s+rebase\b'; then
    block "git rebase not allowed"
fi

# sudo
if matches '(^|[;&|[:space:]])sudo[[:space:]]'; then
    block "sudo not allowed"
fi

# Recursive delete targeting root or top-level system paths.
# Catches: rm -rf /, rm -fr /etc, rm -Rf /usr, etc.
if matches '\brm\b' && matches '\-[a-zA-Z]*[rR][a-zA-Z]*' && \
   matches '[[:space:]]/([[:space:]]|$|bin|boot|dev|etc|home|lib|lib64|opt|proc|root|run|sbin|srv|sys|tmp|usr|var)'; then
    block "recursive rm on system path not allowed"
fi

# Cloud instance metadata endpoints (AWS IMDS, GCP metadata server)
if matches '169\.254\.169\.254'; then
    block "access to IMDS metadata endpoint not allowed"
fi
if echo "$COMMAND" | grep -qF 'metadata.google.internal'; then
    block "access to GCP metadata endpoint not allowed"
fi

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

# System-destructive single-word commands
if matches '\b(mkfs|fdisk|diskutil|shutdown|reboot|nvram|csrutil|launchctl|systemsetup|networksetup)\b'; then
    block "system-destructive command not allowed"
fi

# Package manager global installs
if matches '\bbrew\s+install\b'; then
    block "brew install not allowed"
fi
if matches '\bnpm\s+install\s+(.*\s)?-g\b'; then
    block "npm install -g not allowed"
fi

exit 0

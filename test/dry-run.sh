#!/usr/bin/env bash
# Local smoke test: exercises the full setup chain without any external accounts.
# Run from anywhere; it navigates to the repo root automatically.
# Prereqs: git, python3, pyyaml (pip install pyyaml)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  OK  $1"; }
fail() { echo "  FAIL $1"; exit 1; }

# ---------------------------------------------------------------------------
# Fixture: local bare git repo acting as the GitHub remote
# ---------------------------------------------------------------------------
REMOTE="$WORK/remote.git"
git init --bare "$REMOTE" -q
INIT="$WORK/init"
git clone "$REMOTE" "$INIT" -q
git -C "$INIT" -c user.email="t@t.com" -c user.name="T" \
    commit --allow-empty -m "Initial commit" -q
git -C "$INIT" push origin HEAD:main -q
git -C "$INIT" push origin HEAD:blocked_beads -q

# ---------------------------------------------------------------------------
# Mock binaries
# ---------------------------------------------------------------------------
MOCKS="$WORK/mocks"
mkdir -p "$MOCKS"
export REMOTE REPO_ROOT

cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "auth setup-git") exit 0 ;;
  "repo clone") git clone "$REMOTE" "$4" -q ;;
  "issue view") echo '{"comments":[{"body":"Jira Epic: MDOMO-1"}]}' ;;
  *) echo "mock gh: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCKS/gh"

CLAUDE_CALLS="$WORK/claude-calls.log"
cat > "$MOCKS/claude" << MOCK
#!/usr/bin/env bash
echo "\$@" >> "$CLAUDE_CALLS"
exit 0
MOCK
chmod +x "$MOCKS/claude"

cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  "dolt") exit 0 ;;
  "stats") exit 0 ;;
  "show")
    TASK_ID="$2"
    case "$TASK_ID" in
      "minordomo-abc")
        echo '[{"id":"minordomo-abc","title":"Plan: Test Task","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/54"}]'
        ;;
      *) echo "[]" ;;
    esac
    ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCKS/bd"

export PATH="$MOCKS:$PATH"

# ---------------------------------------------------------------------------
# Fake credentials (mimic Jenkins credential bindings)
# ---------------------------------------------------------------------------
export ROOT_DOMAIN="test.example.com"
export GH_APP_PSW="gh-fake-token"
export JIRA_ACCT_PSW="jira-fake-token"
export JIRA_ACCT_USR="test@example.com"
export JIRA_CLOUD_ID="test-cloud-id"
export BEADS_TASK_ID="minordomo-abc"
export BEADS_DOLT_SERVER_USER="minordomo"
export HOME="$WORK/home"
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# Step 1: setup-env.sh
# ---------------------------------------------------------------------------
echo "--- setup-env.sh ---"
cd "$REPO_ROOT"
source shared/setup-env.sh
[ -n "$DOMAIN_ROOT" ] && pass "DOMAIN_ROOT=$DOMAIN_ROOT" || fail "DOMAIN_ROOT not set"
[ -n "$JIRA_URL" ]    && pass "JIRA_URL=$JIRA_URL"       || fail "JIRA_URL not set"
[ -n "$GH_TOKEN" ]    && pass "GH_TOKEN set"             || fail "GH_TOKEN not set"
[ -n "$BASE_BRANCH" ] && pass "BASE_BRANCH=$BASE_BRANCH" || fail "BASE_BRANCH not set"

# ---------------------------------------------------------------------------
# Step 2: setup-claude.sh
# ---------------------------------------------------------------------------
echo "--- setup-claude.sh ---"
source shared/setup-claude.sh
[ -f "$HOME/.claude/settings.json" ] \
    && pass "settings.json created" || fail "settings.json missing"
[ -f "$HOME/.claude/hooks/pre-bash-guard.sh" ] \
    && pass "pre-bash-guard.sh installed" || fail "pre-bash-guard.sh missing"
grep -q "mcp add atlassian" "$CLAUDE_CALLS" \
    && pass "claude mcp add atlassian called" || fail "claude mcp add atlassian not called"

# ---------------------------------------------------------------------------
# Step 3: setup-workspace.sh (planning mode)
# ---------------------------------------------------------------------------
echo "--- setup-workspace.sh (planning) ---"
WSDIR="$WORK/workspace"
mkdir -p "$WSDIR/shared"
cp "$REPO_ROOT/shared/config.yaml" "$WSDIR/shared/config.yaml"
cd "$WSDIR"

source "$REPO_ROOT/shared/setup-workspace.sh" planning
[ "$REPO" = "minordomo" ] \
    && pass "REPO=$REPO"               || fail "unexpected REPO: $REPO"
[ "$EPIC_KEY" = "MDOMO-1" ] \
    && pass "EPIC_KEY=$EPIC_KEY"       || fail "unexpected EPIC_KEY: $EPIC_KEY"
[[ "$(git branch --show-current)" == task/* ]] \
    && pass "on task branch"           || fail "not on task branch: $(git branch --show-current)"

echo ""
echo "All checks passed."

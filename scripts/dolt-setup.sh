#!/usr/bin/env bash
# Source this file to get the dolt_setup function.
#
# dolt_setup: starts a kubectl port-forward to the in-cluster Dolt server,
# exports BEADS_DOLT_SERVER_* env vars, and registers an EXIT trap to tear
# it down.  Safe to call when already in Jenkins (no-op) or when
# BEADS_DOLT_SERVER_HOST is already set (skips to avoid double port-forward).
#
# Usage (in a script or git hook):
#   . "$(git rev-parse --show-toplevel)/scripts/dolt-setup.sh"
#   dolt_setup

dolt_setup() {
  # In Jenkins, Dolt is reachable via k8s DNS — nothing to do.
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    return 0
  fi

  # Already configured (e.g. called twice, or env pre-set externally).
  if [[ -n "${BEADS_DOLT_SERVER_HOST:-}" ]]; then
    return 0
  fi

  local namespace=minordomo
  local local_port=3306
  local connect_timeout=10  # seconds before giving up on the port-forward

  BEADS_DOLT_PASSWORD=$(kubectl get secret dolt-minordomo-password \
    -n "$namespace" -o jsonpath='{.data.text}' | base64 -d) || {
    echo >&2 "dolt-setup: kubectl failed — skipping Dolt port-forward"
    return 0
  }
  export BEADS_DOLT_PASSWORD
  export BEADS_DOLT_SERVER_HOST=127.0.0.1
  export BEADS_DOLT_SERVER_PORT=$local_port
  export BEADS_DOLT_SERVER_USER=minordomo

  kubectl port-forward svc/dolt-server "${local_port}:3306" -n "$namespace" \
    >/tmp/dolt-forward.log 2>&1 &
  local pf_pid=$!
  trap 'kill "$pf_pid" 2>/dev/null; wait "$pf_pid" 2>/dev/null || true' EXIT

  local deadline=$(( $(date +%s) + connect_timeout ))
  until (echo >/dev/tcp/127.0.0.1/"$local_port") 2>/dev/null; do
    if (( $(date +%s) >= deadline )); then
      echo >&2 "dolt-setup: port-forward did not become ready within ${connect_timeout}s — skipping"
      kill "$pf_pid" 2>/dev/null || true
      unset BEADS_DOLT_SERVER_HOST BEADS_DOLT_SERVER_PORT BEADS_DOLT_SERVER_USER BEADS_DOLT_PASSWORD
      return 0
    fi
    sleep 0.1
  done
}

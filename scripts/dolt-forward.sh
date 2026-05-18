#!/usr/bin/env bash
# Port-forward the in-cluster Dolt server for local bd use.
#
# Usage:
#   scripts/dolt-forward.sh bd list --status=open   # one-shot: run command, then tear down
#   scripts/dolt-forward.sh                         # interactive: subshell with env pre-set

set -euo pipefail

NAMESPACE=minordomo
LOCAL_PORT=3306

export BEADS_DOLT_PASSWORD
BEADS_DOLT_PASSWORD=$(kubectl get secret dolt-minordomo-password \
    -n "$NAMESPACE" -o jsonpath='{.data.text}' | base64 -d)
export BEADS_DOLT_SERVER_HOST=127.0.0.1
export BEADS_DOLT_SERVER_PORT=$LOCAL_PORT
export BEADS_DOLT_SERVER_USER=minordomo

kubectl port-forward svc/dolt-server "${LOCAL_PORT}:3306" -n "$NAMESPACE" \
    >/tmp/dolt-forward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null; wait "$PF_PID" 2>/dev/null || true' EXIT

until (echo >/dev/tcp/127.0.0.1/"$LOCAL_PORT") 2>/dev/null; do
    sleep 0.1
done

if [[ $# -gt 0 ]]; then
    "$@"
else
    echo "Dolt port-forward active on localhost:${LOCAL_PORT}"
    echo "Type 'exit' to stop."
    exec "$SHELL"
fi

#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
suspended=$(flux get kustomization 40-inference --no-header | awk '{print $3}')
[ "$suspended" = "False" ] || fail "40-inference is still suspended"
kubectl -n inference rollout status deploy/ollama --timeout=120s >/dev/null 2>&1 || fail "ollama is not rolled out"
pass "ollama pulls and serves again"

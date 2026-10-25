#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
suspended=$(flux get kustomization 40-inference --no-header | awk '{print $3}')
[ "$suspended" = "False" ] || fail "40-inference is still suspended"
[ "$(kubectl -n inference get deploy vllm -o jsonpath='{.status.readyReplicas}')" -ge 1 ] 2>/dev/null || fail "vllm has no ready replicas"
pass "vllm serving, reconciliation resumed"

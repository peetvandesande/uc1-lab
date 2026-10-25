#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl wait node uc1-worker-2 --for=condition=Ready --timeout=10s >/dev/null 2>&1 || fail "uc1-worker-2 is not Ready"
pass "uc1-worker-2 is Ready"
[ "$(kubectl -n inference get deploy vllm -o jsonpath='{.status.readyReplicas}')" -ge 1 ] || fail "vllm has no ready replicas"
pass "vllm is serving again"

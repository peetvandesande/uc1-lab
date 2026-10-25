#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl get runtimeclass nvidia >/dev/null 2>&1 || fail "the nvidia RuntimeClass is missing"
kubectl -n inference rollout status deploy/ollama --timeout=180s >/dev/null 2>&1 || fail "ollama is not back"
pass "ollama runs with the nvidia runtime again"

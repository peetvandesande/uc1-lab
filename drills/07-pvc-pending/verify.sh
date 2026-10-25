#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
phase=$(kubectl -n inference get pvc artefact-store -o jsonpath='{.status.phase}' 2>/dev/null || echo gone)
[ "$phase" = "Bound" ] || [ "$phase" = "gone" ] || fail "PVC artefact-store is $phase"
if [ "$phase" = "Bound" ]; then
  kubectl -n inference wait pod artefact-store --for=condition=Ready --timeout=60s >/dev/null 2>&1 || fail "pod is not Running"
fi
pass "artefact-store resolved ($phase)"

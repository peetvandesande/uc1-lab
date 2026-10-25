#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
for n in uc1-cp-1 uc1-cp-2 uc1-cp-3; do
  kubectl wait node $n --for=condition=Ready --timeout=10s >/dev/null 2>&1 || fail "$n is not Ready"
done
kubectl -n default create configmap drill10-write-check --from-literal=ok=true --dry-run=server -o name >/dev/null 2>&1 || fail "API writes still failing"
pass "quorum restored, API writes work"

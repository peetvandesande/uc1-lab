#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl get validatingwebhookconfiguration compliance-gate >/dev/null 2>&1 && fail "compliance-gate still exists"
kubectl -n inference auth can-i create pods >/dev/null 2>&1 || true
kubectl -n inference run drill09-check --image=busybox:1.37 --restart=Never --command --dry-run=server -- true >/dev/null 2>&1 || fail "creates into inference still fail"
pass "admission works again"

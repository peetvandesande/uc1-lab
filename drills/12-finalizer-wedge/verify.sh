#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference get modeldeployment drill-demo >/dev/null 2>&1 && fail "drill-demo still exists"
[ "$(kubectl -n uc1-operator-system get deploy uc1-operator-controller-manager -o jsonpath='{.spec.replicas}')" -ge 1 ] || fail "the operator is still scaled to 0"
pass "drill-demo gone and the operator is back"

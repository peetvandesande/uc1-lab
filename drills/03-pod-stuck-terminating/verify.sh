#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
if kubectl get ns drill-tenant >/dev/null 2>&1; then fail "drill-tenant still exists"; fi
pass "drill-tenant is gone"

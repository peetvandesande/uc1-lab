#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl run drill08-check --rm -i --restart=Never --image=busybox:1.37 --command -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 || fail "cluster DNS does not resolve"
pass "cluster DNS resolves"

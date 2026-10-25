#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference get pdb vllm-guard >/dev/null 2>&1 && \
  [ "$(kubectl -n inference get pdb vllm-guard -o jsonpath='{.spec.maxUnavailable}')" = "0" ] && \
  fail "vllm-guard still allows zero disruption"
kubectl get node uc1-worker-2 -o jsonpath='{.spec.unschedulable}' | grep -q true && fail "uc1-worker-2 is still cordoned"
pass "a sane PDB and an uncordoned node"

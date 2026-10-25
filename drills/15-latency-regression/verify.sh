#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference get job drill15-load >/dev/null 2>&1 && \
  [ -z "$(kubectl -n inference get job drill15-load -o jsonpath='{.status.completionTime}')" ] && \
  fail "the load job is still running - observe first, then wait it out (or delete it)"
pass "load gone"
say "worth answering before reading solution.md:"
say " - did VllmRequestQueueHigh fire?"
say " - did KEDA scale vllm, and what un-scaled it?"
say " - which moved first: queue depth, TTFT, or e2e latency?"

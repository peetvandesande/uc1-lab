#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
if kubectl -n inference get deploy embedder >/dev/null 2>&1; then
  fail "embedder still exists - the drill ends with removing it (it can never fit its limit)"
fi
pass "embedder removed"

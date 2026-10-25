#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
for n in uc1-cp-2 uc1-cp-3; do
  id=$(vmid $n)
  say "stopping $n (VMID $id)"
  pm "qm stop $id --skiplock 1"
done
say "injected - see brief.md"

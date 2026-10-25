#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
id=$(vmid uc1-worker-2)
say "stopping uc1-worker-2 (VMID $id) the hard way"
pm "qm stop $id --skiplock 1"
say "injected - see brief.md"

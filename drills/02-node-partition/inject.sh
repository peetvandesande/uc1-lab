#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
id=$(vmid uc1-cp-3)
say "cutting uc1-cp-3's network at the virtual cable (VMID $id)"
pm "qm set $id --net0 \$(qm config $id | sed -n 's/^net0: //p' | sed 's/\$/,link_down=1/')"
say "injected - see brief.md"

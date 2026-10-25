# Drills

Break/fix scenarios, one directory each. The intended loop:

1. Run `./inject.sh` and walk away for a minute.
2. Read `brief.md` - the symptom as a ticket would state it, nothing more.
3. Investigate and fix it as if it were production. No peeking.
4. Run `./verify.sh` until it exits 0, then `../../scripts/verify.sh`
   for the whole platform.
5. Write the RCA (docs/rca-template.md). The writing is part of the drill.
6. Compare with `solution.md` - the fix, the mechanism and the prevention.

The drills assume the full platform is up (`scripts/verify.sh` green) and
SSH access to the Proxmox host as root (override with PROXMOX_TARGET).
Injections are scoped to the lab; nothing touches the rest of the homelab.

| # | Drill | Exercises |
|---|-------|-----------|
| 01 | node-down | unavailable nodes, workload rescheduling |
| 02 | node-partition | NotReady vs down, etcd member health |
| 03 | pod-stuck-terminating | finalizers, forced deletion |
| 04 | crashloop | reading logs backwards from the restart |
| 05 | oomkill | limits, exit 137, right-sizing |
| 06 | image-pull | registries, containerd errors |
| 07 | pvc-pending | storage classes, scheduling on volume affinity |
| 08 | dns-broken | CoreDNS, what "everything is down" really means |
| 09 | webhook-outage | admission webhooks as a cluster-wide SPOF |
| 10 | etcd-quorum | control plane majority, recovery order |
| 11 | flux-drift | suspended reconciliation, drift, GitOps discipline |
| 12 | finalizer-wedge | operator deletion paths, stuck CRs |
| 13 | gpu-runtime | RuntimeClass, device plugin, GPU scheduling |
| 14 | pdb-blocked-drain | PodDisruptionBudgets vs safe node drains |
| 15 | latency-regression | LLM-serving signals, alerts, KEDA scaling |

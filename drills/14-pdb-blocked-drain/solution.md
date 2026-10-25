# What happened

`maxUnavailable: 0` means "no voluntary disruption, ever". Eviction (the
API drain uses) respects PDBs, so the drain retries the same pod
forever. This is working as designed: the PDB is someone's availability
requirement, and the kubelet politely refuses to violate it.

# Diagnosis path

    kubectl drain uc1-worker-2 --ignore-daemonsets --delete-emptydir-data
        # error when evicting pod ... Cannot evict pod as it would violate
        # the pod's disruption budget
    kubectl get pdb -A                        # ALLOWED DISRUPTIONS: 0
    kubectl -n inference describe pdb vllm-guard

# Fix

Make the budget satisfiable instead of forcing the drain: with one vllm
replica, maxUnavailable 0 and any disruption are mutually exclusive, so
either scale up first or set an honest budget:

    kubectl -n inference patch pdb vllm-guard --type=merge -p '{"spec":{"maxUnavailable":1}}'
    kubectl drain uc1-worker-2 --ignore-daemonsets --delete-emptydir-data
    # ... maintenance happens ...
    kubectl uncordon uc1-worker-2
    kubectl -n inference delete pdb vllm-guard    # it was drill clutter

(Note the local-path PVC pods: `--delete-emptydir-data` and node-pinned
volumes make drains of stateful lab pods a conscious decision.)

# Prevention / hardening

- PDBs with maxUnavailable 0 (or minAvailable = replicas) are drain
  deadlocks by construction; audit for them before upgrade windows -
  exactly what module 90's runbook does first.
- Never `--disable-eviction` to bypass a PDB you have not understood;
  that flag converts a safety mechanism into an outage.

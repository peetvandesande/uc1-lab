# What happened

The worker VM was powered off. The kubelet stops heartbeating, the node
goes `NotReady` after ~40s (`node-monitor-grace-period`), and ~5 minutes
later (the default toleration for `node.kubernetes.io/not-ready`) its pods
are marked for eviction. Pods with node-pinned PVCs (local-path!) cannot
reschedule anywhere else and stay Pending.

# Diagnosis path

    kubectl get nodes                        # NotReady
    kubectl describe node uc1-worker-2       # last heartbeat, taints added
    kubectl get pods -A -o wide | grep -v Running
    ssh root@lenora.home qm status <vmid>    # the layer below: VM stopped

# Fix

    ssh root@lenora.home qm start <vmid>

Watch the node come back and the taints clear. Anything stuck Terminating
on the dead node clears when the kubelet reports in.

# Prevention / hardening

- Alert on `up{job="node-exporter"} == 0` or kube-state's node condition
  before users notice.
- Know which workloads are node-pinned by their storage and whether that
  is acceptable (it rarely is in production - this is the local-path
  trade-off on display).

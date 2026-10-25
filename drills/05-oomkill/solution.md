# What happened

The process allocates without bound; the cgroup kills it at the 128Mi
limit. From inside, nothing is logged - the kernel SIGKILLs it. The
evidence lives in the pod status, not the logs.

# Diagnosis path

    kubectl -n inference get pods                     # Restarts climbing, maybe OOMKilled in STATUS
    kubectl -n inference describe pod -l app=embedder # Last State: Terminated, Reason: OOMKilled, Exit Code: 137
    kubectl top pod -l app=embedder -n inference      # watch it climb to the limit

Exit code 137 = 128 + SIGKILL(9). "No errors in the logs" plus 137 is
OOM until proven otherwise.

# Fix

Here the workload is simply broken (unbounded allocation), so the fix is
removal - in the real case you would size the limit from observed usage:

    kubectl -n inference delete deploy embedder

# Prevention / hardening

- Alert on `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`.
- Memory limits are a kill threshold, not a suggestion; set requests from
  a measured baseline and limits with honest headroom.

# What happened

Someone patched the Deployment directly (an argument the server rejects),
and reconciliation had been suspended, so GitOps never put it back. The
container exits at once; kubelet restarts it with exponential backoff.

# Diagnosis path

    kubectl -n inference get pods                       # CrashLoopBackOff, RESTARTS climbing
    kubectl -n inference logs deploy/mock-nim --previous   # the crash, not the current attempt
    kubectl -n inference describe pod -l app.kubernetes.io/name=mock-nim  # Last State: Exit Code
    kubectl -n inference get deploy mock-nim -o yaml    # spot the odd command
    flux get kustomizations                             # 40-inference: Suspended

`--previous` is the habit: the running container's log is empty, the
evidence is in the dead one.

# Fix

    flux resume kustomization 40-inference

Flux reverts the drift from git. (Fixing the command by hand also works -
and is drift again. Resume is the real fix.)

# Prevention / hardening

- Suspended Flux objects are silent risk: the FluxReconciliationErrors
  alert does not cover suspension. `flux get all -A | grep -i suspend`
  belongs in the incident checklist.
- kubectl patch on managed objects is how prod drifts. Prefer PRs.

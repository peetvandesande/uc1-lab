# What happened

The pod asks for `runtimeClassName: nvidia`; the RuntimeClass object was
deleted. The kubelet cannot even start creating the sandbox and the pod
sits in Pending/ContainerCreating with an event, not a log.

The stack under a GPU pod, from top to bottom - any layer can take it
down, each with a distinct signature:

    pod (nvidia.com/gpu resource)   -> Pending: Insufficient nvidia.com/gpu (device plugin)
    runtimeClassName: nvidia        -> RuntimeClass not found (this drill)
    containerd nvidia runtime       -> OCI runtime create failed (toolkit extension)
    kernel driver / modules         -> nvidia-smi fails inside (machine config, extension)
    the PCI device                  -> nothing in lspci (vfio/passthrough, Proxmox)

# Diagnosis path

    kubectl -n inference describe pod -l app.kubernetes.io/name=ollama
        # Warning FailedCreatePodSandBox / RuntimeClass "nvidia" not found
    kubectl get runtimeclass                  # gone
    flux diff kustomization 30-gpu --path ./modules/30-gpu   # git still has it

# Fix

    flux reconcile kustomization 30-gpu       # restores the RuntimeClass
    kubectl -n inference delete pod -l app.kubernetes.io/name=ollama   # retry now it exists

# Prevention / hardening

- Pruning note: Flux *created* that RuntimeClass, so flux also noticed
  it missing only at the next reconcile (up to 10 minutes). Forcing
  reconciliation is the operator's fast-forward button.
- Learn the five-layer signature list above; GPU tickets rarely say
  which layer, but the error text always does.

# What happened

The PVC names a StorageClass (`fast-ssd`) that does not exist, so no
provisioner ever answers; the claim stays Pending and the pod stays
unschedulable on volume binding, not on resources.

# Diagnosis path

    kubectl -n inference describe pod artefact-store   # Events: unbound immediate PersistentVolumeClaims
    kubectl -n inference describe pvc artefact-store   # waiting for a volume to be created...
                                                       # storageclass.storage.k8s.io "fast-ssd" not found
    kubectl get storageclass                           # local-path (default) is what exists

# Fix

StorageClass is immutable on a PVC - fix means recreate:

    kubectl -n inference delete pod artefact-store
    kubectl -n inference delete pvc artefact-store
    # recreate with storageClassName: local-path (or none, for the default)

(Deleting both and leaving them gone also passes the drill.)

# Prevention / hardening

- A Kyverno policy can restrict storageClassName to classes that exist.
- Know your binding mode: local-path is WaitForFirstConsumer, so a bare
  PVC Pending there is *normal* until a pod wants it - do not chase that
  ghost in the wrong direction.

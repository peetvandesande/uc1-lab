# What happened

The deploy pointed at a tag that exists in nobody's registry (a "hotfix"
image never pushed). kubelet retries the pull with backoff:
ErrImagePull, then ImagePullBackOff. Deleting the old pod turned a
degraded rollout into an outage - the surgeon's first lesson.

# Diagnosis path

    kubectl -n inference get pods                      # ImagePullBackOff
    kubectl -n inference describe pod -l app.kubernetes.io/name=ollama
        # Events: Failed to pull ... registry.uc1.home/ollama/ollama:0.40.11-hotfix not found
    curl -s http://registry.uc1.home/v2/ollama/ollama/tags/list   # what IS there?
    flux get kustomizations                            # suspended, so git did not do this

# Fix

    flux resume kustomization 40-inference    # git truth restores the image

# Prevention / hardening

- Rollouts guard you: the old ReplicaSet keeps serving while the new one
  fails to pull - unless someone deletes the old pod. Do not.
- `kubectl rollout undo` is the fast path when git is not an option.
- Pull errors name the layer that failed (auth vs not-found vs timeout);
  read the words, they are precise.

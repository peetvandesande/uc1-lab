#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: artefact-store
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast-ssd
  resources: {requests: {storage: 5Gi}}
---
apiVersion: v1
kind: Pod
metadata:
  name: artefact-store
  labels: {uc1.home/data-residency: eu}
spec:
  containers:
    - name: store
      image: busybox:1.37
      command: [sleep, infinity]
      resources: {requests: {cpu: 10m, memory: 16Mi}}
      volumeMounts: [{name: data, mountPath: /data}]
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: artefact-store}
YAML
say "injected - see brief.md"

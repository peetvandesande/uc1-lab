#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference apply -f - >/dev/null <<'YAML'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: vllm-guard
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: vllm
YAML
say "injected - now try: kubectl drain uc1-worker-2 --ignore-daemonsets --delete-emptydir-data"

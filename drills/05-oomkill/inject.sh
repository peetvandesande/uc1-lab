#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl -n inference apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embedder
  labels: {uc1.home/data-residency: eu}
spec:
  replicas: 1
  selector: {matchLabels: {app: embedder}}
  template:
    metadata:
      labels: {app: embedder, uc1.home/data-residency: eu}
    spec:
      containers:
        - name: embedder
          image: python:3.13-slim
          command: [python, -c, "x = []\nimport time\nwhile True:\n    x.append(bytearray(10 << 20))\n    time.sleep(0.2)"]
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits: {memory: 128Mi}
YAML
say "injected - see brief.md"

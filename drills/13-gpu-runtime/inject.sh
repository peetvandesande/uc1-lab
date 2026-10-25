#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl delete runtimeclass nvidia >/dev/null
kubectl -n inference delete pod -l app.kubernetes.io/name=ollama --wait=false >/dev/null 2>&1 || true
say "injected - see brief.md"

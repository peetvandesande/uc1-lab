#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
flux suspend kustomization 40-inference >/dev/null
kubectl -n inference set image deploy/ollama ollama=registry.uc1.home/ollama/ollama:0.40.11-hotfix >/dev/null
kubectl -n inference delete pod -l app.kubernetes.io/name=ollama --wait=false >/dev/null 2>&1 || true
say "injected - see brief.md"

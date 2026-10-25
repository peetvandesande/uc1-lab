#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
flux suspend kustomization 40-inference >/dev/null
kubectl -n inference scale deploy vllm --replicas=0 >/dev/null
say "injected - see brief.md"

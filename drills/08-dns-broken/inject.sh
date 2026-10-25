#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
# A plausible bad change: someone "tuned" CoreDNS and broke the Corefile
kubectl -n kube-system get configmap coredns -o yaml > /tmp/uc1-drill08-coredns.yaml
kubectl -n kube-system patch configmap coredns --type=merge -p '{"data":{"Corefile":".:53 {\n    errors\n    forward . 192.0.2.53\n    cache 30\n}\n"}}' >/dev/null
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n inference delete pod -l app.kubernetes.io/name=vllm --wait=false >/dev/null 2>&1 || true
say "injected - see brief.md (a backup of the good ConfigMap is in /tmp, as if from the night before)"

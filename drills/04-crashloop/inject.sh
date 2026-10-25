#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
# Flux is suspended so the drift is yours to find and revert
flux suspend kustomization 40-inference >/dev/null
kubectl -n inference patch deploy mock-nim --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/command",
   "value":["python","-I","/app/server.py","--definitely-not-a-flag"]}]' >/dev/null
say "injected - see brief.md"

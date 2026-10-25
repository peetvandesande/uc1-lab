#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl create ns drill-tenant --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n drill-tenant run sleeper --image=busybox:1.37 --restart=Never -- sleep 3600 >/dev/null
kubectl -n drill-tenant patch pod sleeper -p '{"metadata":{"finalizers":["uc1.home/never-lets-go"]}}' >/dev/null
kubectl delete ns drill-tenant --wait=false >/dev/null
say "injected - see brief.md"

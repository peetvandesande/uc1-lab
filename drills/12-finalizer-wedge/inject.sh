#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl get crd modeldeployments.serving.uc1.home >/dev/null 2>&1 || fail "deploy the operator first (module 50)"
kubectl -n inference apply -f - >/dev/null <<'YAML'
apiVersion: serving.uc1.home/v1alpha1
kind: ModelDeployment
metadata: {name: drill-demo}
spec: {model: drill/demo, engine: mock, replicas: 1}
YAML
# wait for the finalizer, then take the controller away and delete
for i in $(seq 30); do
  kubectl -n inference get modeldeployment drill-demo -o jsonpath='{.metadata.finalizers}' | grep -q finalizer && break
  sleep 2
done
kubectl -n uc1-operator-system scale deploy uc1-operator-controller-manager --replicas=0 >/dev/null
kubectl -n inference delete modeldeployment drill-demo --wait=false >/dev/null
say "injected - see brief.md"

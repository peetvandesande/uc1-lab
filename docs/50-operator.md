# Module 50 - the ModelDeployment operator

Go + kubebuilder. One CRD (`ModelDeployment`), one controller: reconciles
a Deployment, a Service and a ServiceMonitor, owns them (watch the owner
references), guards deletion with a finalizer, reports conditions.
The JD line "Operators, CRDs, controllers, unexpected reconciliation
behaviour" is this directory.

## Build, push, deploy

The workstation's Docker must trust the plain-HTTP registry once:
add `"insecure-registries": ["registry.uc1.home"]` to the Docker daemon
config (colima: `~/.colima/default/colima.yaml` under `docker:`), restart.

```sh
cd operator
make test                                   # envtest: no cluster needed
make docker-build docker-push               # -> registry.uc1.home/uc1-operator:v0.1.0
make install                                # the CRD
make deploy                                 # ns uc1-operator-system
kubectl apply -f config/samples/serving_v1alpha1_modeldeployment.yaml
kubectl -n inference get mdep -w            # watch Ready go True
```

Nodes pull from the registry via the containerd mirror in the machine
config (talos.tf) - that is why image refs say `registry.uc1.home/...`
with no scheme and it still works over HTTP.

## Exercises that teach the most

1. Delete the operator's Deployment behind Flux's back - who notices?
2. `kubectl edit` the owned Service's port; watch the reconciler put it
   back. Then find the field the reconciler does NOT own and drift it.
3. Remove the RBAC for servicemonitors from config/rbac and redeploy:
   reconcile errors in the logs, Degraded conditions - the daily bread
   of operator troubleshooting.
4. Add a validating webhook (`kubebuilder create webhook`) rejecting
   models outside an allowlist; then re-run drill 09 against your own
   webhook.
5. Scale a ModelDeployment while KEDA also targets it and reason about
   the fight.

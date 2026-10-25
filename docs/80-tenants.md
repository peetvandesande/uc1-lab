# Module 80 - tenants, and a three-tier application end to end

"Tenant" is the word this platform uses for what various shops call a
customer, team, project or workspace: **a namespace wearing the
platform's contract**, with its own quota, RBAC, network rules and front
door. Kubernetes has no tenant object - the pattern is an agreement
between namespace-scoped primitives, and this module is that agreement
written down once and then walked through to a working application:

    browser ──TLS──▶ ingress-nginx ──▶ web (nginx)──▶ api (python) ──▶ db (postgres)
                     demo.uc1.home      tier 1         tier 2           tier 3

Everything lives in `tenants/demo/`; this document reads it in order.

## What makes a namespace a tenant

Five pieces, one file each:

| File | Gives the tenant | Worth knowing |
|---|---|---|
| namespace.yaml | identity + posture | `uc1.home/tenant` is the label the Kyverno policies select on - *that* is what subjects a namespace to the platform's rules. PSA `enforce: baseline` blocks the obviously privileged; `warn: restricted` nags towards the ideal. |
| quota.yaml | a slice of the cluster | ResourceQuota caps the total; the LimitRange supplies defaults. `services.loadbalancers: "0"` makes the ingress the only front door - LB addresses are platform property. |
| rbac.yaml | people | RoleBinding to the built-in `admin` ClusterRole: full control inside, nothing outside. The lab has no IdP, so test it with impersonation (commands in the file). |
| networkpolicies.yaml | a traffic contract | default-deny ingress, then exactly the architecture's arrows. Policy follows architecture, never the other way round. |
| ingress.yaml | a front door | one host, certificate from step-ca, web tier only. |

The platform's side of the contract (modules 60/20/15): Kyverno enforces
pinned image tags, resource requests and the `uc1.home/data-residency`
label on every Deployment/StatefulSet in tenant namespaces; Prometheus
may scrape across the deny; certificates issue automatically.

**Onboarding a new tenant is copying `tenants/demo/`**, renaming the
namespace and host, and adding the host name to the CNAME list in
`ansible/tasks/dns.yml` (re-run `ansible-playbook ansible/bootstrap.yml`
to register it - `demo` is already there).

## The application, tier by tier

**db.yaml - the data tier.** PostgreSQL as a StatefulSet with a
volumeClaimTemplate: the pod keeps its storage identity across restarts,
which is the whole point of a StatefulSet. Credentials live in a Secret
that both the db and the api consume (`envFrom`), so there is exactly one
copy. local-path pins the volume to one node - restarting the pod is
fine, but it can only ever come back where its data is (drill 01 shows
the consequence).

**api.yaml - the application tier.** A small Python HTTP server:
`GET /visits`, `POST /visits`, `/healthz` for the probe. Two replicas
behind a ClusterIP Service - stateless, so replicas are free. The one
demo-ism: `pip install psycopg` at container start, to keep the
walkthrough image-build-free; note the readiness probe's generous
`failureThreshold` absorbing that install. A real tenant builds an image
and pushes it to `registry.uc1.home` - module 50's workflow, and the
first exercise below.

**web.yaml - the presentation tier.** Unprivileged nginx (listens on
8080, runs as non-root - PSA-friendly) serving one static page and
proxying `/api/` to the api Service. The browser only ever talks to this
tier; that is what lets the network policy say "nothing else reaches the
api".

Every workload carries `uc1.home/data-residency: eu`, pinned tags and
explicit requests - remove any of them and Kyverno will show you the
contract (last exercise).

## Deploy it

Quick path, straight from the working tree:

```sh
kubectl apply -k tenants/demo
kubectl -n demo get pods -w        # db first, then api (pip install), then web
```

GitOps path - the real onboarding, where a tenant is a folder plus one
Kustomization and arrives by pull request:

```yaml
# clusters/uc1/80-tenant-demo.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: 80-tenant-demo
  namespace: flux-system
spec:
  interval: 10m
  sourceRef: {kind: GitRepository, name: flux-system}
  path: ./tenants/demo
  prune: true
  wait: true
  dependsOn:
    - name: 16-ingress
    - name: 60-policy
```

Commit that file and the tenant is platform-managed: drift reverts,
deletion is `git rm` (prune removes the namespace and everything in it).

## Prove it works

```sh
curl -s https://demo.uc1.home/api/visits | jq                      # [] on first run
curl -s https://demo.uc1.home/api/visits \
  -H 'Content-Type: application/json' -d '{"name":"peet"}'
open https://demo.uc1.home                                          # green padlock, the guestbook
kubectl -n demo get certificate demo-tls                            # Ready=True, issued by step-ca
```

Then prove the *contract* works, which is the actual lesson:

```sh
# The policies: all three rejections name their rule
kubectl -n demo create deploy bad --image=nginx:latest              # denied: pin a tag
kubectl -n demo run t --image=busybox:1.37 --privileged             # denied: PSA baseline

# The network contract: the db answers the api and nobody else
kubectl -n demo exec deploy/web -- sh -c 'nc -zw2 db 5432'          # times out - web may not
kubectl -n demo exec deploy/api -- python -c \
  'import socket; socket.create_connection(("db", 5432), 2); print("api may")'
hubble observe -n demo --verdict DROPPED --last 10                  # the denies, live

# The quota: the eleventh replica will not fit
kubectl -n demo scale deploy api --replicas=20 && kubectl -n demo describe quota demo
kubectl -n demo scale deploy api --replicas=2

# The boundary: tenant admin ends at the namespace wall
kubectl --as=jo --as-group=demo-team -n demo get pods               # allowed
kubectl --as=jo --as-group=demo-team get nodes                      # forbidden
```

## Teardown

`kubectl delete -k tenants/demo` (or remove the Flux Kustomization and
let prune do it). The PVC's PersistentVolume goes with the namespace;
local-path reclaims the disk.

## Exercises

1. **Build a real image**: replace the api's pip-at-start with a proper
   image pushed to `registry.uc1.home` (docs/50-operator.md has the
   Docker insecure-registry setup). Watch the Kyverno tag rule stay
   satisfied.
2. **Second tenant**: copy the folder, change namespace and host, add the
   CNAME. Then try to reach tenant A's db from tenant B's api and watch
   Hubble drop it.
3. **Give the tenant AI**: the ModelDeployment CRD (module 50) is
   namespace-scoped - `kubectl -n demo apply` the sample CR and the
   operator builds the serving stack inside the tenant's walls. Note
   which network policy you must add before the web tier may call it.
4. **Monitor it**: add a ServiceMonitor for the api (it has no /metrics
   yet - that too is the exercise) and a PrometheusRule alerting on 5xx.
5. **Break it on purpose**: run drills 03, 05 and 07 inside `demo`
   instead of `inference` - a tenant namespace is exactly where those
   tickets come from.

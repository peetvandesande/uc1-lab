# What happened

A "capacity experiment": suspend reconciliation, scale the workload to
zero, forget. Suspension is the GitOps off-switch - drift stops being
corrected and *stops being reported*.

# Diagnosis path

    kubectl -n inference get deploy vllm      # replicas: 0 - but why?
    flux get kustomizations                   # 40-inference SUSPENDED True
    flux diff kustomization 40-inference --path ./modules/40-inference

# The trap inside the fix

`flux resume kustomization 40-inference` is necessary but NOT sufficient:
the Deployment manifest in git deliberately has no `replicas` field (KEDA
owns the count), so reconciliation has nothing to put back. And KEDA
cannot rescue it either: scaled to zero, vLLM serves nothing, so
`vllm:num_requests_waiting` has no series, the scaler never activates,
and zero is a stable state. An autoscaler keyed on a metric the workload
itself emits cannot recover the workload from nothing.

    flux resume kustomization 40-inference
    kubectl -n inference scale deploy vllm --replicas=1   # the human kick

# Prevention / hardening

- Suspensions must be time-boxed and visible: alert on
  `gotk_suspend_status == 1`, or make `flux get all -A` a daily glance.
- Scale-to-zero designs need an activation signal that exists while the
  workload is gone (an LB/ingress request count, a queue outside the
  pod) - this lab's trigger is deliberately the naive one.
- Know every writer of spec.replicas: humans, Flux, KEDA's HPA. Drift
  reads differently depending on who else holds a pen.

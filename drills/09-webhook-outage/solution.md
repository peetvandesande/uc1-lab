# What happened

A ValidatingWebhookConfiguration points at a service that does not exist,
with `failurePolicy: Fail`. The API server must consult it for every pod
and deployment in the namespace; no answer means refuse. An admission
webhook is a synchronous dependency of the API itself - the strongest
SPOF you can register, and it arrives looking like an innocent YAML.

# Diagnosis path

    kubectl -n inference run test --image=busybox --dry-run=server
        # Internal error ... failed calling webhook "gate.compliance.example.com":
        # ... service "compliance-gate" not found
    kubectl get validatingwebhookconfigurations
    kubectl get mutatingwebhookconfigurations          # always check both

The error names the webhook. From there it is one get away.

# Fix

    kubectl delete validatingwebhookconfiguration compliance-gate

(If the webhook were real and its backend down, the fix is restoring the
backend or consciously relaxing failurePolicy - a judgement call about
what the gate protects.)

# Prevention / hardening

- Kyverno runs with failurePolicy Ignore for exactly this reason -
  availability over strictness; know which way each of your webhooks
  leans and why. Scope (`namespaceSelector`) limits the blast radius.
- This failure also bites upgrades and node drains: pods cannot be
  recreated while the gate is dark.

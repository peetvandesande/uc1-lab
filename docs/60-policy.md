# Module 60 - policy and security posture

Three layers, smallest useful version of each:

- **PSA**: the inference namespace enforces `baseline`, warns on
  `restricted` (see its labels). Try a hostPath pod there and read the
  refusal.
- **NetworkPolicy**: default-deny ingress in `inference`, with explicit
  allows for ingress-nginx and Prometheus. `kubectl exec` a shell
  somewhere else and prove the deny; Hubble shows the drops live.
- **Kyverno** (enforced in `inference`, audit elsewhere): no `:latest`,
  resource requests mandatory, and the data-residency contract - every
  workload labelled `uc1.home/data-residency: eu`. The "residency" label
  is a stand-in for the real thing (admission-time placement rules,
  storage classes pinned to a region, audit trail), but the mechanism -
  policy as versioned YAML in git, enforced at admission - is exactly it.

Policy reports: `kubectl get policyreports -A`.

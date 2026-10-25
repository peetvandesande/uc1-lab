# What happened

CoreDNS's Corefile lost the `kubernetes` plugin block entirely and now
forwards everything (including cluster.local) to a blackhole address.
Every in-cluster name fails: probes that call services, Grafana ->
Prometheus, vLLM's model download, scrapes by name. Many symptoms, one
cause - the signature of an infrastructure-layer failure.

# Diagnosis path

The fan-out of unrelated failures is the cue to test the common layers:

    kubectl run t --rm -i --restart=Never --image=busybox:1.37 --command -- \
      nslookup kubernetes.default.svc.cluster.local     # fails -> DNS
    kubectl -n kube-system logs deploy/coredns          # forward errors
    kubectl -n kube-system get cm coredns -o yaml       # no kubernetes plugin!

# Fix

    kubectl -n kube-system apply -f /tmp/uc1-drill08-coredns.yaml
    kubectl -n kube-system rollout restart deploy/coredns

# Prevention / hardening

- "Many things broke at once" is nearly always one shared dependency:
  DNS, the CNI, the API server, storage, time. Check those four before
  chasing any individual service.
- coredns is just a ConfigMap+Deployment; it deserves the same GitOps
  discipline as everything else (Talos lets you template it too).

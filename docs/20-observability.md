# Module 20 - observability

kube-prometheus-stack (Prometheus, Alertmanager, Grafana, node-exporter,
kube-state-metrics), Loki single-binary, Alloy as the log shipper. The
control plane itself is scraped - etcd (:2381), controller-manager,
scheduler - because the machine config binds their metrics to the node
addresses (see the cluster patch in talos.tf); kube-proxy is absent by
design (Cilium).

Dashboards to live in: the vLLM board (provisioned from
modules/20-observability/dashboards/), DCGM for the GPU, the Cilium
board, and the kube-prometheus defaults for nodes/etcd/apiserver.

Logs: Grafana -> Explore -> Loki; `{namespace="inference"}` to start.

## Alerts

`uc1-platform` PrometheusRule holds the lab's own: vLLM queue depth,
inference endpoint down, GPU metrics absent, GPU temperature, Flux
reconcile errors. Delivery is intentionally nothing (the Alertmanager UI
is the lab's pager). To get real mail, uncomment the receiver in
modules/20-observability/kube-prometheus-stack.yaml - the homelab's
hermes relays for 192.168.32.0/21 without auth - and route to a mailbox
hermes hosts.

Every drill that breaks something should be visible here before you fix
it; if it was not, that is a finding for the RCA ("detection gap").

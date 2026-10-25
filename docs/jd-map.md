# Job description -> lab map

Every bullet from the JD and where this lab exercises it.

| JD asks | Where you practise it |
|---|---|
| Operating a production-grade Kubernetes platform | the whole repo; scripts/verify.sh is "is production healthy" |
| End-to-end ownership of components | each module is a component you own, GitOps-managed |
| Troubleshooting complex k8s infrastructure | drills 01-15 |
| - unavailable nodes | drills 01, 02, 10 |
| - unhealthy or hanging pods | drills 03, 04, 05, 06, 07 |
| - Kubernetes Operators | module 50 (write one), module 30 (operate one), drill 12 |
| - CRDs and controllers | module 50; gpu-operator's ClusterPolicy; Flux's own CRDs |
| - unexpected reconciliation behaviour | drills 11, 13; operator exercises 2 and 5 |
| - platform/infrastructure dependencies | drills 08 (DNS), 09 (webhook), 02 (network), 07 (storage) |
| Restoring production and RCA | every drill ends with docs/rca-template.md |
| Preventing recurrence | the "prevention/hardening" section of every solution |
| Safe rolling upgrades | module 90; drill 14 is the pre-upgrade gate |
| HA + predictable GPU infrastructure | module 30; the five-layer GPU chain in docs/30-gpu.md |
| LLM inference and model serving | module 40; drill 15 |
| NVIDIA NIM and vLLM | vLLM for real (CPU); NIM as pattern + mock (docs/40-inference.md) |
| Automation, observability, processes | tofu+ansible; module 20; the drill loop itself |
| Reusable patterns, clear interfaces | the ModelDeployment CRD is exactly that |
| Developer experience, time-to-market | "one CR to serve a model" vs the YAML in module 40 |
| Security and data residency | module 60 |
| Talos Linux | everywhere; docs/00-cluster.md |
| Bare metal / self-managed | Proxmox + SDN + VIP + LB-IPAM - no cloud LB to hide behind |
| GPU Operator / CUDA | module 30 |
| Linux administration | Talos's API-only take on it; the vfio work on the host |
| Fluent written English | the RCAs - have them reviewed, that is the practice |

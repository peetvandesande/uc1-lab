# uc1-lab

A production-shaped Kubernetes platform for LLM serving, run as a lab on
the homelab's Proxmox host: **Talos Linux** nodes as VMs, a **GPU** passed
through for inference, **vLLM** and a NIM-shaped mock behind one endpoint,
a hand-written **operator**, and a drill library that breaks it all on
purpose. Built to practise the work of a DevOps / platform engineer who
owns such a platform in production.

OpenTofu creates the VMs; Ansible prepares the Proxmox host and tears the
lab down; Flux runs everything inside the cluster from this repository.
The lab follows the conventions of its siblings (openstack-lab,
nutanix-lab): its own resource pool and API token, an SDN zone inside
192.168.32.0/21, names registered in the homelab's DNS, nothing touched
outside its own scope.

## What you get

- 3 control planes (shared API VIP) + 2 workers, Talos v1.13, k8s 1.36 -
  one step behind current, so the upgrade runbook is real work
- Cilium (no kube-proxy, LB-IPAM, Hubble), local-path storage,
  cert-manager with a lab CA, ingress-nginx
- kube-prometheus-stack + Loki/Alloy; etcd and the control plane scraped;
  vLLM and DCGM dashboards; alerts the drills actually fire
- The Quadro P2200 on worker-1 via vfio: GPU Operator (driver and toolkit
  from Talos extensions), device plugin, DCGM
- vLLM (CPU backend - the card is Pascal; the real API and metrics
  regardless), Ollama on the GPU, a mock NIM, KEDA scaling on queue depth
- `operator/`: a kubebuilder operator with a ModelDeployment CRD -
  finalizers, owner refs, conditions, envtest
- Kyverno + NetworkPolicies + PSA as the security/data-residency posture
- `drills/`: 15 break/fix scenarios with briefs, verifiers and solutions

## Running it

```sh
ansible-playbook ansible/prepare-proxmox.yml   # once; the GPU part needs one host reboot
ansible-playbook ansible/bootstrap.yml
tofu init && tofu apply -var-file=secret.tfvars
scripts/bootstrap-cluster.sh                   # needs GITHUB_TOKEN for flux bootstrap
scripts/verify.sh
```

Then work the modules in order - each has a doc in `docs/` - and when the
platform is green, start pulling it apart: `drills/README.md`.

| | |
|---|---|
| docs/00-cluster.md | the cluster, talosctl, teardown |
| docs/15-ingress.md | the CA, the names |
| docs/20-observability.md | dashboards, alerts |
| docs/30-gpu.md | the passthrough chain, and how to give the card back |
| docs/40-inference.md | vLLM / Ollama / NIM |
| docs/50-operator.md | build, deploy, exercises |
| docs/60-policy.md | Kyverno, NetworkPolicy, PSA |
| docs/90-upgrades.md | Talos and Kubernetes rolling upgrades |
| docs/jd-map.md | which part of the lab trains which JD bullet |

## Requirements

- The Proxmox host from `../homelab` (lenora), root SSH
- ~90 GB RAM and 44 vCPUs free on it; ~130 GB on ssdpool, ~180 GB on hddpool
- Workstation: tofu, ansible, talosctl, kubectl, helm, flux, go (for the
  operator), docker
- The other labs' VMs stopped (RAM), though their SDN zones may stay -
  this lab only claims 192.168.39.0/24

## Addressing

See NETWORK.md. Everything lives in `network.conf`, the single source
OpenTofu and the playbooks read.

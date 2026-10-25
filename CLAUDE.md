# uc1-lab

A Kubernetes/LLM platform lab on the homelab's Proxmox host (lenora), for
practising platform-engineer work: Talos, GPU serving, operators, upgrades
and incident drills. Sibling to openstack-lab and nutanix-lab and built on
their conventions: OpenTofu makes the VMs (pool uc1-lab, token
terraform@pve!uc1-lab, VMIDs 9301-9303/9311-9312), Ansible owns the host
side, network.conf is the single source both read.

- **Network**: SDN zone `uc1`, one vnet, 192.168.39.0/24 - deliberately
  disjoint from openstack-lab's subnets so both zones can exist; only RAM
  decides which lab runs. API VIP .10, nodes .11-.13/.21-.22, LB pool
  .100-.199. DNS zone uc1.home via Pythia's API, created by bootstrap,
  removed by teardown; the homelab repo needs no edits for this lab.
- **The GPU** (P2200, 0000:86:00) is vfio-bound by prepare-proxmox.yml and
  passed to uc1-worker-1. Giving it back to the host is a manual revert -
  docs/30-gpu.md. It is Pascal: vLLM and NIM cannot use it (CC 6.1 < 7.0);
  Ollama can. vLLM runs its CPU backend. Do not "fix" that by bumping the
  NVIDIA extensions past the 580 driver branch - 580 is the last one that
  supports Pascal, which is why the -lts extensions are pinned.
- **Versions are one step behind on purpose** (Talos 1.13/k8s 1.36 at
  build time): module 90 is a real upgrade. After upgrading, bump
  TALOS_VERSION in network.conf and kubernetes_version in variables.tf so
  tofu matches reality.
- **Flux owns everything in-cluster** from clusters/uc1 + modules/. Cilium
  is first installed by scripts/bootstrap-cluster.sh (no CNI before it)
  and then adopted by its HelmRelease - keep release name/namespace and
  modules/10-cilium/values.yaml as the single values source.
- **secrets/** (kubeconfig, talosconfig) and secret.tfvars are generated
  and gitignored; `. scripts/env.sh` wires kubectl/talosctl to them.
  scripts/verify.sh is the "is the platform healthy" oracle - keep it
  green between exercises, and extend it when adding a module.
- **drills/** break the lab on purpose. Injections scope to the lab (its
  VMs, its namespaces); keep it that way. lib.sh reaches the Proxmox host
  as root@lenora.home (override: PROXMOX_TARGET).
- The job description this lab trains for is in `job description.md`,
  deliberately untracked; docs/jd-map.md maps its bullets to modules.

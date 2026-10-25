# Module 90 - rolling upgrades

The lab installs one step behind current on purpose. Targets:

| What | Installed | Target |
|---|---|---|
| Talos | v1.13.12 | v1.14.4 |
| Kubernetes | 1.36.3 | 1.37.1 |

Both -lts NVIDIA extensions exist for v1.14.4 with the same 580 driver,
so the GPU survives the OS upgrade. Verify that claim before believing
it (the habit matters more than the fact):

```sh
curl -s https://factory.talos.dev/version/v1.14.4/extensions/official | jq -r '.[].name' | grep nvidia
```

## Before any upgrade - the gate

```sh
scripts/verify.sh                                  # start green or do not start
talosctl health --server=false
kubectl get pdb -A                                 # drain deadlocks? (drill 14)
talosctl -n 192.168.39.11 etcd status              # leader, no alarms
flux suspend kustomization --all                   # no reconciler surprises mid-upgrade; resume after
```

## 1. Talos OS, node by node

`talosctl upgrade` stages the new image, reboots the node, and keeps etcd
membership intact; the kubelet drains... no - **it does not drain**. Talos
cordons but the pods are killed with the reboot, so drain yourself when it
matters:

```sh
# workers first, GPU worker last (its image differs - note the schematic!)
kubectl drain uc1-worker-2 --ignore-daemonsets --delete-emptydir-data
talosctl -n 192.168.39.22 upgrade \
  --image factory.talos.dev/installer/<BASE_SCHEMATIC>:v1.14.4 --wait
kubectl uncordon uc1-worker-2
scripts/verify.sh          # between every node - this is the discipline

kubectl drain uc1-worker-1 --ignore-daemonsets --delete-emptydir-data
talosctl -n 192.168.39.21 upgrade \
  --image factory.talos.dev/installer/<GPU_SCHEMATIC>:v1.14.4 --wait
kubectl uncordon uc1-worker-1
# GPU check: DCGM reporting, nvidia-smi pod runs (docs/30-gpu.md)

# control planes one at a time; etcd must show 3 voters before the next
talosctl -n 192.168.39.13 upgrade --image factory.talos.dev/installer/<BASE_SCHEMATIC>:v1.13.12 --wait
talosctl -n 192.168.39.13 etcd members
# ... then .12, then .11 (the VIP moves when its holder reboots - watch it)
```

Schematic ids are in network.conf. A failed upgrade rolls back on its
own (Talos boots the previous image if the new one does not come up) -
induce one on a worker some day to see it.

Afterwards: bump TALOS_VERSION in network.conf, update the install images
in a `tofu plan` (expect config-only changes, no replacement), commit.

## 2. Kubernetes

One command, control plane first, then kubelets, one node at a time:

```sh
talosctl -n 192.168.39.11 upgrade-k8s --to 1.37.1
```

It pre-pulls images, patches the static pod configs through the machine
config, and waits per node. Watch `kubectl get nodes` report mixed
versions mid-flight - that mixed state is the exact thing version skew
policy exists for. Then set kubernetes_version in terraform.tfvars and
`tofu plan` to confirm no drift.

## 3. Platform components

Charts upgrade by PR: bump the version in the module's HelmRelease, push,
watch `flux get helmreleases -A --watch`. Practise a failure: bump
Cilium with a deliberately broken value, watch the HelmRelease go Failed,
then `flux` the rollback (helm-controller keeps history; spec.rollback
or revert the commit - the second one is the GitOps answer).

Order worth respecting when several move: Cilium first on its own day;
kube-prometheus-stack and CRD-carrying charts (gpu-operator, kyverno,
cert-manager) each alone - CRD upgrades are the part that bites.

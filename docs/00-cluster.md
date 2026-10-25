# Module 00 - the cluster

Five Talos VMs on lenora: three control planes (ssdpool - etcd wants SSD
latency), two workers (hddpool), worker-1 with the P2200 passed through.
The kube-apiserver sits behind a Talos-managed shared VIP (192.168.39.10,
`api.uc1.home`): the control planes campaign for it through etcd, so it
moves with quorum, not with hope.

## Build

```sh
ansible-playbook ansible/prepare-proxmox.yml   # once; GPU part wants a host reboot
ansible-playbook ansible/bootstrap.yml         # SDN, DNS, images, pool, token
tofu init && tofu apply -var-file=secret.tfvars
scripts/bootstrap-cluster.sh                   # talos health, Cilium, Flux
scripts/verify.sh                              # green means done
. scripts/env.sh                               # talosctl/kubectl wired to the lab
```

## Talos in one breath

No SSH, no shell, no package manager: an API (`talosctl`) and a declared
machine config, applied as a whole. The useful daily set:

```sh
talosctl -n 192.168.39.11 dashboard        # the "console" of a node
talosctl -n 192.168.39.21 services         # systemd's answer, API-shaped
talosctl -n 192.168.39.21 logs kubelet
talosctl -n 192.168.39.21 dmesg
talosctl -n 192.168.39.11 etcd members
talosctl health --server=false
talosctl -n <ip> get members               # cluster discovery view
talosctl -n <ip> edit machineconfig        # change, applied live where possible
```

Machine config changes that belong to the *cluster* (not an experiment)
go into `talos.tf` patches and arrive via `tofu apply` - the provider
re-applies configs in place.

## Teardown / rebuild

```sh
tofu destroy -var-file=secret.tfvars
ansible-playbook ansible/teardown.yml      # zone, DNS, pool, token, local state
```

Rebuilding from nothing is itself a drill; time yourself.

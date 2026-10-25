# Operating the cluster

The day-to-day manual: starting, stopping, updating, upgrading and
troubleshooting the lab. The module guides describe what each part *is*;
this is how you *run* it. Everything here assumes the repo root as the
working directory.

```sh
. scripts/env.sh        # source it (a dot and a space) - exports KUBECONFIG
                        # and TALOSCONFIG for the current shell; needed in
                        # every new terminal
scripts/verify.sh       # the health oracle: green means the platform keeps
                        # every promise the modules make
```

Three places hold state; know which one you are changing:

| Where | What | Changed by |
|---|---|---|
| git (this repo) | everything in-cluster | commits; Flux applies them |
| tofu state + `secrets/` | the VMs, machine configs, credentials | `tofu apply` |
| the Proxmox host | SDN zone, pool, token, mapping, images, vfio | the playbooks |

A `kubectl edit` is drift: Flux reverts it within 10 minutes. That is a
feature; use branches and commits even for experiments, or
`flux suspend kustomization <n>` deliberately - and time-box it (drill 11
is what forgetting looks like).

## Stopping and starting

### The whole lab (e.g. to free RAM for another lab)

Stop workers first, control planes last - etcd keeps quorum until the
end; start in the reverse order. `qm shutdown` is graceful: the guest
agent asks Talos, which stops workloads and unmounts cleanly.

```sh
ssh root@lenora.home 'for id in 9311 9312 9301 9302 9303; do qm shutdown $id; done'
ssh root@lenora.home 'for id in 9301 9302 9303 9311 9312; do qm start $id; done'
```

After starting: the API answers once two control planes agree (the VIP
follows etcd leadership), nodes go Ready when Cilium is up, and Flux
needs no help - it picks up where it left off. `scripts/verify.sh` is the
"fully back" test. Expect a few minutes of alerts while things settle.

Workloads with PVCs (Prometheus, Loki, the registry, Ollama's models)
live on local-path volumes pinned to their node - they come back with it
and cannot float elsewhere. That is the local-path trade-off on display.

### One node

Planned (upgrades, maintenance): drain first, and know that a PDB can
veto it - that is drill 14, and the right response is to make the budget
satisfiable, never to force past it.

```sh
kubectl drain uc1-worker-2 --ignore-daemonsets --delete-emptydir-data
ssh root@lenora.home qm shutdown 9312     # or: talosctl -n 192.168.39.22 shutdown
# ...
ssh root@lenora.home qm start 9312
kubectl uncordon uc1-worker-2
```

Reboot without the detour: `talosctl -n <ip> reboot`.

Control planes: one at a time, always; check
`talosctl -n 192.168.39.11 etcd members` shows three voters before
touching the next. Two down = no quorum = drill 10.

### The Proxmox host

Every VM has `onboot=1`, so a lenora reboot brings the lab back without
ceremony - order is not guaranteed, but etcd re-elects and everything
converges. Shut the lab down first anyway when the reboot is planned;
"crashed" and "stopped" are different etcd recovery paths and the second
one is boring, which is what you want.

### Stop vs teardown

Stopping keeps everything. `tofu destroy` + `ansible/teardown.yml`
removes the VMs, zone, DNS and credentials - rebuilding is quick but the
in-cluster state (dashboards you clicked together, registry contents,
Prometheus history) is gone. **After any destroy, run
`ansible-playbook ansible/bootstrap.yml` before the next apply**:
destroying a VM purges its `/vms/<id>` ACL and mid-create permission
checks fail without it (docs/00-cluster.md has the mechanism).

## Updating and upgrading

### Platform components (charts) - via git, always

Versions are pinned in each module's HelmRelease. Bump, commit, push,
watch:

```sh
grep -rn "version:" modules/*/release.yaml modules/*/*.yaml | grep -v apiVersion   # what is pinned where
# edit the version, then:
git commit -am "Bump kube-prometheus-stack to X" && git push
flux reconcile source git flux-system     # or wait for the next sync
flux get helmreleases -A --watch
```

Rollback is `git revert` + push - helm history is kept, but git is the
authority. Rules of thumb:

- One CRD-carrying chart per change (kube-prometheus-stack, gpu-operator,
  kyverno, cert-manager, cilium) - CRD upgrades are the part that bites.
- Cilium gets its own day. After a cilium change also run
  `kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status`.
- Check the chart's release notes for values renames; a failed HelmRelease
  shows the renderer's complaint in `flux get hr -A` / `kubectl describe hr`.

### Pinned images (vLLM, Ollama, mock-nim, registry)

Image tags live in the module manifests (`modules/40-inference/*.yaml`,
`modules/50-operator/registry.yaml`). Same loop: edit, commit, watch the
rollout. Ollama uses `strategy: Recreate` - expect a short GPU-inference
gap while the old pod releases the card.

### The operator

```sh
cd operator
make test                        # envtest, before anything ships
# bump IMG in the Makefile (or make docker-build IMG=...)
make docker-build docker-push    # -> registry.uc1.home
make deploy                      # rolls the controller
kubectl -n inference get mdep    # the CRs should stay Ready throughout
```

CRD schema changes: `make manifests install` before `make deploy`, and
mind that removing fields breaks stored objects - version the API
instead (v1alpha2) when it matters.

### Talos OS and Kubernetes

The full runbook with health gates is **docs/90-upgrades.md** - the short
form: workers first (GPU worker with its own schematic), control planes
one at a time, `talosctl upgrade-k8s` afterwards, `scripts/verify.sh`
between every step. After upgrading, update TALOS_VERSION in network.conf
and `kubernetes_version` in variables.tf so tofu matches reality - the
next `tofu plan` must be clean.

The NVIDIA constraint: stay on the `-lts` extension branch (driver 580) -
it is the last branch that knows the Pascal P2200. Check the target Talos
version still ships it before upgrading (the command is in 90-upgrades.md).

### Flux itself

```sh
brew upgrade flux
flux check
GITHUB_TOKEN=... flux bootstrap github --owner peetvandesande --repository uc1-lab \
  --branch main --path clusters/uc1 --personal     # idempotent: upgrades the controllers in place
git pull                                           # it commits the new manifests
```

### Certificates

Nothing to do by hand. Ingress certs renew via ACME against pistis
(90-day lifetimes, renewed at two-thirds); Hubble's internal certs renew
from uc1-ca. If pistis is down at renewal time the Certificate goes
not-Ready and the old secret keeps serving until it expires - that is
your window, and `kubectl get certificates -A` is the place to look.

### Workstation tools

`brew upgrade talosctl kubernetes-cli helm fluxcd/tap/flux`. talosctl
warns when the client runs ahead of the nodes; a one-minor gap is fine,
more deserves a cluster upgrade first.

## Troubleshooting

### Method first

Walk the layers until two of them disagree; the fault lives between the
last layer that is right and the first that is wrong.

```
workstation -> LAN/DNS -> lenora (host) -> VM -> Talos -> etcd/API
            -> CNI -> platform (Flux/charts) -> workload
```

Three habits that pay for themselves:

1. `scripts/verify.sh` before any theory - it localises the break to a
   layer in one run.
2. "Many things broke at once" means a shared dependency: DNS, time, the
   CNI, the API, storage. Check those before any individual service.
3. After fixing, write the RCA (docs/rca-template.md). Detection gaps
   found there become alert rules in modules/20-observability.

### The cookbook, by layer

**Host / VM**

```sh
ssh root@lenora.home qm list                          # what is even running
ssh root@lenora.home qm status 9311
ssh root@lenora.home 'qm config 9311 | grep -E "net0|hostpci"'   # link_down? mapping?
```

**Talos** (no SSH - the API is the console)

```sh
talosctl -n <ip> dashboard          # live overview: load, services, logs
talosctl -n <ip> services           # anything not Running/OK is the lead
talosctl -n <ip> logs kubelet       # also: etcd, apid, containerd
talosctl -n <ip> logs controller-runtime | tail -50   # network, time, config
talosctl -n <ip> dmesg | tail -30
talosctl -n <ip> get timestatus     # synced: true, or nothing else starts
```

A node stuck "Waiting for time sync" cannot start kubelet or etcd at
all - NTP is lenora's chrony, which must `allow 192.168.32.0/21` (it cost
this lab its first bootstrap; `../homelab/proxmox` owns that config).

**etcd / control plane**

```sh
talosctl -n 192.168.39.11 etcd members    # three voters or start worrying
talosctl -n 192.168.39.11 etcd status     # leader, db size, errors
kubectl get --raw /readyz?verbose         # the apiserver's own checklist
```

API hangs with VMs running: think quorum (drill 10). API unreachable:
think VIP - it lives on whichever control plane holds the etcd lease,
`talosctl -n <each cp> get addresses | grep 39.10` finds the holder.

**CNI / network**

```sh
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --brief
hubble observe -n inference --last 50     # per-flow verdicts, incl. policy drops
kubectl run t --rm -it --restart=Never --image=busybox:1.37 -- \
  nslookup kubernetes.default.svc.cluster.local    # cluster DNS in one line
```

LoadBalancer address unreachable from the LAN: check the service has its
IP (`kubectl get svc -A | grep 192.168.39`), then remember the answer
path - Cilium answers ARP on uc1net, lenora routes, the router routes the
/21 to lenora. `arp -a | grep 39.100` on lenora shows whether L2
announcement is happening at all.

**Flux / platform**

```sh
flux get all -A                     # the one-screen platform status
flux get all -A | grep -i suspend   # silent risk: suspended = unreported drift
flux logs --level=error -A
kubectl describe hr <name> -n <ns>  # helm render errors live here
flux diff kustomization 40-inference --path ./modules/40-inference   # drift preview
flux reconcile kustomization 30-gpu # the fast-forward button
```

**Workloads** - the five fatal states and their one-liners:

| State | First command |
|---|---|
| CrashLoopBackOff | `kubectl logs <pod> --previous` (the dead container has the evidence) |
| OOMKilled / exit 137 | `kubectl describe pod` -> Last State; size from `kubectl top` |
| ImagePullBackOff | `kubectl describe pod` -> Events name the exact failure |
| Pending | `kubectl describe pod` -> Events: resources? PVC? taint? RuntimeClass? |
| Stuck Terminating | finalizers (`-o yaml`); find the controller that should remove them |

**GPU** - five layers, each with its own signature (docs/30-gpu.md):
`Insufficient nvidia.com/gpu` = device plugin; `RuntimeClass not found` =
module 30 pruned/missing; `OCI runtime create failed` = toolkit
extension; nvidia-smi failing inside = driver/machine config; nothing in
lspci = vfio/passthrough on the host.

```sh
kubectl get node -l uc1.home/gpu=true -o jsonpath='{.items[0].status.allocatable}'
kubectl -n gpu-operator get pods
talosctl -n 192.168.39.21 dmesg | grep -i nvidia
```

**Certificates / ingress**

```sh
kubectl get certificates -A                      # Ready column
kubectl describe order -A | tail -30             # where an ACME attempt died
curl -sv https://grafana.uc1.home 2>&1 | grep -E "issuer|subject|HTTP"
```

The ACME path crosses four systems - pistis (CA), Pythia (DNS), lenora
(routing), ingress-nginx (solver) - and the Order's events say which leg
failed.

**Observability of the observability**: Prometheus targets at
https://prometheus.uc1.home/targets; logs flowing =
`sum(rate(loki_distributor_lines_received_total[5m])) > 0`; alert state
in Alertmanager's UI, not your memory.

### Traps this lab has already sprung once

Documented here so they cost minutes, not evenings:

- **`talosctl health` hangs before the CNI exists** - client-side health
  includes node readiness; nodes cannot be Ready without Cilium.
- **Time sync blocks everything** on a fresh node and looks like a
  Kubernetes problem; it never is. `talosctl get timestatus` first.
- **`tofu destroy` purges per-VMID ACLs** - bootstrap again before apply.
- **A second `options vfio-pci` file wins silently** (last ids=
  assignment, alphabetical file order) and force-loaded nvidia_uvm drags
  nvidia past any blacklist - `dmesg | grep vfio_pci:` shows what was
  actually registered.
- **PCI mappings are validated at VM start** against live hardware,
  every property included; the bootstrap builds them from PVE's own
  hardware listing, so a mismatch means the hardware really moved.
- **nginx allowlists on the homelab side are dual-stack now** - a 403
  where a 401 belongs often means the IPv6 source address is missing
  from an allow list, not a wrong key.
- **env.sh is sourced, not executed** - `. scripts/env.sh`.

### When it is truly wedged

The nuclear option, in order of escalation: reboot the node
(`talosctl -n <ip> reboot`), reset the node back to maintenance and let
tofu re-apply its config (`talosctl -n <ip> reset --reboot
--system-labels-to-wipe STATE,EPHEMERAL`, then `tofu apply`), rebuild the
lab (destroy + teardown + bootstrap + apply - under an hour, and the
GitOps layer reassembles itself). Nothing in the cluster is precious;
that is the point of a lab. The RCA, though - write it first, while the
evidence is still warm.

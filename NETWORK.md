# Network design

All settings live in [network.conf](network.conf). OpenTofu and the
playbooks both read them from there.

```
LAN 192.168.8.0/24 ── router (routes 192.168.32.0/21 -> lenora, NATs it)
      │                   DNS: Themis -> Pythia, zones uc1.home + reverse
      │
lenora vmbr0, forwarding on
      │  SDN zone "uc1" (simple)
      └─ uc1net 192.168.39.0/24  gw .1 on lenora
            ├─ .10         kube-apiserver VIP (api.uc1.home) - Talos moves it with etcd quorum
            ├─ .11-.13     uc1-cp-1..3     (VMIDs 9301-9303, ssdpool)
            ├─ .21-.22     uc1-worker-1..2 (VMIDs 9311-9312, hddpool; worker-1 has the GPU)
            └─ .100-.199   Cilium LB-IPAM pool
                 ├─ .100   ingress-nginx (ingress.uc1.home; grafana/llm/... are CNAMEs)
                 └─ .101   image registry (registry.uc1.home, plain HTTP)
```

## Decisions

| Decision | Reason |
|---|---|
| One /24 for everything | A Kubernetes cluster needs one L2 segment; pod/service traffic rides the CNI. Multi-network realism lives in the openstack lab next door. |
| 192.168.39.0/24, not the whole /21 | Disjoint from openstack-lab's subnets, so the zones coexist and only RAM forces a choice between the labs. The bootstrap still refuses genuine overlaps. |
| Talos shared VIP for the API | The production answer to "which control plane do I talk to" without an external LB; it moves with etcd quorum (drill 10 shows what that means). |
| Cilium LB-IPAM + L2 announcements | LoadBalancer services on bare metal/Proxmox with no cloud; lenora ARPs for the pool on uc1net and routes on. |
| VMIDs 9301+/9311+ | The 9xxx lab block (nutanix 91xx, openstack 92xx); +10 offset separates the roles. |
| Static addresses via nocloud, pinned by machine config | First boot gets the address from the cloud-init drive so the Talos API is reachable for config apply; the machine config then owns it. |
| Firewall off on the vnet NICs | Proxmox MAC filtering would drop VIP and LB traffic, whose MACs it does not know (same as openstack-lab). |
| DNS through Pythia's API | Lab zones come and go with the lab; bootstrap creates them, teardown removes them - nothing in the homelab repo to edit. |

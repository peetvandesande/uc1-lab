# What happened

The VM's virtual NIC had its link set down - the machine is fine, the
network is gone. From Kubernetes it looks identical to drill 01 (NotReady),
which is the point: *unavailable* has layers. etcd keeps quorum (2 of 3),
so the API stays up, but writes now have no margin left.

# Diagnosis path

    kubectl get nodes                             # NotReady
    talosctl -n 192.168.39.13 version             # times out - no path to it
    ssh root@lenora.home qm status <vmid>         # running!
    ssh root@lenora.home qm config <vmid>         # net0: ...link_down=1
    talosctl -n 192.168.39.11 etcd members        # who is still voting?

The gap between "the VM runs" and "nothing reaches it" is the tell:
look at the (virtual) cabling.

# Fix

    ssh root@lenora.home 'qm set <vmid> --net0 \
      "$(qm config <vmid> | sed -n "s/^net0: //p" | sed "s/,link_down=1//")"'

# Prevention / hardening

- An etcd alert on `etcd_server_has_leader` / member count buys the margin
  story: one more loss and the API goes read-only.
- In real incidents this is a switch port, a bond flap or a firewall push;
  the diagnosis muscle - walk the layers down until something disagrees -
  is the same.

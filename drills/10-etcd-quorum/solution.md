# What happened

etcd needs a majority: 2 of 3. With two members gone, the survivor
cannot elect a leader; every write (and any linearizable read) times
out. The apiserver on cp-1 is up but can promise nothing. Workloads
keep running - the data plane does not depend on etcd - but nothing can
change: no scheduling, no scaling, no fixes.

# Diagnosis path

    kubectl get nodes                        # hangs / times out
    talosctl -n 192.168.39.11 service etcd   # Running, but...
    talosctl -n 192.168.39.11 etcd status    # no leader, errors
    talosctl -n 192.168.39.11 logs etcd | tail  # lost the majority of members
    ssh root@lenora.home qm list             # two CP VMs stopped

# Fix

Start the members again; etcd re-elects and heals itself:

    ssh root@lenora.home 'qm start <cp2-id>; qm start <cp3-id>'
    talosctl -n 192.168.39.11 etcd members   # wait for 3 voters
    talosctl health --server=false

The order of recovery matters in worse variants: if a member's data is
*lost* (not just stopped), it must be removed from the member list and
rejoined - `talosctl etcd remove-member`, then reset the node. Never
restore two members from backup into a surviving cluster.

# Prevention / hardening

- This is why the control planes sit on different physical disks in
  real deployments (and why 3 VMs on one host is a lab, not HA).
- Alert on `etcd_server_has_leader == 0` and member count; the window
  between "one down" and "two down" is where operators earn their keep.

locals {
  # network.conf, as a map of lowercase keys, so the address plan has a
  # single source shared with the playbooks
  net = {
    for m in regexall("(?m)^([A-Z_]+)=\"?([^\"\\r\\n]*)\"?", file("${path.module}/network.conf")) :
    lower(m[0]) => trimspace(m[1])
  }

  subnet_bits = split("/", local.net.node_subnet)[1]

  # Control planes count from vm_id_start, workers from vm_id_start + 10,
  # so either group can grow without renumbering the other
  nodes = merge(
    {
      for i in range(var.cp_count) : "${var.cluster_name}-cp-${i + 1}" => {
        vm_id        = var.vm_id_start + i
        host         = tonumber(local.net.cp_host_start) + i
        role         = "controlplane"
        gpu          = false
        cores        = var.cp_cores
        memory_mb    = var.cp_memory_mb
        disk_gb      = var.cp_disk_gb
        datastore_id = var.cp_datastore_id
      }
    },
    {
      for i in range(var.worker_count) : "${var.cluster_name}-worker-${i + 1}" => {
        vm_id        = var.vm_id_start + 10 + i
        host         = tonumber(local.net.worker_host_start) + i
        role         = "worker"
        gpu          = var.gpu_worker && i == 0
        cores        = var.worker_cores
        memory_mb    = var.worker_memory_mb
        disk_gb      = var.worker_disk_gb
        datastore_id = var.worker_datastore_id
      }
    }
  )

  node_ip = { for name, node in local.nodes : name => cidrhost(local.net.node_subnet, node.host) }
  vip     = cidrhost(local.net.node_subnet, tonumber(local.net.vip_host))

  # Talos nocloud images, downloaded to the import storage by
  # ansible/bootstrap.yml. The GPU image adds the NVIDIA -lts extensions
  image = {
    base = "${var.image_storage}:import/talos-${local.net.talos_version}-nocloud-base-amd64.qcow2"
    gpu  = "${var.image_storage}:import/talos-${local.net.talos_version}-nocloud-gpu-amd64.qcow2"
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name        = each.key
  vm_id       = each.value.vm_id
  node_name   = var.node_name
  pool_id     = var.pool_id
  description = "Talos ${each.value.role}${each.value.gpu ? " with the GPU" : ""}, managed by OpenTofu"
  tags        = ["uc1", "opentofu"]

  on_boot         = true
  started         = true
  stop_on_destroy = true

  # q35 for PCIe passthrough; the same machine type everywhere so the nodes
  # are uniform
  machine = "q35"

  operating_system {
    type = "l26"
  }

  cpu {
    type    = "host"
    cores   = each.value.cores
    sockets = 1
  }

  # No ballooning: kubelet and etcd size themselves on what they see
  memory {
    dedicated = each.value.memory_mb
    floating  = 0
  }

  scsi_hardware = "virtio-scsi-single"

  # System disk, imported from the Talos nocloud image. Talos installs
  # itself onto it on first boot and owns it from then on
  disk {
    interface    = "scsi0"
    datastore_id = each.value.datastore_id
    import_from  = each.value.gpu ? local.image.gpu : local.image.base
    size         = each.value.disk_gb
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  boot_order = ["scsi0"]

  # The P2200, both functions (GPU + audio). Needs the vfio setup from
  # ansible/prepare-proxmox.yml and a host reboot first
  dynamic "hostpci" {
    for_each = each.value.gpu ? [1] : []
    content {
      device = "hostpci0"
      id     = local.net.gpu_pci_address
      pcie   = true
      rombar = true
    }
  }

  # Firewall off: its MAC filtering would drop traffic from the VIP and the
  # LoadBalancer addresses, whose MACs Proxmox does not know
  network_device {
    bridge   = local.net.node_vnet
    model    = "virtio"
    firewall = false
  }

  # Talos' nocloud platform reads the static address from the cloud-init
  # drive on first boot; the machine config then pins the same address, so
  # the node survives without the drive
  initialization {
    datastore_id = each.value.datastore_id

    dns {
      domain  = local.net.domain
      servers = split(" ", local.net.dns_servers)
    }

    ip_config {
      ipv4 {
        address = "${local.node_ip[each.key]}/${local.subnet_bits}"
        gateway = local.net.node_gateway
      }
    }
  }

  # The qemu-guest-agent system extension reports addresses to Proxmox and
  # lets it shut nodes down cleanly
  agent {
    enabled = true
  }

  serial_device {}

  lifecycle {
    # Cloud-init only matters on first boot, and Talos owns the disk after
    # installing to it - a size change would otherwise want to rebuild it
    ignore_changes = [initialization, disk[0].import_from]
  }
}

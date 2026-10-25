# Talos machine configuration, applied over the network once the VMs boot
# into maintenance mode. The install image comes from the Image Factory with
# the same schematic as the boot image, so talosctl upgrade keeps the
# extensions.

locals {
  installer = {
    base = "factory.talos.dev/installer/${local.net.talos_schematic_base}:${local.net.talos_version}"
    gpu  = "factory.talos.dev/installer/${local.net.talos_schematic_gpu}:${local.net.talos_version}"
  }

  # Per-node machine patch: hostname, the static address the cloud-init
  # drive also set, and on the control planes the shared VIP the cluster
  # endpoint points at
  node_patch = {
    for name, node in local.nodes : name => {
      machine = {
        install = {
          disk  = "/dev/sda"
          image = node.gpu ? local.installer.gpu : local.installer.base
        }
        network = {
          hostname = name
          interfaces = [
            merge(
              {
                interface = "eth0"
                dhcp      = false
                addresses = ["${local.node_ip[name]}/${local.subnet_bits}"]
                routes    = [{ network = "0.0.0.0/0", gateway = local.net.node_gateway }]
              },
              node.role == "controlplane" ? { vip = { ip = local.vip } } : {}
            )
          ]
          nameservers = split(" ", local.net.dns_servers)
        }
        time = {
          servers = split(" ", local.net.ntp_servers)
        }
      }
    }
  }

  # The in-cluster registry (module 50) speaks plain HTTP on a LoadBalancer
  # address; containerd needs telling
  registry_patch = {
    machine = {
      registries = {
        mirrors = {
          "registry.${local.net.domain}" = {
            endpoints = ["http://registry.${local.net.domain}"]
          }
        }
      }
    }
  }

  # Cilium replaces both the default CNI and kube-proxy (module 10), and
  # the control plane components bind their metrics to the node address so
  # kube-prometheus-stack (module 20) can scrape them
  cni_patch = {
    cluster = {
      network = {
        cni = { name = "none" }
      }
      proxy = { disabled = true }
      etcd = {
        extraArgs = {
          "listen-metrics-urls" = "http://0.0.0.0:2381"
        }
      }
      controllerManager = {
        extraArgs = {
          "bind-address" = "0.0.0.0"
        }
      }
      scheduler = {
        extraArgs = {
          "bind-address" = "0.0.0.0"
        }
      }
    }
  }

  # The GPU worker: load the proprietary driver the -lts extension ships,
  # label the node, and taint it so only GPU workloads land there. The
  # taint goes through kubelet's registerWithTaints: NodeRestriction
  # forbids a node modifying its own taints after registration, and that
  # one refusal makes Talos's NodeApplyController fail its whole batch -
  # machine.nodeTaints on a worker silently costs you the labels too.
  gpu_patch = {
    machine = {
      kernel = {
        modules = [
          { name = "nvidia" },
          { name = "nvidia_uvm" },
          { name = "nvidia_drm" },
          { name = "nvidia_modeset" },
        ]
      }
      nodeLabels = {
        "uc1.home/gpu" = "true"
      }
      kubelet = {
        extraConfig = {
          registerWithTaints = [
            { key = "nvidia.com/gpu", value = "present", effect = "NoSchedule" },
          ]
        }
      }
    }
  }
}

locals {
  # The provider (0.12) appends a HostnameConfig document with "auto:
  # stable" to every generated config, and Talos refuses that next to the
  # v1alpha1 machine.network.hostname these patches set ("static hostname
  # is already set in v1alpha1 config"). Patching the document instead
  # merges hostname INTO auto: stable - also invalid - so the document is
  # deleted and the legacy field, consistent with the rest of this config,
  # names the node.
  drop_hostname_doc = <<-EOT
    apiVersion: v1alpha1
    kind: HostnameConfig
    $patch: delete
  EOT
}

resource "talos_machine_secrets" "this" {
  talos_version = local.net.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = local.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${local.vip}:6443"
  machine_type       = each.value.role
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = local.net.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = concat(
    [
      yamlencode(local.node_patch[each.key]),
      yamlencode(local.registry_patch),
      local.drop_hostname_doc,
    ],
    each.value.role == "controlplane" ? [yamlencode(local.cni_patch)] : [],
    each.value.gpu ? [yamlencode(local.gpu_patch)] : [],
  )
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  endpoint                    = local.node_ip[each.key]
  node                        = local.node_ip[each.key]

  depends_on = [proxmox_virtual_environment_vm.node]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.node_ip["${var.cluster_name}-cp-1"]
  node                 = local.node_ip["${var.cluster_name}-cp-1"]

  depends_on = [talos_machine_configuration_apply.node]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for name, node in local.nodes : local.node_ip[name] if node.role == "controlplane"]
  nodes                = [for name, node in local.nodes : local.node_ip[name]]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.node_ip["${var.cluster_name}-cp-1"]
  node                 = local.node_ip["${var.cluster_name}-cp-1"]

  depends_on = [talos_machine_bootstrap.this]
}

# Credentials for talosctl, kubectl and the scripts; secrets/ is gitignored
resource "local_sensitive_file" "talosconfig" {
  filename        = "${path.module}/secrets/talosconfig"
  file_permission = "0600"
  content         = data.talos_client_configuration.this.talos_config
}

resource "local_sensitive_file" "kubeconfig" {
  filename        = "${path.module}/secrets/kubeconfig"
  file_permission = "0600"
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
}

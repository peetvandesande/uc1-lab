output "nodes" {
  description = "Cluster nodes with their VMID and address"
  value = {
    for name, node in local.nodes : name => {
      vm_id = node.vm_id
      ip    = local.node_ip[name]
      role  = node.role
      gpu   = node.gpu
    }
  }
}

output "endpoints" {
  description = "The cluster's addresses and names"
  value = {
    api_vip     = local.vip
    api_fqdn    = "api.${local.net.domain}"
    kubeconfig  = "secrets/kubeconfig"
    talosconfig = "secrets/talosconfig"
  }
}

# Proxmox connection

variable "pm_endpoint" {
  description = "Proxmox API endpoint, without /api2/json, e.g. https://lenora.home:8006/"
  type        = string
}

variable "pm_api_token" {
  description = "Proxmox API token, e.g. terraform@pve!uc1-lab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  type        = string
  sensitive   = true
}

variable "pm_insecure" {
  description = "Skip TLS verification (only if the Proxmox CA is not in the system trust store)"
  type        = bool
  default     = false
}

# Placement

variable "node_name" {
  description = "Proxmox node to create the VMs on"
  type        = string
}

variable "pool_id" {
  description = "Existing resource pool the VMs are placed in; the API token should only have rights on this pool"
  type        = string
  default     = "uc1-lab"
}

variable "vm_id_start" {
  description = "First VMID; control planes take vm_id_start to +2, workers +10 onwards. Make sure these are free."
  type        = number
  default     = 9301
}

variable "cp_datastore_id" {
  description = "Datastore for the control plane disks - etcd wants SSD"
  type        = string
  default     = "ssdpool"
}

variable "worker_datastore_id" {
  description = "Datastore for the worker disks"
  type        = string
  default     = "hddpool"
}

variable "image_storage" {
  description = "Storage holding the Talos images as import volumes; ansible/bootstrap.yml downloads them"
  type        = string
  default     = "local"
}

# Cluster

variable "cluster_name" {
  description = "Talos cluster name; also the node name prefix"
  type        = string
  default     = "uc1"
}

variable "kubernetes_version" {
  description = "Kubernetes version Talos installs; module 90 upgrades it with talosctl upgrade-k8s"
  type        = string
  default     = "1.36.3"
}

# Node sizing

variable "cp_count" {
  description = "Control plane nodes; 3 for an etcd quorum"
  type        = number
  default     = 3
}

variable "cp_cores" {
  type    = number
  default = 4
}

variable "cp_memory_mb" {
  type    = number
  default = 8192
}

variable "cp_disk_gb" {
  type    = number
  default = 40
}

variable "worker_count" {
  description = "Workers; worker-1 gets the GPU"
  type        = number
  default     = 2
}

variable "worker_cores" {
  description = "vCPUs per worker; vLLM's CPU backend wants plenty"
  type        = number
  default     = 12
}

variable "worker_memory_mb" {
  type    = number
  default = 32768
}

variable "worker_disk_gb" {
  type    = number
  default = 80
}

variable "gpu_worker" {
  description = "Pass the GPU in network.conf through to worker-1 (needs ansible/prepare-proxmox.yml's vfio setup and a host reboot first)"
  type        = bool
  default     = true
}

# Shared by every drill's inject.sh and verify.sh. Not a drill itself.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TALOSCONFIG="$repo/secrets/talosconfig"
export KUBECONFIG="$repo/secrets/kubeconfig"

# VM-level faults go through the Proxmox host
PROXMOX=${PROXMOX_TARGET:-root@lenora.home}

pm() { ssh -o BatchMode=yes "$PROXMOX" "$@"; }

# vmid <vm-name>  e.g. vmid uc1-worker-2
vmid() { pm "qm list" | awk -v n="$1" '$2 == n {print $1}'; }

say()  { printf '%s\n' "$*"; }
pass() { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; exit 1; }

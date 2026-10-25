# Source this: . scripts/env.sh
# Points talosctl and kubectl at the lab, from the files tofu wrote.
_repo="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export TALOSCONFIG="$_repo/secrets/talosconfig"
export KUBECONFIG="$_repo/secrets/kubeconfig"
unset _repo

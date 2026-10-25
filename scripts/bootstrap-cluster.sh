#!/usr/bin/env bash
# From a finished `tofu apply` to a reconciling platform:
#
#   1. waits for the Talos cluster to be healthy
#   2. installs Cilium (the cluster boots with no CNI: cluster.network.cni
#      is "none" and kube-proxy is disabled, so nothing schedules before this)
#   3. bootstraps Flux onto the GitHub repository, which then converges
#      every module under clusters/uc1
#
# Needs: talosctl, kubectl, helm, flux, and GITHUB_TOKEN with repo scope for
# the flux bootstrap. Re-runnable: every step is idempotent.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export TALOSCONFIG="$repo/secrets/talosconfig"
export KUBECONFIG="$repo/secrets/kubeconfig"

github_owner=${GITHUB_OWNER:-peetvandesande}
github_repo=${GITHUB_REPO:-uc1-lab}

cilium_version=$(sed -n 's/^      version: //p' "$repo/modules/10-cilium/release.yaml" | head -1)

say() { printf '\n== %s\n' "$*"; }

# Node lists from the tofu state - health wants told who is what
cp_nodes=$(cd "$repo" && tofu output -json nodes | jq -r '[.[] | select(.role == "controlplane").ip] | join(",")')
worker_nodes=$(cd "$repo" && tofu output -json nodes | jq -r '[.[] | select(.role == "worker").ip] | join(",")')
node_count=$(cd "$repo" && tofu output -json nodes | jq 'length')

# Full talosctl health includes "all k8s nodes ready", which cannot pass
# before the CNI exists - so before Cilium, wait only for the API to answer
# on the VIP and every node to have registered
say "Waiting for the API on the VIP and $node_count registered nodes"
until [ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l)" -eq "$node_count" ]; do
  printf '.'
  sleep 5
done
echo

say "Installing Cilium $cilium_version (skipped if present)"
if ! helm status cilium -n kube-system >/dev/null 2>&1; then
  helm repo add cilium https://helm.cilium.io >/dev/null
  helm repo update cilium >/dev/null
  helm install cilium cilium/cilium \
    --version "$cilium_version" \
    --namespace kube-system \
    -f "$repo/modules/10-cilium/values.yaml"
fi

say "Waiting for the nodes to go Ready"
kubectl wait node --all --for=condition=Ready --timeout=10m

say "Full Talos health check"
talosctl -n "${cp_nodes%%,*}" health --server=false \
  --control-plane-nodes "$cp_nodes" \
  --worker-nodes "$worker_nodes"

say "Bootstrapping Flux onto github.com/$github_owner/$github_repo"
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN is not set - export a token with repo scope" >&2
  exit 1
fi
flux bootstrap github \
  --owner "$github_owner" \
  --repository "$github_repo" \
  --branch main \
  --path clusters/uc1 \
  --personal

say "Done - watch it converge with: flux get kustomizations --watch"

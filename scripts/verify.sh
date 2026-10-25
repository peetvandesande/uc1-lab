#!/usr/bin/env bash
# Asserts the whole lab works, layer by layer. Exit 0 means everything the
# modules promise is actually there. Run it after bootstrap, after an
# upgrade, and after every drill's fix.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export TALOSCONFIG="$repo/secrets/talosconfig"
export KUBECONFIG="$repo/secrets/kubeconfig"

fail=0
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s   (%s)\n' "$desc" "$*"
    fail=1
  fi
}

prom() { # prom <description> <query> - the query must return a value > 0.
  # Through the ingress on purpose: the Prometheus image has no shell
  # utilities to exec, and this way a passing check vouches for the whole
  # path (DNS, LB, ingress, certificate, Prometheus)
  local desc="$1" query="$2" result
  result=$(curl -skG -m 15 https://prometheus.uc1.home/api/v1/query \
    --data-urlencode "query=$query" 2>/dev/null \
    | jq -r '.data.result[0].value[1] // empty' 2>/dev/null)
  if [ -n "$result" ] && [ "$result" != "0" ]; then
    printf 'ok   %s (=%s)\n' "$desc" "$result"
  else
    printf 'FAIL %s (query: %s)\n' "$desc" "$query"
    fail=1
  fi
}

cp_nodes=$(cd "$repo" && tofu output -json nodes 2>/dev/null | jq -r '[.[] | select(.role == "controlplane").ip] | join(",")')
worker_nodes=$(cd "$repo" && tofu output -json nodes 2>/dev/null | jq -r '[.[] | select(.role == "worker").ip] | join(",")')

echo "-- cluster"
check "talos is healthy"                talosctl -n "${cp_nodes%%,*}" health --server=false --control-plane-nodes "$cp_nodes" --worker-nodes "$worker_nodes"
check "every node is Ready"             kubectl wait node --all --for=condition=Ready --timeout=30s
check "the API answers on the VIP"      kubectl --request-timeout=10s version

echo "-- gitops"
check "every Kustomization is Ready"    kubectl wait kustomization --all -n flux-system --for=condition=Ready --timeout=60s
check "every HelmRelease is Ready"      kubectl wait helmrelease --all -A --for=condition=Ready --timeout=60s

echo "-- network"
check "cilium is healthy"               kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status --probe
check "ingress has its address"         sh -c 'kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}" | grep -q 192.168.39.100'
check "ingress answers from the LAN"    curl -skm 10 https://grafana.uc1.home/api/health

echo "-- observability"
prom  "prometheus sees its targets"     'count(up == 1)'
prom  "etcd is scraped"                 'count(up{job="kube-etcd"} == 1)'
prom  "logs are flowing into loki"      'sum(rate(loki_distributor_lines_received_total[5m]))'

echo "-- gpu"
check "the worker advertises the GPU"   sh -c 'kubectl get nodes -l uc1.home/gpu=true -o json | jq -e ".items[0].status.allocatable[\"nvidia.com/gpu\"] == \"1\"" >/dev/null'
prom  "DCGM reports the GPU"            'count(DCGM_FI_DEV_GPU_UTIL)'

echo "-- inference"
check "vLLM answers a completion" sh -c 'curl -skm 120 https://llm.uc1.home/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"Qwen/Qwen2.5-0.5B-Instruct\",\"messages\":[{\"role\":\"user\",\"content\":\"Say ok.\"}],\"max_tokens\":5}" | grep -q choices'
check "ollama answers on the GPU" sh -c 'curl -skm 120 https://llm.uc1.home/ollama/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"qwen2.5:0.5b\",\"messages\":[{\"role\":\"user\",\"content\":\"Say ok.\"}],\"max_tokens\":5}" | grep -q choices'
check "the mock NIM is ready"           curl -skm 10 -o /dev/null -w '' https://llm.uc1.home/nim/v1/health/ready
prom  "vLLM metrics are scraped"        'count(vllm:num_requests_running >= 0)'

echo "-- operator"
check "the registry answers"            curl -sm 10 http://registry.uc1.home/v2/
if kubectl get crd modeldeployments.serving.uc1.home >/dev/null 2>&1; then
  check "a ModelDeployment reconciles"  sh -c 'kubectl get modeldeployments -A -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -qv False'
else
  echo "skip the ModelDeployment CRD is not installed yet (module 50)"
fi

echo "-- policy"
check "kyverno enforces :latest"        sh -c '! kubectl -n inference create deploy should-fail --image=nginx:latest --dry-run=server 2>/dev/null'

exit $fail

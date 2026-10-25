#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
say "starting a 10-minute load job against vLLM"
kubectl -n inference apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: drill15-load
  labels: {uc1.home/data-residency: eu}
spec:
  parallelism: 8
  completions: 8
  backoffLimit: 0
  activeDeadlineSeconds: 700
  template:
    metadata:
      labels: {uc1.home/data-residency: eu}
    spec:
      restartPolicy: Never
      containers:
        - name: load
          image: curlimages/curl:8.11.1
          command: [sh, -c]
          args:
            - |
              end=$(( $(date +%s) + 600 ))
              while [ $(date +%s) -lt $end ]; do
                curl -sm 120 http://vllm:8000/v1/chat/completions \
                  -H 'Content-Type: application/json' \
                  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Write six sentences about etcd."}],"max_tokens":256}' \
                  -o /dev/null
              done
          resources:
            requests: {cpu: 20m, memory: 32Mi}
YAML
say "injected - see brief.md; watch grafana.uc1.home -> vLLM"

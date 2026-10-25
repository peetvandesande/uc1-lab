#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: compliance-gate
webhooks:
  - name: gate.compliance.example.com
    admissionReviewVersions: [v1]
    sideEffects: None
    failurePolicy: Fail
    timeoutSeconds: 5
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: inference
    rules:
      - apiGroups: ["*"]
        apiVersions: ["*"]
        operations: [CREATE, UPDATE]
        resources: [pods, deployments]
    clientConfig:
      service:
        name: compliance-gate
        namespace: default
        port: 443
        path: /validate
YAML
say "injected - see brief.md"

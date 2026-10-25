# Modules 15/16 - certificates and ingress

cert-manager issues from `uc1-ca`, a self-signed CA kept in the
`uc1-ca` secret (cert-manager namespace). ingress-nginx answers on
192.168.39.100 = `ingress.uc1.home`; every service name is a CNAME to it:

| Name | What |
|---|---|
| grafana.uc1.home | dashboards (admin / uc1-lab) |
| prometheus.uc1.home | the Prometheus UI |
| alertmanager.uc1.home | alert state |
| llm.uc1.home | vLLM; /ollama -> GPU engine; /nim -> mock NIM |
| hubble.uc1.home | add an Ingress for hubble-ui as an exercise |
| registry.uc1.home | the image registry (plain HTTP, .101, no ingress) |

Trust the CA locally (macOS):

```sh
kubectl -n cert-manager get secret uc1-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/uc1-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/uc1-ca.crt
```

or live with `curl -k` and browser warnings - the lab does not mind.

An alternative worth doing once: point cert-manager at the homelab's
step-ca (pistis) over ACME instead of the self-signed root, and the lab's
certificates chain to the same CA as everything else on the LAN.

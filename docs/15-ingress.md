# Modules 15/16 - certificates and ingress

Two issuers:

- **step-ca** (the default for ingresses): ACME against the homelab CA on
  pistis (`https://pistis.home:8443/acme/acme/directory`, HTTP-01 through
  ingress-nginx). Certificates chain to the G2 root the LAN already
  trusts, with Let's Encrypt-shaped lifetimes renewed by cert-manager.
- **uc1-ca**: the lab's own self-signed CA, kept for what ACME cannot
  sign - Hubble's internal mTLS SANs - and as the fallback issuer if
  pistis is down.

ingress-nginx answers on 192.168.39.100 = `ingress.uc1.home`; every
service name is a CNAME to it:

| Name | What | URL |
|---|---|---|
| grafana.uc1.home | dashboards (admin / uc1-lab) | https://grafana.uc1.home |
| prometheus.uc1.home | the Prometheus UI | https://prometheus.uc1.home |
| alertmanager.uc1.home | alert state | https://alertmanager.uc1.home |
| llm.uc1.home | vLLM; /ollama -> GPU engine; /nim -> mock NIM | https://llm.uc1.home (also /ollama, /nim) |
| hubble.uc1.home | add an Ingress for hubble-ui as an exercise | https://hubble.uc1.home (once you add the Ingress) |
| registry.uc1.home | the image registry (plain HTTP, .101, no ingress) | http://registry.uc1.home |

Devices that trust the homelab's G2 root (most of the LAN) get a green
padlock on every lab ingress with no extra steps. A device that does not:
install the root from `../homelab/ca/rootca/certs/root.crt`, or live with
`curl -k`.

Worth watching once: `kubectl -n monitoring describe certificate` during
issuance - the ACME order, the HTTP-01 challenge appearing as a temporary
ingress, pistis fetching it over the routed lab network, the secret
landing. That path (DNS via Pythia, routing via lenora, solver via
ingress-nginx) is a four-system integration and each is a place it can
fail - which is what makes it good drill material.

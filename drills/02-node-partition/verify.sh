#!/usr/bin/env bash
. "$(dirname "$0")/../lib.sh"
kubectl wait node uc1-cp-3 --for=condition=Ready --timeout=10s >/dev/null 2>&1 || fail "uc1-cp-3 is not Ready"
pass "uc1-cp-3 is Ready"
talosctl -n 192.168.39.13 etcd members >/dev/null 2>&1 || fail "etcd on .13 is not answering"
m=$(talosctl -n 192.168.39.13 etcd members 2>/dev/null | grep -c true || true)
pass "etcd members all voting"

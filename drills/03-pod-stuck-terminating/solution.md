# What happened

The pod carries a finalizer no controller will ever remove, so its
deletion can never complete, so the namespace's own finalizer
(`kubernetes`) can never see an empty namespace. Everything upstream of
one stuck object hangs - the classic shape of "Terminating forever".

# Diagnosis path

    kubectl get ns drill-tenant -o yaml        # status: Terminating, conditions say what remains
    kubectl -n drill-tenant get all
    kubectl -n drill-tenant get pod sleeper -o yaml | grep -A3 finalizers

`--force --grace-period=0` does NOT remove finalizers - it only skips
waiting for the kubelet. The object stays until the finalizer list is
empty.

# Fix

Remove the finalizer (after understanding why it is there - here, pure
sabotage):

    kubectl -n drill-tenant patch pod sleeper --type=merge \
      -p '{"metadata":{"finalizers":null}}'

The namespace then finishes terminating on its own.

# Prevention / hardening

- Finalizers are a contract: whoever adds one must run a controller that
  removes it. Orphaned finalizers mean a controller died or lost RBAC -
  that is the real root cause to chase in production (see drill 12).
- Never clear finalizers reflexively: on PVs/PVCs they order storage
  teardown, and clearing them can leak or corrupt the backend.

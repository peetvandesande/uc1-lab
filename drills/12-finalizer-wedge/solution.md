# What happened

The CR carries the operator's finalizer, and the operator - the only
thing that removes it - was scaled to zero. Deletion set the
deletionTimestamp and then waited for a controller that never came.
Drill 03 from the other side of the table: this time you own the
controller.

# Diagnosis path

    kubectl -n inference get mdep drill-demo -o yaml
        # deletionTimestamp set, finalizers: [serving.uc1.home/finalizer]
    # who removes that finalizer? the operator:
    kubectl -n uc1-operator-system get deploy    # replicas 0!
    kubectl -n uc1-operator-system get events    # who scaled it, when

# Fix

Bring the controller back and let it do its job:

    kubectl -n uc1-operator-system scale deploy uc1-operator-controller-manager --replicas=1

The reconciler sees the deletionTimestamp, runs its cleanup branch,
removes the finalizer; the API finishes the delete. Hand-clearing the
finalizer also unsticks it - and skips whatever cleanup the finalizer
guards. With this operator that is nothing; with a real one it is
exactly the bill you do not want to pay.

# Prevention / hardening

- Watch controller availability like workload availability: a dead
  controller fails silent, as pending work, not errors.
- When writing operators: finalizer work must be idempotent and fast,
  and anything slow belongs in a job the finalizer merely confirms.

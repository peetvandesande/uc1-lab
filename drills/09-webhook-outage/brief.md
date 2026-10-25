# Ticket: every deploy to inference fails instantly

CI reports `Internal error occurred: failed calling webhook` on every
apply into the inference namespace. Even `kubectl -n inference run
test --image=busybox` is refused. Other namespaces are fine.

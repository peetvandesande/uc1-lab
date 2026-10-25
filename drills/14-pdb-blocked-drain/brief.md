# Task (not an outage): drain uc1-worker-2 for maintenance

Planned work: uc1-worker-2 needs to be drained for a (pretend) hardware
intervention. A colleague started `kubectl drain` an hour ago; it is
still "evicting" the same pod. Finish the job properly - and know when
NOT to force it.

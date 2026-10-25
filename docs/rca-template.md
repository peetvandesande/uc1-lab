# RCA - <one-line title>

**Date:** <when> · **Duration:** <detected -> resolved> · **Severity:** <user impact class>
**Author:** <you> · **Status:** draft / reviewed

## Impact
What users/consumers experienced, in their terms. Numbers where possible
(requests failed, minutes degraded).

## Timeline (UTC)
- hh:mm fault injected / began
- hh:mm first signal (alert? ticket? luck?)
- hh:mm diagnosis milestones - include the wrong turns, they are the lessons
- hh:mm mitigated
- hh:mm fully resolved (verify.sh green)

## Root cause
The mechanism, not the component: *why* it failed and why the failure
propagated to the symptom. "CoreDNS was broken" is a symptom; "a config
change removed the kubernetes plugin, so every in-cluster lookup
forwarded upstream and NXDOMAINed" is a cause.

## Detection
What told us - and what should have. Detection gaps become action items.

## Resolution
What fixed it, and why that was the right fix rather than the fastest.

## What would have prevented it
- <change in config / policy / process>
## What would have found it sooner
- <alert / dashboard / check>
## Action items
- [ ] concrete, owned, small

## Five whys (optional but do it while learning)
1. Why ...

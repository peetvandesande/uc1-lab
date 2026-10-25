# What happened

Eight tight loops of chat completions outrun one CPU replica. The queue
(vllm:num_requests_waiting) grows, TTFT and e2e latency follow, the
VllmRequestQueueHigh alert fires after its 2-minute hold, and KEDA
(threshold 5 waiting) scales the deployment towards 3 replicas. When the
job ends, the queue drains and the cooldown (300s) scales back down.

# The reading order that matters

1. *Is it real?* p95 e2e latency on the vLLM dashboard - subjective
   reports become a number.
2. *Where does the time go?* TTFT rising with queue depth = waiting for
   a slot (capacity); TTFT flat but generation slow = per-token
   performance (CPU contention, model size).
3. *What is the platform doing?* ScaledObject status, replica count,
   the alert's state in Alertmanager.

    kubectl -n inference get scaledobject vllm
    kubectl -n inference get hpa               # KEDA drives one underneath
    kubectl -n inference get pods -w

# The catch worth noticing

The second and third vLLM replica each download the model and warm up
for minutes while the queue keeps growing - autoscaling LLM servers is
slow-motion autoscaling, and capacity planning has to assume it. (In
production: pre-pulled images, a shared model cache on fast storage,
and scale-up thresholds set well before saturation.)

# Prevention / hardening

- Queue depth is the leading indicator; latency is the lagging one.
  Alert on the leader.
- Load-test the scale-up path before users do it for you.

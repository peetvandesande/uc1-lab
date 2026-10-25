# Module 40 - LLM serving

Three engines, one host name (`llm.uc1.home`):

| Path | Engine | Why it is here |
|---|---|---|
| / | vLLM v0.29, CPU backend (AVX-512) | the real vLLM API + vllm:* metrics |
| /ollama | Ollama on the P2200 | real GPU inference on Pascal |
| /nim | mock NIM | NIM-shaped surface to practise against |

```sh
curl -sk https://llm.uc1.home/v1/models | jq
curl -sk https://llm.uc1.home/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"hello"}]}' | jq
curl -sk https://llm.uc1.home/ollama/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5:0.5b","messages":[{"role":"user","content":"hello"}]}' | jq
```

vLLM pulls its model from Hugging Face on first start (minutes; the
readiness probe holds it out of the Service meanwhile). KEDA scales it
1->3 on `vllm:num_requests_waiting > 5` - drill 15 shows why that signal
and not CPU.

## What real NIM operations would add

Worth knowing for the JD even though the card cannot run it: NIM ships
one container per model family from nvcr.io (pull secrets + NGC_API_KEY
licence), selects an optimised engine per GPU at start, caches it in a
PVC mounted at /opt/nim/.cache, exposes the same OpenAI surface plus
/v1/health/{live,ready} and Prometheus metrics - i.e. everything this
module practises, with a licence and bigger silicon. NVIDIA's `nim-llm`
Helm chart and the NIM Operator (CRDs: NIMService, NIMCache) follow the
same pattern as the module 50 operator.

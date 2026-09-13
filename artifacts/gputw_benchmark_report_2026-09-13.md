# GPUtw Qwen3.8-27B benchmark report

## Scope

- Instance: `db954f8c-1e73-42e8-bde8-8f03c9c33cf9` (RTX 5090 32 GB, 53 GB RAM)
- Profile during the compared runs: `mtp16`
- Context targets: 32K and 64K; output cap 256 tokens
- Three timed batches plus one warm-up per combination
- Token-accurate unique padding, so prefills are cold even though prefix caching is enabled
- All completed requests returned successfully; pool limits skip 32K C16 and 64K C8/C16

## Median results

| mode | context | C1 output tok/s | C2 | C4 | C8 |
|---|---:|---:|---:|---:|---:|
| Light16 | 32K | 38.3 | 47.3 | 55.5 | 54.1 |
| MTP16, thinking off | 32K | 49.0 | 55.9 | 59.5 | 61.5 |
| MTP16, thinking on | 32K | 44.9 | 53.5 | 57.8 | 59.9 |
| Light16 | 64K | 19.3 | 21.4 | 23.0 | — |
| MTP16, thinking off | 64K | 21.1 | 22.3 | 22.9 | — |
| MTP16, thinking on | 64K | 20.4 | 22.2 | 22.4 | — |

Values are aggregate output throughput in tokens/second, median over the three timed batches. C8 at 32K is the highest valid level for the approximately 265K-token KV pool; higher combinations were intentionally skipped to avoid an out-of-memory test.

## Decision

Keep the current instance on `mtp16` with `max-num-seqs=16`. MTP improves 32K aggregate throughput by about 8–29% over the Light profile and has a smaller 64K benefit. Thinking-on reduces decode throughput by roughly 3–8% versus MTP thinking-off in this workload, while leaving TTFT nearly unchanged; it should therefore be selected per request based on answer quality, rather than by rebuilding the image or instance.

The service was healthy after the run: profile `mtp16`, authenticated `/health` HTTP 200, and authenticated `/v1/models` HTTP 200. The public GPUtw proxy authentication path and a real Hermes continuation remain separate production gates.

## Evidence on GPUtw

- Light16: `/vault/qwen38/benchmarks/results/2026-09-13_18-03-34_parallel.json`
- MTP16 thinking-off: `/vault/qwen38/benchmarks/results/2026-09-13_18-18-27_parallel.json`
- MTP16 thinking-on: `/vault/qwen38/benchmarks/results/2026-09-13_18-32-46_parallel.json`

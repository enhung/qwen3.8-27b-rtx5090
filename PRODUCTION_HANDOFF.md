# Qwen3.8-27B GPUtw Production Handoff

## Current service

- GPUtw instance: `db954f8c-1e73-42e8-bde8-8f03c9c33cf9`
- GPU: RTX 5090 32 GB; host allocation 53 GB RAM
- Image: `ghcr.io/enhung/qwen38-rtx5090:p1-auth-1973a4eb8add626c77d791ecea63d1ce64d0adb7-34771120435@sha256:6e23342db6616a8c41200680ad602d5c20615675dc18fe06350fa0913c10c1d4`
- HTTPS endpoint: `https://8000-db954f8c-1e73-42e8-bde8-8f03c9c33cf9.gputw.ai`
- API base URL for Hermes: endpoint plus `/v1`
- Model: `qwen3.8-27b`
- Profile: `mtp16` (`max-num-seqs=16`, MTP draft length 2)
- Port 8000: `public`; authentication is enforced by the container middleware

## Hermes defaults

Use the OpenAI-compatible provider with streaming and automatic tool choice. Keep `enable_thinking=false` as the default for lower latency; enable it per request when needed. The API key is the model `VLLM_API_KEY`, stored by the instance at `/vault/qwen38/config/api_key`; never use or expose the GPUtw management key in Hermes.

## Same-instance operations

The profile supervisor supports an in-place switch without creating a new instance:

```text
/app/switch-profile.sh light16
/app/switch-profile.sh mtp16
```

During the switch, wait for authenticated `GET /health` to return 200 before sending traffic. Keep the instance running between normal profile changes so the model and compiled kernels remain available.

## Acceptance evidence

- External auth matrix: 10/10 pass (`401` unauthenticated, `200` valid key, `404` blocked routes)
- MTP/Thinking benchmark: [benchmark report](artifacts/gputw_benchmark_report_2026-09-13.md)
- Production decision: GO with the profile and defaults above

## Operations and rollback

Monitor GPUtw status/resources and Hermes error rates. If auth bypass, repeated output, tool-loop failure, OOM, or restart instability recurs, stop sending traffic, switch to `light16`, and preserve the instance for diagnosis. Keep the v2 digest and `/vault` contents intact; do not delete model or config data during rollback.

The instance is intentionally left running after acceptance. Billing is approximately US$0.5606/hour; stop it only after confirming no active Agent or tool loop.

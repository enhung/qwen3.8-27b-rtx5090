# Qwen3.8-27B (NVFP4) on a single RTX 5090 with vLLM

This repo is a self-contained Docker stack that serves
[**Qwen/Qwen3.8-27B**](https://huggingface.co/Qwen/Qwen3.8-27B),
[NVFP4 4-bit quantized](https://huggingface.co/gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090),
on a single RTX 5090 (32 GB) through [vLLM](https://github.com/vllm-project/vllm).
The API is OpenAI-compatible and includes a 256K-token context,
reasoning, and auto tool choice.

It ships two serve modes: the base **light** setup (no MTP, 16 concurrent
sequences, shared-host defaults) and an **MTP speculative-decoding**
override tuned for a dedicated card. At `0.965` GPU-memory utilization the
full native 256K-token context remains available, and the measured decode
rate is ≈120–170 tok/s (task-dependent). See [Usage modes](#usage-modes)
for the switch and [Performance](#performance) for the measured numbers.

## Purpose

This repo makes one specific thing work, end to end, on a
**single consumer GPU (RTX 5090, 32 GB)**:

- a **27B model** (Qwen3.8-27B) at **NVFP4 4-bit** — ~17.1 GB in VRAM
- the **native 256K-token context** (FP8 KV cache) — most 4-bit recipes cap
  out far earlier on 32 GB
- an **OpenAI-compatible API** with reasoning + auto tool choice (qwen3
  reasoning parser, qwen3_xml tool-call parser) that any OpenAI-SDK client can
  point at — self-hosted, private, no per-token costs

It is a *deployment recipe*, not a framework: the weights come from
Hugging Face, and this repo is the tested glue (Docker image, serve flags,
RAM/tuning) that makes the stack work on Blackwell, with the setup details
that matter on that hardware documented here (FlashInfer SM120 JIT,
`cutlass-dsl`, graph-build OOM).

**Target host:** a plain **Ubuntu 24.04/26.04** box with Docker — bare
metal, a VM, or WSL2 / a similar setup (via Docker Desktop) — no nested
container layers in between. Bare metal / VM: the host only needs Docker
and an NVIDIA driver; `setup.sh` installs the rest (NVIDIA container
toolkit). WSL2 gets its driver from the Windows NVIDIA driver and the
NVIDIA runtime from Docker Desktop, so the apt-toolkit / `systemctl`
steps of `setup.sh` don't apply there (they target bare metal / VMs). The
image ships its own CUDA toolkit either way.

Memory is the practical difference: on WSL/Windows the desktop shares the
GPU, so part of the 32 GB is spoken for before the stack starts. A
dedicated bare-metal or VM host leaves the whole card free for vLLM —
that is what maximum context usage wants: the largest KV pool and the
full 256K-token context (and it is what the dedicated-card MTP tuning
assumes — keep the display off the dGPU, see [Desktop host](#desktop-host)).

Once the stack is up (`docker compose up -d`), `8020`
(direct full API) works immediately;
`8030` (Basic-auth gateway) serves once `METRICS_HASH` is in `.env`
(fail-closed by design — see Authentication & exposure).

## Model

Weights: [gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090](https://huggingface.co/gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090)
— a **GeForce RTX 5090-specific** NVFP4 export of
[Qwen/Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B), quantized with
[NVIDIA Model Optimizer](https://github.com/NVIDIA/Model-Optimizer)
(NVFP4 W4A4, group size 16, FP8 KV).

| | |
|---|---|
| Weights | ~18.8 GB on disk (3 shards), ~17.1 GB in VRAM |
| Quantization | ModelOpt NVFP4 W4A4 + FP8 KV cache |
| Context | full 262,144 tokens fit in 32 GB (KV pool ≈ 265K tokens at the default `--gpu-memory-utilization 0.95`; ≈ 276K at `0.97`) |
| Hardware | Blackwell tensor cores only — Hopper can load the files but cannot run NVFP4 |
| License | Apache-2.0 (same as the base model) |

Numbers from the [model card](https://huggingface.co/gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090):
~80 tok/s single-stream decode, up to ~1,030 tok/s aggregate at 16 concurrent
requests, and a 5/5 tool-call pass rate. The model card also benchmarks
against the alternative [Unsloth NVFP4 export](https://huggingface.co/unsloth/Qwen3.8-27B-NVFP4):
where that one needs ~22.7 GB of weights and holds only a ~77K-token KV pool
(~42 tok/s decode, 2/5 tool calls), this one serves the full 256K context with
a ~276K-token KV pool (~80 tok/s decode, 5/5 tool calls) on the same card.

The weights are pulled into `./models/qwen3.8-27b-nvfp4/` by `setup.sh` and are
**not** part of this repository; this repo's tooling is MIT-licensed (see
`LICENSE.md`).

## Usage modes

Two modes: the base stack is the **light** setup (no MTP, the sensible
shared-host profile — 16 concurrent sequences at `0.95`); the
`docker-compose.mtp.yml` override adds **MTP speculative decoding** —
the model's built-in MTP layers draft 2 tokens per step, roughly
doubling decode speed. MTP is tuned for ideal usage on a dedicated card:
the override ships 3 concurrent sequences at `0.965` GPU-memory
utilization, the full native 256K-token context stays available, and the
measured single-stream decode rate is ≈120–170 tok/s (task-dependent —
[MTP results](#mtp-override-dedicated-card) in Performance; the bench ran
at one concurrent request, so the rate is unaffected by the 3-sequence
cap).

| mode | command | built-in defaults | when to use |
|---|---|---|---|
| Light (default) | `docker compose up -d` | 16 seqs, `0.95` | shared host — display / other workloads OK |
| MTP (ideal-usage tuning) | `docker compose -f docker-compose.yml -f docker-compose.mtp.yml up -d` | 3 seqs, `0.965` + MTP | dedicated card, fast decode, full 256K context |

No image build is involved — the override replaces only the vllm serve
command (see the table above), and no `.env` keys are needed.

To deviate from the tuned values — or to run MTP on a shared host at the
light values (`16` / `0.95`) — set `VLLM_MAX_NUM_SEQS` /
`VLLM_GPU_MEMORY_UTILIZATION` in `.env` (the keys apply to *both* command
lists, so a set value follows you into MTP mode). To go back to the light
shared-host profile, drop the `-f docker-compose.mtp.yml` — and if those
two keys are set in `.env`, remove them too (otherwise the `.env` values
keep applying to the base file; with both unset, the base defaults
`16` / `0.95` kick in).

### MTP (dedicated card)

MTP mode wants the card reserved for it: at `0.965` utilization nearly
all of the 32 GB goes to the engine (weights + KV pool), so the full
native 256K-token context stays available under the tuned low
concurrency. Nothing else runs on the RTX 5090:

- **No display on the RTX 5090.** Do not connect HDMI/DP to it; run the
  desktop environment (X/Wayland) on the iGPU instead, so the compositor
  and every GUI app stay out of the 32 GB. Host setup details
  (iGPU modes, WSL2): [Desktop host](#desktop-host).
- **No other GPU workloads** on the card (agent sessions, other models,
  renders — whatever shows up in `nvidia-smi`). Verify the card is idle
  before enabling MTP mode. WSL2: the Windows desktop shares the GPU, so
  keep the display off the dGPU there too ([Desktop host](#desktop-host)).

## Performance

Measured on this stack: 1x RTX 5090 (32 GB), driver `610.43.02`, vLLM 0.27.1,
NVFP4 weights (~17.1 GB in VRAM) + FP8 KV cache. The single-stream suites run
sequentially with `temperature 0`, a 256-token completion budget, and a unique
padding per run — i.e. a cold prefill, because the stack runs with
`--enable-prefix-caching` and any repeat of a seen prefix would hit the cache.
Re-measure the single-stream tables with:

```bash
.venv_download/bin/python benchmarks/context_bench.py
```

(add `--cached` to also refresh the prefix-cache table; the suite reads
`VLLM_API_KEY` from `.env`; sizes/runs are env-configurable, see the script
header. Raw runs land in `benchmarks/results/`).

### Light mode (single-stream baseline)

At the light-mode defaults (`--gpu-memory-utilization 0.95`, KV pool ≈ 265K
tokens), medians of 3 timed runs per size (2026-08-22, `benchmarks/results/`):

| context | prompt (tok) | TTFT (s) | prefill (tok/s) | decode (tok/s) | E2E (s) |
|---|---|---|---|---|---|
| 1K | 1,087 | 0.07 | 15,104 | 86.0 | 3.04 |
| 8K | 8,255 | 0.59 | 14,075 | 84.4 | 3.61 |
| 32K | 32,831 | 3.38 | 9,725 | 81.1 | 6.52 |
| 64K | 65,598 | 9.63 | 6,814 | 77.3 | 12.93 |
| 128K | 131,135 | 31.09 | 4,218 | 70.6 | 34.70 |
| 250K | 256,062 | 104.48 | 2,451 | 60.6 | 108.69 |

Prefill throughput falls with context length (quadratic attention + KV
writes), while decode holds ≈86→81 tok/s out to 32K context and drifts to
≈61 at the 250K row, where the big KV cache dominates each step. The 250K
row is 256,062 prompt tokens (≈98% of the 262,144 `--max-model-len` cap;
the 256-token completion budget keeps the request inside the ~265K-token
KV pool at the default `0.95` utilization).

### MTP override (dedicated card)

Single-stream `benchmarks/context_bench.py` on a card dedicated to the
stack, run with the MTP override (MTP-2 draft tokens, `--max-num-seqs 3`
— the shipped MTP default — and `0.965` GPU-memory utilization), driver
`610.43.02`, 2026-08-22. Medians
of 3 timed runs per size, 256-token completion budget, unique padding per
run — the stack runs with prefix caching, so the rotating padding keeps the
prefill cold; the single-stream rate is unaffected by the 3-sequence cap
(re-measure per mode/setup; raw runs land in `benchmarks/results/`):

| context | prompt (tok) | TTFT (s) | prefill (tok/s) | decode (tok/s) | E2E (s) |
|---|---|---|---|---|---|
| 1K | 1,084 | 0.10 | 11,211 | 169.3 | 1.60 |
| 8K | 8,253 | 0.66 | 12,593 | 167.1 | 2.18 |
| 32K | 32,829 | 3.65 | 8,994 | 161.6 | 5.23 |
| 64K | 65,597 | 10.28 | 6,380 | 153.9 | 11.94 |
| 128K | 131,133 | 32.68 | 4,013 | 142.1 | 34.47 |
| 250K | 256,060 | 108.89 | 2,351 | 123.7 | 110.95 |

### Prefix-cache effect

With the prefix cache warmed (same padding repeated — the suite's
`--cached` flag), only the unseen suffix is prefilled. Medians of 3 timed
cold runs + the 1 `--cached` run per size (2026-08-16 run; its cold-TTFT
column predates the 2026-08-22 re-measure above — re-run
`context_bench.py --cached` to refresh):

| context | cold TTFT (s) | cached TTFT (s) |
|---|---|---|
| 1K | 0.07 | 0.07 |
| 8K | 0.59 | 0.05 |
| 32K | 3.36 | 0.23 |
| 64K | 9.58 | 0.30 |
| 128K | 30.95 | 0.51 |
| 250K | 104.18 | 0.65 |

### Parallel load

The companion suite `benchmarks/parallel_bench.py` measures aggregate
throughput under concurrent load: every batch fires ALL of its requests at
the same instant (a threading barrier), each with unique padding, so the
timed prefill stays cold despite `--enable-prefix-caching`. Each
context x concurrency combo runs 1 warm-up + 3 timed batches; the
throughput/wall/decode cells are medians over the timed batches (decode:
each batch's mean per-request speed) and the latency columns pool every
timed request of the combo. A level is skipped at a context once the whole
batch (`level x (context + 256-token completion)`) exceeds the ~265K-token
KV pool — c=16 fits only at 8K, c=8 up to 32K, c=4 up to 64K, c=2 up to
128K — so no batch preempts.

Tables from 2026-08-16 (`benchmarks/results/`); the 128K levels produced
no timed batches in that run, so only 8K–64K are shown.

**8K context**

| concurrency | wall (s) | req/s | output (tok/s) | total (tok/s) | TTFT p50 (s) | TTFT p95 (s) | E2E p50 (s) | E2E p95 (s) | decode (tok/s/req) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 3.86 | 0.26 | 66 | 2,207 | 0.60 | 0.60 | 3.85 | 3.85 | 78.3 |
| 2 | 4.81 | 0.42 | 106 | 3,537 | 0.96 | 1.18 | 4.78 | 4.81 | 66.9 |
| 4 | 6.16 | 0.65 | 166 | 5,525 | 1.62 | 2.35 | 6.05 | 6.15 | 57.8 |
| 8 | 8.55 | 0.94 | 239 | 7,963 | 2.79 | 4.72 | 8.29 | 8.54 | 48.4 |
| 16 | 13.86 | 1.15 | 296 | 9,825 | 5.17 | 9.39 | 13.31 | 13.81 | 34.7 |

**32K context**

| concurrency | wall (s) | req/s | output (tok/s) | total (tok/s) | TTFT p50 (s) | TTFT p95 (s) | E2E p50 (s) | E2E p95 (s) | decode (tok/s/req) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6.79 | 0.15 | 38 | 4,871 | 3.41 | 3.41 | 6.79 | 6.79 | 75.4 |
| 2 | 10.64 | 0.19 | 48 | 6,219 | 5.12 | 6.79 | 10.49 | 10.63 | 51.7 |
| 4 | 17.83 | 0.22 | 57 | 7,423 | 8.56 | 13.64 | 17.38 | 17.82 | 34.9 |
| 8 | 37.10 | 0.22 | 55 | 7,134 | 15.45 | 33.23 | 34.00 | 37.07 | 20.6 |

**64K context**

| concurrency | wall (s) | req/s | output (tok/s) | total (tok/s) | TTFT p50 (s) | TTFT p95 (s) | E2E p50 (s) | E2E p95 (s) | decode (tok/s/req) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 13.22 | 0.08 | 19 | 4,982 | 9.67 | 9.67 | 13.21 | 13.21 | 72.1 |
| 2 | 23.44 | 0.09 | 22 | 5,619 | 14.53 | 19.34 | 23.13 | 23.43 | 40.9 |
| 4 | 45.55 | 0.09 | 22 | 5,783 | 24.23 | 41.88 | 42.14 | 45.52 | 27.9 |

The c=1 rows agree with the single-stream context suite above
(≈72–84 tok/s decode depending on context; the 2026-08-16 parallel rows
read 72–78 while the 2026-08-22 single-stream re-measure reads 77–84 at
8K–64K). Aggregate output throughput scales near-linearly with
concurrency at 8K (66 -> 296 tok/s from c=1 to c=16; 9,825 total tok/s
including the prefilled prompts), while per-request decode speed and TTFT
degrade as requests queue behind each other's prefill (32K: 34.9 -> 20.6
tok/s/req and TTFT p95 13.6 -> 33.2 s from c=4 to c=8; past its peak the
aggregate output throughput even dips slightly at 32K). Measured on
a shared host: other GPU workloads (including the agent sessions served by
this very stack) can shift the numbers a bit. Re-measure with
`.venv_download/bin/python benchmarks/parallel_bench.py` (levels, contexts,
and run counts are env-configurable — `BENCH_LEVELS`, `BENCH_CONTEXTS`,
`BENCH_RUNS`; `--quick` for a fast sanity check; raw runs land in
`benchmarks/results/`).

## Requirements

| | |
|---|---|
| GPU | 1x NVIDIA RTX 5090 (32 GB VRAM) |
| System RAM | 64 GB minimum, 128 GB recommended (CUDA graph builds are RAM-hungry) |
| Host | Ubuntu 24.04/26.04, Docker, NVIDIA driver (on WSL2: the Windows NVIDIA driver + Docker Desktop) |
| Disk | ~19 GB for the model weights, ~24 GB for the Docker image (built vLLM stack) |

The container is fully self-contained (it ships its own CUDA toolkit). On the
host you only need the NVIDIA driver and the NVIDIA container toolkit, which
`setup.sh` installs.

## Quickstart

```bash
# 1. Install the NVIDIA container toolkit and download the model (~19 GB)
#    (public model, no HF_TOKEN needed)
sudo ./setup.sh

# 2. Configure
cp .env.example .env
# edit .env:
#   - VLLM_API_KEY: set it, or leave empty to disable auth (LAN use only!)
#   - 8030 gateway (optional): METRICS_USER / METRICS_PASSWORD + METRICS_HASH
#     (bcrypt one-liner in .env.example) — caddy stays down without the hash

# 3. Build and start (first build takes a while)
docker compose up -d --build
# Or start the MTP profile instead (dedicated card — see "Usage modes"):
# docker compose -f docker-compose.yml -f docker-compose.mtp.yml up -d --build

# 4. Check it serves (open when VLLM_API_KEY is empty; with a key set,
#    add -H "Authorization: Bearer $VLLM_API_KEY")
curl http://localhost:8020/v1/models
```

Requests use the model name `qwen3.8-27b` (the compose default for
`--served-model-name`). Port and auth semantics of 8020/8030: see
[Authentication & exposure](#authentication--exposure) below.

### Using the API

```bash
# Direct LLM endpoint (auth per "Authentication & exposure")
curl http://localhost:8020/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.8-27b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 256
  }'
```

Any OpenAI SDK works, e.g. with Python:

```python
import base64, os
from openai import OpenAI

# Direct endpoint: vLLM validates the bearer key (VLLM_API_KEY). When no
# key is configured, any non-empty placeholder works.
client = OpenAI(
    base_url="http://localhost:8020/v1",
    api_key=os.environ.get("VLLM_API_KEY") or "no-key",
)
# … or via the Basic-auth gateway on 8030 (for externally-exposed setups):
# cred = base64.b64encode(
#     f"{os.environ['METRICS_USER']}:{os.environ['METRICS_PASSWORD']}".encode()
# ).decode()
# client = OpenAI(
#     base_url="http://localhost:8030/v1",
#     api_key="gateway",
#     default_headers={"Authorization": f"Basic {cred}"},
# )
# … or the 8030 gateway with the plain vLLM key — the key itself is
# accepted on /v1/* (8020 parity, no Basic auth):
# client = OpenAI(base_url="http://localhost:8030/v1", api_key=os.environ["VLLM_API_KEY"])
resp = client.chat.completions.create(
    model="qwen3.8-27b",
    messages=[{"role": "user", "content": "Hello!"}],
)
```

## Authentication & exposure

The stack has four network surfaces (three reachable externally, one
loopback-only):

| Endpoint | What | Authentication |
|---|---|---|
| `:8020` | direct full vLLM API — OpenAI-compatible `/v1/*` plus `/metrics`, `/health`, `/docs` | `VLLM_API_KEY` empty → **fully open (LAN-use only!)**; key set → bearer on `/v1/*`, while `/metrics`, `/health`, `/docs` stay open by vLLM design |
| `:8030` | caddy gateway — routes `/v1/*` (Basic auth translated into the vLLM bearer key upstream, or the vLLM bearer key itself passed through — 8020 parity), `/metrics` (vLLM telemetry), `/dcgm/metrics` (per-GPU DCGM telemetry) | `/v1/*`: HTTP Basic (`METRICS_USER` / `METRICS_PASSWORD` from `.env`) **or** the vLLM bearer key; `/metrics`, `/dcgm/*`: Basic only |
| `:3000` | Grafana UI | open on all interfaces; protected by the Grafana admin password (sign-ups disabled) |
| `127.0.0.1:9090` | Prometheus (1 y retention) | loopback only — from a remote host, open an `ssh -L 9090:localhost:9090` tunnel first |

Notes:

- **Fresh checkout:** caddy stays down until `METRICS_HASH` (the bcrypt hash
  of `METRICS_PASSWORD`, see `.env.example`) is generated in `.env` —
  fail-closed, so the 8030 gateway is unavailable in the meantime.
- **Prometheus:** the internal scrape targets (on the docker network) are
  unauthenticated — only the host-side ports matter for external exposure.
- **Internet-facing box:** put 8020/8030/3000 behind a firewall or Tailnet;
  nothing unauthenticated sits behind 8030 — every route requires a
  credential: the Basic password on all routes, and `/v1/*` additionally
  accepts the vLLM key alone (the same credential 8020 already requires);
  but 8020/3000 can be.

```bash
# /v1/* on 8020 — direct API (open without VLLM_API_KEY)
curl http://localhost:8020/v1/models

# … or the Basic-auth gateway on 8030 (vLLM + per-GPU telemetry)
curl -u "$METRICS_USER:$METRICS_PASSWORD" http://localhost:8030/v1/models
# … or 8030/v1 with the plain vLLM key (8020 parity, no Basic auth needed)
curl -H "Authorization: Bearer $VLLM_API_KEY" http://localhost:8030/v1/models
curl -u "$METRICS_USER:$METRICS_PASSWORD" http://localhost:8030/metrics | grep -m1 vllm:generation_tokens_total
curl -u "$METRICS_USER:$METRICS_PASSWORD" http://localhost:8030/dcgm/metrics | grep -m1 DCGM_FI_DEV_GPU_UTIL
ssh -L 9090:localhost:9090 <host>   # then open http://localhost:9090
```

## First boot & troubleshooting

Expect a slow **first** start (subsequent starts are much faster):

- image build: vLLM + FlashInfer wheels
- container boot: FlashInfer JIT-compiles the Blackwell FP4 GEMMs (`nvcc`
  inside the container — normal), then CUDA graph capture (RAM-hungry)
- the endpoint is ready once the logs show `Application startup complete`:

```bash
docker logs -f vllm
```

| Symptom | Likely cause / fix |
|---|---|
| stuck in "Compiling kernels…" / `nvcc` | normal first boot (JIT); skipped on later boots |
| OOM crash during graph capture | lower `MAX_JOBS` / `NVCC_THREADS` (e.g. `2`) |
| port 8020/8030 in use | set `VLLM_HOST_PORT` / `GATEWAY_HOST_PORT` in `.env` (defaults `8020` / `8030`) and re-run `docker compose up -d`; only touch the `ports` in `docker-compose.yml` (and the site line in `caddy/Caddyfile`) if you also want to move the caddy container port |
| "model folder … does not exist" | `setup.sh` missing/incomplete — weights absent in `./models/` |
| HTTP 401 from the API | see [Authentication & exposure](#authentication--exposure) — `8020` requires the `VLLM_API_KEY` bearer when set; `8030` requires Basic auth, except its `/v1/*` routes also accept the plain vLLM key. 401 from 8030 right after rotating `VLLM_API_KEY`? caddy still runs the old key — caddy only picks up `.env` changes when its container is recreated |
| `/metrics` open on `:8020` | by design (vLLM only keys `/v1/*`); the 8030 telemetry routes (`/metrics`, `/dcgm/*`) stay behind Basic auth — block 8020/8030 in your firewall if you want no external exposure at all |

### Desktop host

Keep the display off the RTX 5090. Run X/Wayland (the compositor) on the
iGPU if your CPU has one (laptops: "integrated only" graphics mode in the
firmware; desktops: point the display connector at the iGPU) and leave the
RTX 5090 a pure compute card. The display server itself only books a few
MiB — it is the GUI apps that end up on the dGPU that add up and steal VRAM
from the KV pool (in the test environment a GNOME shell running on the 5090
had ~6 MiB of it booked). WSL2: the Windows desktop shares the GPU, so the
display stays on the iGPU there too. The strict version of this — the card
reserved for vLLM entirely, nothing else on it — is MTP mode:
[MTP (dedicated card)](#mtp-dedicated-card).

## Monitoring (Prometheus + Grafana)

The compose stack includes a small monitoring sidecar set — it just comes up
with `docker compose up -d`:

| Service | Port | What it does |
|---|---|---|
| `vllm` | `8020` | direct full API access (auth per [Authentication & exposure](#authentication--exposure)); caddy (8030) and Prometheus also reach it on the docker network (`vllm:8000`) |
| `caddy` | `8030` | optional gateway (expose it to host the OpenAI endpoint externally): Basic auth; the plain vLLM key is also accepted on `/v1/*` |
| `dcgm-exporter` | — | per-GPU DCGM telemetry sidecar (details in the paragraph below) |
| `prometheus` | `127.0.0.1:9090` | scrapes `vllm:8000/metrics` + `dcgm-exporter:9400` every 5 s; 1 y retention, loopback-only (remote access via SSH tunnel) |
| `grafana` | `3000` | dashboard auto-provisioned under folder **vllm** ("vLLM — Qwen3.8-27B (RTX5090)"): running/waiting requests, token throughput, TTFT / E2E / inter-token latency, KV-cache utilization, preemptions, prefix-cache hit ratio, MTP spec-decode acceptance rate / draft rates |

Grafana login: `admin` / `GRAFANA_ADMIN_PASSWORD` from `.env`.

Direct link to the dashboard (Grafana listens on all interfaces, port 3000
— from another machine on the network, replace `localhost` with the host's
IP/DNS name): `http://localhost:3000/d/vllm-qwen3827b`

![Top rows of the auto-provisioned vLLM dashboard](docs/Dashboard_Example.png)

*Top rows of the dashboard (folder **vllm**): requests running/waiting,
KV-cache utilization, TTFT p95, token counters, requests per second.*

Note the caddy gateway on 8030 does *not* route Grafana — the dashboard
is only available on 3000. To run the queries behind the panels
yourself, hit Prometheus on the loopback (`http://localhost:9090`;
remote access via the SSH tunnel described in
[Authentication & exposure](#authentication--exposure)).

Per-GPU metrics (utilization, memory, power, temps, fan, clock) are part of
the stack: the `dcgm-exporter` service (no host port) plus the `dcgm`
Prometheus job (scrapes `dcgm-exporter:9400`). The exporter is a small NVML
sidecar built from public images (`dcgm-exporter/`) that emits the official
`DCGM_FI_DEV_*` names — no nvcr.io/NGC login required; the NVML driver
library is injected into the container by the NVIDIA container toolkit.
Read them through the gateway at `http://localhost:8030/dcgm/metrics` or
query the `DCGM_*` series in Grafana Explore. Prefer the official exporter?
Replace the dcgm-exporter `build:` block in `docker-compose.yml` with
`image: nvcr.io/nvidia/dcgm-exporter:3.3.9-3.6.0-ubuntu22.04`. Not needed?
Delete the service + the `dcgm` job and `docker compose up -d`.

## Configuration

Most knobs live in `docker-compose.yml`:

| Setting | Value | Notes |
|---|---|---|
| LLM port | `8020` | direct full vLLM API host port; override with `VLLM_HOST_PORT` in `.env`, unset = `8020` (auth semantics: see [Authentication & exposure](#authentication--exposure)) |
| Gateway port | `8030` | caddy host port (Basic-auth front, for optional external exposure); override with `GATEWAY_HOST_PORT` in `.env`, unset = `8030`; container-side ports (`vllm:8000`, `caddy:8030`) stay fixed |
| `VLLM_API_KEY` | from `.env` | empty = no authentication |
| GPU | 1x, `CUDA_VISIBLE_DEVICES=0` | single RTX 5090 |
| `MAX_JOBS` / `NVCC_THREADS` | `4` | lower these on machines with less RAM |
| MTP speculative decoding | off in the base file, on via the `docker-compose.mtp.yml` override | MTP layers draft 2 tokens/step — run: `docker compose -f docker-compose.yml -f docker-compose.mtp.yml up -d`; see [Usage modes](#usage-modes) |
| `VLLM_GPU_MEMORY_UTILIZATION` | base: unset = `0.95` · MTP: unset = `0.965` | `.env` key behind `--gpu-memory-utilization`; set it to override the shipped defaults ([Usage modes](#usage-modes)) |
| `VLLM_MAX_NUM_SEQS` | base: unset = `16` · MTP: unset = `3` | `.env` key behind `--max-num-seqs` (max concurrent sequences); set it to override the shipped defaults ([Usage modes](#usage-modes)) |
| `--max-model-len` | `262144` | 256K context |
| `--kv-cache-dtype` | `fp8` | halves KV cache VRAM, longer contexts |
| `--trust-remote-code` | — | required by the NVFP4 (modelopt) config |
| `--speculative-config` | — (base) | in the MTP override it is `{"method": "mtp", "num_speculative_tokens": 2}` (draft length 2, tune to 3 if the workload benefits) |
| `shm_size` | `16gb` | needed for multi-process workers |

## Switching the model

The Docker image only ships vLLM — no model is baked in. Both `setup.sh` and
`docker compose` read the `.env` keys below; unset keys keep the defaults for
the stock Qwen3.8-27B NVFP4 model:

| Key | Meaning | Default |
|---|---|---|
| `MODEL_REPO` | Hugging Face repo to download | `gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090` |
| `MODEL_SUBDIR` | local weights dir under `./models/` (and the container mount) | `qwen3.8-27b-nvfp4` |
| `SERVED_MODEL_NAME` | value for `--served-model-name` | `qwen3.8-27b` |
| `CONTAINER_NAME` | container name | `vllm` |
| `MODEL_REVISION` | Hugging Face revision to download (weights pin, `setup.sh` only) | `0cc27958…` (known-good, 2026-08-22) |

Set `MODEL_REVISION=` (empty) in `.env` if you would rather have `setup.sh`
always download the latest weights.

To serve a different model:

1. set `MODEL_REPO` + `MODEL_SUBDIR` (+ `SERVED_MODEL_NAME`) in `.env`
2. `sudo ./setup.sh` — downloads the weights into `./models/$MODEL_SUBDIR/`
3. `docker compose up -d` (the image is model-agnostic; no rebuild needed)

Model-specific serve flags (`--quantization`, `--kv-cache-dtype`, parsers, …)
deliberately stay explicit in `docker-compose.yml`. If your model needs
different ones, provide a full replacement of the `command` list in a second
file, e.g. `mymodel.yml`, and run
`docker compose -f docker-compose.yml -f mymodel.yml up -d`.

## Pinned versions

Everything that could break a rebuild is pinned — the Python stack is the
full lock of the known-good production container (frozen 2026-08-15, vllm
bumped to 0.28.0 on 2026-09-04):

| Input | Pinned | Where |
|---|---|---|
| vLLM stack (vllm 0.28.0, FlashInfer, CUTLASS DSL, torch, … 196 packages) | `requirements.lock` | `Dockerfile` |
| uv / Python | `0.12.5` / `3.13.15` | `Dockerfile` |
| CUDA base image | `13.3.1-devel-ubuntu22.04` | `Dockerfile` |
| huggingface_hub (model download CLI) | `1.27.0` | `setup.sh` |
| NVIDIA container toolkit | `1.20.0-1` | `setup.sh` |
| Model weights | HF revision `0cc27958…` (2026-08-22) | `setup.sh` (override: `MODEL_REVISION`) |
| Host driver (tested) | `610.43.02` (RTX 5090) | — |
| caddy (API gateway, monitoring) | `2.11.4-alpine` | `docker-compose.yml` |
| dcgm-exporter (GPU metrics sidecar) | `python:3.13-slim` + `nvidia-ml-py 13.610.43` | `dcgm-exporter/Dockerfile` |
| prometheus (metrics) | `v3.13.2` | `docker-compose.yml` |
| grafana (dashboards) | `11.1.4` | `docker-compose.yml` |

Updating the pins: change the relevant lines, rebuild the image, re-run the
smoke test (`curl /v1/models` + a short chat), and commit. For a new
stack, regenerate the lock from a working container:
`docker exec <container> sh -c 'cd /app && uv pip freeze' > requirements.lock`
(keep only the `package==version` lines).

## Project layout

```
Dockerfile                          vLLM + flashinfer + CUTLASS DSL image (NVFP4)
requirements.lock                   frozen Python stack of the known-good container (196 packages)
docker-compose.yml                  service definition (ports, volumes, serve flags; light mode)
docker-compose.mtp.yml              MTP override file (ideal-usage tuning: 3 seqs / 0.965, dedicated card)
setup.sh                            host prerequisites + model download (~19 GB)
.env.example                        secret template (copy to .env)
AGENTS.md                           build/verification commands + gotchas for AI agents
CONTRIBUTING.md                     commit style (Conventional Commits)
LICENSE.md                          MIT license for this repo's tooling
benchmarks/context_bench.py         context-size performance suite (TTFT / prefill / decode per size)
benchmarks/parallel_bench.py        concurrent-requests throughput suite (aggregate tok/s vs concurrency)
# raw runs of both suites land in benchmarks/results/
caddy/Caddyfile                     gateway: /v1/* (Basic or the vLLM key), /metrics, /dcgm/metrics (port 8030)
prometheus/prometheus.yml           Prometheus scrape config (vllm + dcgm jobs)
grafana/                            auto-provisioned datasource + vLLM dashboard
dcgm-exporter/                      NVML → Prometheus sidecar (DCGM_FI_DEV_* names, no NGC login)
docs/Dashboard_Example.png          dashboard screenshot referenced in Monitoring
models/qwen3.8-27b-nvfp4/           model weights (empty in git, filled by setup.sh)
```

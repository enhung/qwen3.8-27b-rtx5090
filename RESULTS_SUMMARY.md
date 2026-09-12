# 結果摘要

| 指標 | 值 | 證據等級 |
|---|---:|---|
| Light 單流 decode | 約 82–86 tok/s | Handoff 記錄；本次未重測 |
| 4 clients aggregate | 約 279 tok/s | Handoff 記錄；server `max-num-seqs=4` |
| 8 clients aggregate | 約 284 tok/s | Handoff 記錄；含排隊，非 GPU 並行上限 |
| API ready | 約 14m48s | Handoff 記錄；需同條件 cold/warm 實驗 |
| Thinking ON 700-token sample | 約 7.9 tok/s，無 final content | Handoff 單次觀察，不能推論普遍慢 10× |
| P1 middleware / entrypoint / verifier 本地測試 | 7/7 pass | 本地驗證，非 GPUtw live 驗收 |
| P1 image GitHub Actions build / GHCR push | pass；digest `sha256:e8b34e248f7a97758df88dd50d312bbb321c3b5daecd0f3982187c812312c7a0` | Image build 證據，非 GPUtw live 驗收 |
| P1 GPUtw live localhost auth matrix | 10/10 pass | 117 GB RTX 5090；Vault key 僅在容器內使用 |
| P1 chat completion / Agent tool-choice | chat 200；`get_weather` tool call 成功 | 容器 localhost smoke；非完整 Hermes continuation |
| P1 public unauthenticated routes | `/health`、`/v1/models` 401；`/invocations`、`/metrics`、`/docs` 404 | 外部 GPUtw endpoint；valid-key 外部 path 待受信 client |
| Agent tool loop | tool call 200 → tool result continuation 200 → final answer；15 completion tokens | GPUtw live container-local run |
| Context sanity | 8K: 8,208 prompt tokens / 0.673 s；32K: 32,784 / 2.925 s；均 200 | GPUtw live container-local run |
| Parallel sanity | 2 concurrent requests，均 200；wall 0.930 s | GPUtw live container-local run |
| Persistent instance readiness | `RUNNING` / `ready=true` / restart 0；117 GB RAM、8 GB shm；vRAM 90.3% | GPUtw resource snapshot；instance `c2b173c7…` |
| Warm/prefix-cache signal | 同一約 8K prompt：首 byte 1.034 s → 0.162 s；total 1.112 s → 0.240 s | 同一 persistent container localhost streaming run；非 cold start |

下一輪評估以 **Agent 工作完成時間、成功率與每個完成工作成本** 為主要結果；TTFT、decode、tool-call 合法率、131K 長文與 CUDA/Xid 是診斷/驗收指標。原始本地驗證見 `evidence/2026-09-12-local-validation.txt`，image build 證據見 `evidence/2026-09-12-actions-build.txt`，GPUtw live gate 見 `evidence/2026-09-13-gputw-p1-live-gate.txt`。

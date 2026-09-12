# GPUtw / Qwen3.8-27B：目前狀態（2026-09-12）

## 已確認

- 本 repo 來自 `enhung/qwen3.8-27b-rtx5090` 的 `main`，基準 commit：`207222ca131da2b488bcc1b9490edd1fb5e43777`。目前工作分支 `codex/gputw-agent-p1-auth`；沒有修改 `main` 或 v2 image。
- repo 的 `entrypoint-gputw.sh` 將模型下載固定在 revision `0cc27958cefbbe231782ec8511de8c4eb5233348`，再從本地目錄啟動。現有檢查只看 `config.json`，**不是**對整個 snapshot 的完整性證明。
- repo 的通用 `docker-compose.yml` 預設 262144 context、16 seq、`MAX_JOBS=4`，**不是** handoff 中 GPUtw 實測的 Light profile；GPUtw 應使用 `gputw/SAFE_BASELINE.sh` 中的 131072 / 4 seq / 2 jobs 設定。
- vLLM 0.28.0 官方說明確認 `VLLM_API_KEY` 只保護部分路徑，`/invocations` 等路徑不受其保護。[來源](https://docs.vllm.ai/en/v0.28.0/usage/security/)
- 本執行環境沒有 `GPUTW_API_KEY`、Docker 或 RTX 5090；因此尚無任何本次 live GPUtw / Hermes 驗收結果。

## Handoff 記錄，尚未由本次重新測量

- GPUtw：1× RTX 5090 32 GB，成功 host 24 CPU / 約 117 GB RAM；`/vault` 保留，`/workspace` 不保留，RUNNING 時計費。
- 已工作的 image：`ghcr.io/enhung/qwen38-rtx5090:v2`；模型是 `gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090` 的上述 revision，本地 `/vault/qwen38/models/qwen3.8-27b-nvfp4`。
- Light：vLLM 0.28.0、ModelOpt NVFP4、FP8 KV、FlashInfer Blackwell FP4、131072 context、MTP 關閉、單流約 82–86 tok/s，API ready 約 14m48s；Hermes 已成功連線。
- P1 缺口：port 8000 曾公開，且當時 vLLM 無服務層金鑰。

## 當前判斷

P1 候選實作已寫入工作樹，但**尚未 build、部署或驗證外部端點**。Go/no-go 仍是 **NO-GO for production**，直到 `SECURITY.md` 的 live gate 完成。下一個工程變數只應是 P1 auth；cache、機型與 lifecycle 暫不混入。

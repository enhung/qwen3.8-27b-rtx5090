# GPUtw 環境與凍結設定

來源：handoff v2 的既有系統記錄；本次沒有登入 GPUtw 重新量測。

| 項目 | Light baseline |
|---|---|
| GPU / host | 1× RTX 5090 32 GB；已成功 host 約 117 GB RAM |
| image / vLLM | `ghcr.io/enhung/qwen38-rtx5090:v2` / 0.28.0 |
| model / revision | `gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090` / `0cc27958cefbbe231782ec8511de8c4eb5233348` |
| persistent model | `/vault/qwen38/models/qwen3.8-27b-nvfp4` |
| env | `MODEL_DIR` 如上；`MAX_JOBS=2`；`NVCC_THREADS=2` |
| serving | `qwen3.8-27b`、`0.0.0.0:8000`、131072 context、`max-num-seqs=4`、GPU utilization 0.95 |
| inference | FP8 KV、prefix caching ON、`qwen3` reasoning parser、`qwen3_xml` tool parser、auto tool choice ON、MTP OFF |

完整旗標可在 [gputw/SAFE_BASELINE.sh](gputw/SAFE_BASELINE.sh) 核對。P1 image 繼承 v2，加入 auth middleware，並在 GPUtw 未提供 args 時使用這組 Light 旗標；若現有部署有 args，則原樣傳遞。2026-09-12 從公開 GHCR manifest HEAD 取得 v2 digest：`sha256:6f2f5c227aea70f48cd53c650626640723d6a93cca4b2bdf6865058c71cb0298`，並已固定在 P1 Dockerfile；新 image 尚未 build。供應商 `customImage.args` 可覆蓋 CMD、保留 ENTRYPOINT；正式建立 instance 時需對照上述 argv。[GPUtw API 文件](https://docs.gputw.ai/docs/rest-api-quickstart)

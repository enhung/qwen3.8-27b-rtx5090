# 決策記錄

| 日期 | 決策 | 理由 / 邊界 |
|---|---|---|
| 2026-09-12 | 保留 v2 作 rollback，P1 用 `Dockerfile.gputw-auth` 繼承 v2 | 避免重建或升級已工作的 CUDA / vLLM / model stack；新 image 需另標版本，不覆蓋 v2。 |
| 2026-09-12 | P1 同時使用 vLLM key 與全路徑 ASGI middleware | vLLM 0.28.0 的 key 並不保護 `/invocations` 等路徑；middleware 只允許 Hermes 必需路徑與 authenticated health。 |
| 2026-09-12 | Light 維持預設；MTP / thinking ON 暫不啟用 | Handoff 的 Light Agent 使用已足夠，thinking 曾發生無 final content 與低完成速度；先以工作成功率判斷。 |
| 2026-09-12 | P2 cache、P3 便宜 host、P4 lifecycle 分階段測 | 每次只改一個主要變數，先驗證 P1 不退化再做其他實驗。 |

未決：GPUtw 正式啟動新 image 的部署權限、live endpoint 與 secret file 狀態；53 GB RAM 機型的啟動尖峰；GPUtw 停止後是否可原 instance 重新啟動，需依實際 API / 帳號測試，不能從文件推定。

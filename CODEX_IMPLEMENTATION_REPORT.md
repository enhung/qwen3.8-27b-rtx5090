# Codex 實作報告（2026-09-12）

## 結論

**P0 基線文件化與 P1 auth image 已完成；production NO-GO。** P1 image 已由 GitHub Actions 建置並發佈，但尚未在 GPUtw live instance 驗收。這是刻意分開 P1 與後續 cache / host / lifecycle 變數；本次環境沒有 GPUtw key、Docker 或 5090，不能將 image build 當成 live 驗收。

## 本次已做

- 從公開 fork 的 `207222ca131da2b488bcc1b9490edd1fb5e43777` 建立工作分支，保留 `main` 與 v2 image。
- 比對 handoff 與 repo：發現通用 Compose 的 256K / 16 seq / 4 jobs 跟 GPUtw Light 的 131K / 4 seq / 2 jobs 不同；凍結 GPUtw profile 在 `gputw/SAFE_BASELINE.sh`。
- 查 vLLM 0.28.0 官方文件，確認單用 `VLLM_API_KEY` 不能保護 `/invocations` 等路徑。[vLLM 0.28.0 security](https://docs.vllm.ai/en/v0.28.0/usage/security/)
- 新增以 v2 為 base 的獨立 P1 image、從 `/vault` 載入 key 的 fail-closed entrypoint、只允許 Hermes 必要路徑的 Bearer middleware，以及不輸出憑證的外部 auth 驗證腳本；沒有寫入任何實際金鑰。
- 新增只在 P1 功能分支 push 時建置的 GitHub Actions workflow；以 repo `GITHUB_TOKEN` 推送獨立 tag，避免依賴本機 Docker。run `34719491022` 已成功。
- 新增 Agent on-demand、成本、Hermes 驗收與回退文件；參照 [GPUtw API](https://docs.gputw.ai/docs/rest-api-quickstart) 與 [runtime status](https://docs.gputw.ai/zh-TW/docs/instance-runtime)。

## 驗證與缺口

`python3 -m unittest discover -s tests -v`：7/7 pass。`bash -n`、`py_compile`、whitespace check：pass。完整輸出見 `evidence/2026-09-12-local-validation.txt`。公開 GHCR manifest / config 查詢確認 v2 image 的 ENTRYPOINT 為 `/app/entrypoint-gputw.sh`、工作目錄為 `/app`，見 `evidence/ghcr-v2-image.txt`。

已從公開 GHCR 查得 v2 manifest digest 並固定在 P1 Dockerfile。GitHub Actions run `34719491022` 的 7 個測試、Docker build、容器內 middleware import / entrypoint 檢查及 GHCR push 全部成功；P1 image 為 `ghcr.io/enhung/qwen38-rtx5090:p1-auth-31a67e3732b70d05c7c1b758129585d0320b6539-34719491022@sha256:e8b34e248f7a97758df88dd50d312bbb321c3b5daecd0f3982187c812312c7a0`，證據見 `evidence/2026-09-12-actions-build.txt`。此任務環境尚未取得 `GPUTW_API_KEY`，也沒有 Docker 或 5090。尚缺：GPUtw live 外部 auth matrix、Hermes 真實 tool loop、long context、啟動與費用證據。安全路徑 allowlist 只根據 handoff 的 Chat Completions 行為；若 Hermes 走 `/v1/responses` 等路徑，必須用真實 trace 證明後再增加。Handoff 的價格、效能與 RAM 是既有記錄，本次未重測。

## 下一個可執行關卡

1. 依 `P1_DEPLOYMENT_RUNBOOK.md`，用已固定 digest 的 P1 image 在原 117 GB host / 同一 pinned model、同一 Light flags 啟動隔離 instance；確認 `/vault` key file 存在但不讀出內容到 log。
2. 執行 `SECURITY.md` 的外部 auth matrix 與 `HERMES_SETUP.md` 的 tool loop；只有全通過才切 Hermes endpoint。
3. 然後才進入 P2 cache 路徑發現與 cold/warm 測試，再做 53 GB host 資格與 P4 on-demand。每階段保留 raw evidence 與 v2 rollback。

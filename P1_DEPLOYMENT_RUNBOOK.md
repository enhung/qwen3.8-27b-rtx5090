# P1 獨立部署執行清單

此清單只處理 API auth。先在已成功的約 117 GB RAM / 1× RTX 5090 host 測試，不同時加入 cache、53 GB SKU、MTP 或 on-demand。v2 image 與 `/vault` pinned model 保留作回退。

## 1. 建置與發佈新 image

**本次首選 GitHub Actions**：`.github/workflows/build-gputw-p1-auth.yml` 只在推送 `codex/gputw-agent-p1-auth` 分支時自動執行，使用 pinned `actions/checkout`、GitHub hosted Docker 與 repo `GITHUB_TOKEN`；不需本機 Docker。GitHub 的 `workflow_dispatch` 要求 workflow 先存在預設分支，所以首次建置使用分支 push。workflow 有 30 分鐘上限，依 commit SHA / run ID 產生獨立 P1 tag，先跑 7 個本地測試和 image import/entrypoint 檢查，才推送 GHCR。若既有 GHCR package 未連結此 repo，`GITHUB_TOKEN` 可能無 push 權限；要先確認 package 授權，不能把 token 或私人 PAT 放入 repo。[GitHub GHCR 權限說明](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

以下是有獨立 Docker host 時的替代建置流程：

在可使用 Docker 且有 GHCR push 權限的 x86_64 環境：

```bash
P1_IMAGE="ghcr.io/enhung/qwen38-rtx5090:p1-auth-$(date -u +%Y%m%dT%H%M%SZ)"
docker build --platform linux/amd64 -f Dockerfile.gputw-auth -t "$P1_IMAGE" .
docker run --rm --entrypoint python "$P1_IMAGE" -c 'import gputw_auth_middleware; print("middleware import OK")'
docker image inspect "$P1_IMAGE" --format '{{json .Config.Entrypoint}}'
# 確認輸出為 /app/entrypoint-auth.sh，再以已授權的 GHCR 帳號登入並發佈：
docker push "$P1_IMAGE"
docker buildx imagetools inspect "$P1_IMAGE"
```

記錄 **P1 digest**；後續 GPUtw `customImage.dockerImage` 使用 `tag@sha256:...`，不要只用可變 tag。v2 rollback digest 已在 `ENVIRONMENT.md` 固定。此處沒有指定登入命令，避免金鑰被放進 shell history、log 或文件。

## 2. 建立隔離的 GPUtw P1 instance

先讀取 GPUtw 當下可用的 1× RTX 5090 host、RAM 與實際時費率，並設定這次測試的**最大 RUNNING 時間 / 預算**。建立新 instance，不覆蓋現有 v2；可能有短暫雙重計費。

- Image：上述 P1 digest；不在 GPUtw env 注入 API key。預設 entrypoint 會從 `/vault/qwen38/config/api_key` 載入。
- `MODEL_DIR=/vault/qwen38/models/qwen3.8-27b-nvfp4`、`MAX_JOBS=2`、`NVCC_THREADS=2`。新 image 未提供 args 時自動使用 profile supervisor 的 `light`（131072 / 4 seq）設定；SSH 可用 `/app/switch-profile.sh light16` 或 `mtp16` 在同一 instance 重啟 vLLM 子程序，若沿用 v2 的 args 則 supervisor 不會介入，需逐一核對 argv。
- 只開 HTTP 8000；確認 GPUtw 的 port access 模式與 HTTPS endpoint。部署前不啟用額外 raw TCP/UDP exposure。
- 記錄 instance ID、image digest、node/SKU、起始時間、上限時間與 endpoint；不記錄 key。

以 [GPUtw status API](https://docs.gputw.ai/zh-TW/docs/instance-runtime) 觀察 `deployPhase`、Pod readiness、錯誤及重啟數；只有 authenticated `GET /health` 回 200 才視為 API ready。若缺 key file，P1 應 fail-closed，不應改回無 auth 的 v2 公開入口。

## 3. 外部驗收與切換

在可從外部連到 GPUtw HTTPS endpoint 且已有 `VLLM_API_KEY` 環境變數的受信環境執行：

```bash
python3 gputw/verify_auth.py \
  --origin 'https://<GPUtw-endpoint-host>' \
  --expected-host '<GPUtw-endpoint-host>'
```

腳本不輸出金鑰或 response body；成功時輸出 10 個路徑/認證狀態，exit 0。另以 Hermes 完成串流聊天、至少一個 tool call → tool result → final answer、重連與長 context 試驗。保留遮罩後的 status / 時間 / GPUtw runs 證據。全部通過才切換 Hermes endpoint；失敗即依 `ROLLBACK.md` 返回 v2 的**受限網路入口**，不可將不完整驗證的 v2 對外公開。

## 4. 關閉測試與成本核對

達到最大 RUNNING 時間、測試完成或失敗後，先確認沒有 active Agent/tool loop，再停止**P1 測試 instance**；用 GPUtw runs API 核對實際時數和費率。[GPUtw create/stop API](https://docs.gputw.ai/docs/rest-api-quickstart) 僅在有對應 scoped key 的環境使用。不要刪除 `/vault` 模型、config 或 v2 rollback。

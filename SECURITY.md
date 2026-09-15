# GPUtw P1 API 安全設計與驗收

## 已確認的風險

Handoff 記錄 port 8000 曾公開，當時無服務層 key。vLLM 0.28.0 官方明確指出 `--api-key` / `VLLM_API_KEY` 只保護部分路徑；`/invocations` 等仍可提供推論而無需此 key。因此只加入環境變數無法完成 P1。[vLLM 0.28.0 security](https://docs.vllm.ai/en/v0.28.0/usage/security/)

## P1 候選實作

- `Dockerfile.gputw-auth` 以已工作 v2 為 base；不更動其模型、vLLM 或 CUDA。正式 build 請使用獨立、不可覆蓋 v2 的 tag，並記錄新舊 image digest。
- `gputw/entrypoint-auth.sh` 預設 `/vault` model 路徑與 2 個編譯 jobs；未提供 GPUtw args 時交由 `profile-supervisor.sh` 啟動 Light/MTP profile。它必須能讀 `/vault/qwen38/config/api_key` 的單行非空 token，否則容器啟動失敗；只將 token 放進 process environment，不印到 log 或 argv。`/vault/qwen38/config` 權限應限制為推論程序可讀、其他使用者不可讀。
- `gputw/auth_middleware.py` 對 GET `/health`、GET `/v1/models`、POST `/v1/chat/completions` 要求單一有效 Bearer header；其他 HTTP 路徑 404，WebSocket 關閉。vLLM 自身的 key 驗證保留作第二層。
- TLS 仍由 GPUtw HTTPS endpoint 承擔；正式環境應只曝光必要 HTTP port。此實作不代替供應商網路隔離與限流。

### 同一 instance 的 profile 切換

無 args 啟動的 image 以 supervisor 作為 PID 1，vLLM 是其子程序。SSH 進入 instance 後可執行 `/app/switch-profile.sh light16` 或 `/app/switch-profile.sh mtp16`；腳本會把選擇寫入 `/vault/qwen38/config/profile` 並送 HUP，讓 supervisor 優雅停止舊 engine、重新啟動新 profile。`light` 是保守 fallback。切換期間 health 會暫時不可用，只有 authenticated health 回 200 才算 ready；若 profile 無效，supervisor 會回到 Light。

## Live hard gate（目前未執行）

在持有金鑰且可連到 GPUtw HTTPS endpoint 的環境，以 `VLLM_API_KEY` 環境變數或本機單行 key file 提供憑證，執行：

```bash
python3 gputw/verify_auth.py \
  --origin 'https://<GPUtw-endpoint-host>' \
  --expected-host '<GPUtw-endpoint-host>'
```

腳本只接受與另行指定的 `--expected-host` 完全相符的 HTTPS origin；操作人員仍須從 GPUtw 控制台獨立核對該 hostname。腳本只輸出狀態碼與耗時，不輸出憑證或回應內容。腳本通過仍需另外做 Hermes 真實 tool loop 與 provider port 檢查。

| 測試 | 合格條件 |
|---|---|
| 無 key / 錯 key `/v1/models`、`/health` | 401 |
| 有效 key `/v1/models`、`/health` | 200 |
| `/invocations`、`/metrics`、`/docs`（含有效 key） | 404 |
| HTTPS Hermes 串流聊天及 tool loop | 完整成功 |
| 重啟 / 新 instance | key 持續有效；沒有 key 外洩；baseline flags 未變 |
| 外部 port 掃描與 log / Git 檢查 | 無旁路入口、無 secret、無非預期公開 port |

驗收只能記錄 HTTP status、時間、request ID 與經遮罩後的錯誤；不可把 key、完整 Authorization header、含私密內容的 prompt 或原始工具資料寫入報告。若任何 unauthenticated 推論路徑仍可用，回退並維持對外端口關閉。沒有 live gate 前是 **NO-GO**。

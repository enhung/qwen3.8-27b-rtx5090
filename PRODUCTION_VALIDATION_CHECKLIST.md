# Qwen3.8-27B Production 驗證清單

此清單用於把 P1 live 結果提升到 production decision。驗證沿用目前的 GPUtw instance，不重新部署。

## 固定對象

- Instance：`c2b173c7-b356-45fd-babb-bf606b017bf0`
- GPU：1× RTX 5090 32GB、117 GB RAM
- Image：`ghcr.io/enhung/qwen38-rtx5090:p1-auth-31a67e3732b70d05c7c1b758129585d0320b6539-34719491022@sha256:e8b34e248f7a97758df88dd50d312bbb321c3b5daecd0f3982187c812312c7a0`
- HTTPS endpoint：`https://8000-c2b173c7-b356-45fd-babb-bf606b017bf0.gputw.ai`
- Model：`qwen3.8-27b`
- 下次部署：沿用上述 image digest 與 `/vault`，設定 `customImage.sshEnabled: true`；SSH 使用 `pod-<new-instance-id>@ssh.gputw.ai -p 2222`。
- Cold-start 預算：至少 17 分鐘；`STARTING` / JIT 編譯期間不提前判定失敗，只有 authenticated `GET /health` 回 200 才算 ready。

## Gate 順序

1. 從受信外部 client 確認 endpoint hostname 與 GPUtw 控制台一致，並以單行 key file 執行：

   ```bash
   python3 gputw/verify_auth.py \
     --origin 'https://<verified-endpoint-host>' \
     --expected-host '<verified-endpoint-host>' \
     --key-file '<one-line-key-file>'
   ```

   腳本只輸出 status、耗時與 pass/fail，不輸出 key、Authorization header 或 response body。10 個 cases 必須全部通過。

2. 使用同一 endpoint 做 Hermes 真實串流驗收：普通問答一次，以及 `tool call → tool result → final answer` 一次。記錄完成時間、HTTP status、token 數與工具次數；不要記錄 prompt、工具資料或憑證。

3. 做一次重連/恢復驗收：只在完成前兩項後重啟或切換 instance，確認 Hermes 重新取得新 endpoint，並重跑最小 tool loop。

4. 核對 GPUtw runs 的實際費率與 RUNNING 時間，再決定是否切 production。任何一項失敗都維持 **NO-GO**。

## 目前已知阻塞

Container-local auth、chat、tool loop、8K/32K context、雙併發與 warm/cache 已通過。GPUtw Web UI HTTPS proxy 即使在 `public` port 模式仍回 platform-level 401，因此尚未證明 bearer key 能從外部穿透到 middleware；暫時 raw TCP exposure 測試後已刪除。Production gate 必須由真正可通過該平台層的受信 client 完成，不能以 localhost 結果替代。

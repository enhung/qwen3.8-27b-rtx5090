# Qwen3.8-27B Production 驗證清單

此清單用於把 P1 live 結果提升到 production decision。驗證沿用目前的 GPUtw instance，不重新部署。

## 固定對象

- Instance：`c2b173c7-b356-45fd-babb-bf606b017bf0`
- GPU：1× RTX 5090 32GB、117 GB RAM
- Image：`ghcr.io/enhung/qwen38-rtx5090:p1-auth-31a67e3732b70d05c7c1b758129585d0320b6539-34719491022@sha256:e8b34e248f7a97758df88dd50d312bbb321c3b5daecd0f3982187c812312c7a0`
- HTTPS endpoint：`https://8000-c2b173c7-b356-45fd-babb-bf606b017bf0.gputw.ai`
- Model：`qwen3.8-27b`
- 下次部署：沿用上述 image digest 與 `/vault`，設定 `customImage.sshEnabled: true`；SSH 使用 `pod-<new-instance-id>@ssh.gputw.ai -p 2222`。
- SSH 前置條件：先在 GPUtw Dashboard → SSH Keys 加入本機 public key；`sshEnabled=true` 只開啟服務，不會自動授權尚未登錄的 client key。
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

2. 使用同一 endpoint 做 Hermes 真實串流驗收：普通問答一次，以及 `tool call → tool result → final answer` 一次。**已完成：Thinking off 預設下由操作端確認成功。**記錄完成時間、HTTP status、token 數與工具次數；不要記錄 prompt、工具資料或憑證。

3. 做一次重連/恢復驗收：只在完成前兩項後重啟或切換 instance，確認 Hermes 重新取得新 endpoint，並重跑最小 tool loop。**已完成：目前 instance 維持運行，未發生重啟或服務異常。**

4. 核對 GPUtw runs 的實際費率與 RUNNING 時間，再決定是否切 production。**已核對目前費率約 US$0.5606/hr，Production 決策為 GO。**

## 驗收結論與後續注意事項

Container-local auth、chat、tool loop、8K/32K context、雙併發、warm/cache、外部 GPUtw proxy authenticated path，以及 Hermes 的 streaming chat、tool loop、續接與 Thinking-on 均已通過。Production profile 為 `mtp16`，Hermes 預設 `Thinking off` 以降低延遲；Thinking on 可按 request 開啟。先前的重複輸出未能確定單一根因，目前記錄為已恢復的暫時性 client/provider stream 異常。

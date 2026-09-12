# Hermes / Agent 驗收設定

Handoff 記錄的已工作設定：OpenAI Compatible；Base URL 為 GPUtw HTTPS endpoint + `/v1`；model `qwen3.8-27b`；context 131072；initial max output 8192；streaming ON；tool/function calling ON、auto；`enable_thinking=false`。API key 由 Hermes 的安全設定載入，不放入 repo、命令列或測試紀錄。

P1 live 驗收順序：

1. 從外部對 `/v1/models`、`/health` 發送無憑證請求，均須 401；對 `/invocations`、`/metrics`、`/docs` 即使帶有效憑證也須 404。
2. 帶有效 Bearer key 對 `/health`、`/v1/models` 須成功；錯誤 key 須 401。
3. Hermes 串流一輪普通問答與一輪實際工具呼叫 → 工具結果回填 → final answer；確認 tool-call JSON / XML parser 正常、沒有 repetition collapse。
4. 同一 Agent 工作重啟 GPU 後再跑，確認 Hermes 使用新 endpoint / instance ID 可恢復。
5. 後續 P5 準備 10–20 個固定案例：問答、coding、單/多工具迴圈、工具等待續接、並行請求、長 context（含 output headroom）、Personal AI OS / deepArchive。每案記錄成功、總時長、token、工具次數與錯誤。

P1 allowlist 目前只包含 Chat Completions 與 Models。若 Hermes 其實依賴其他 `/v1` 路徑，先從 live trace 證明，再擴充一條路徑並重新測試；不要先打開整個 `/v1/*`。

# Qwen3.8-27B 在 Agent 應用的部署評估

**建議：先維持已工作的 GPUtw Light profile，完成 P1 外部 API 驗證後供 Hermes 使用；暫不把 on-demand 當成同步即時請求的預設路徑。** 原因是 handoff 記錄的冷啟動約 14m48s，對互動式 Agent 是可感知的長等待；另一方面現有單流約 82–86 tok/s 已足夠，下一步應優化完成一項真實工作所需的總時間與成本，而不是追求最高 decode 數字。

## 方案比較

| 方案 | 優點 | 主要風險 | 決策 |
|---|---|---|---|
| 直接保留公開 v2 | 零遷移、既有效能 | vLLM 未保護的推論路徑可能外露 | 不接受作 production Internet endpoint |
| P1 安全版 + 117 GB 已成功 host、先持續運行 | 單一變數，可驗證 Hermes 回歸與長 context | RUNNING 持續計費；外部 valid-key path 尚待 Hermes/受信 client 驗證 | **第一階段推薦** |
| P1 + 53 GB 便宜 host | 可能降低時費率 | JIT/graph 啟動 RAM 峰值未通過；失敗重試增加成本 | 待 P3 真 cold start 資格通過 |
| P1 + Gateway on-demand | 降低閒置 GPU 時數 | 首次工作等待、instance/endpoint 變動、錯誤停機 | P2 已量到 warm/cache；P4 lease 機制仍待驗證 |
| MTP / thinking 預設開啟 | 可能改善特定請求 | correctness、tool calling、記憶體與完成時間未驗證 | 只做隔離實驗，Light 保持 fallback |

## Agent 專用驗收標準

一個成功案例必須包含 **收到工作 → 模型回覆/工具呼叫 → 工具執行 → 結果續接 → final answer**。記錄 P50/P95 完成時間、成功率、重試率、每個完成工作的實際 GPUtw 費用、TTFT、token、工具呼叫格式正確率、冷/暖啟動時間、排隊等待與停止誤判。長 context 測試必須留輸出 headroom；131072 是設定值，不能只憑啟動旗標宣稱端到端已驗證。

最初 10–20 個固定案例涵蓋普通聊天、coding、單/多工具、工具等待後續接、併行、長 context、Personal AI OS / deepArchive。Thinking OFF 是現階段標準；Thinking ON 以同一 prompt A/B，分別記錄 reasoning/content token、最終答案與工具成功，而不是只看 tok/s。四/八 client 測試時，需同時記錄 server `max-num-seqs`，避免把排隊誤判成硬體上限。

## 分階段 Go / No-Go

1. **P0/P1：安全且可回退。** 固定 v2 digest、模型 revision 與 Light flags；P1 新 image 不覆蓋 v2。從外部證明無 key 401、合法 key 成功、`/invocations` 等非允許路徑 404、Hermes tool loop 成功。任何 bypass 或 parser regression 都不切流量。
2. **P2：啟動時間。** 先找出實際 vLLM/torch/FlashInfer/Triton cache 路徑及權限，再在同一 host/image 分別量 cold 與 warm time-to-authenticated-health。cache 應與 runtime / GPU 架構版本相容，不跨不可信 host 盲目複製。[vLLM cache 安全說明](https://docs.vllm.ai/en/v0.28.0/usage/security/)
3. **P3：機型成本。** 以未改的 Light profile 測 53 GB RAM SKU 的啟動峰值、長 context、Hermes 與真實 runs 費率。任何 OOM / 重啟不穩即拒絕，不能用 steady-state RAM 代替資格。
4. **P4：on-demand。** 固定 Gateway、single-flight 建立、authenticated readiness、Agent/tool continuation lease、20–30 分鐘安全 idle、最大 RUNNING/費用保護、stop 失敗恢復與 endpoint 重新發現。若冷啟動仍約 15 分鐘，產品需提供「工作排隊/準備中」體驗或預熱時窗，不應承諾即時回覆。
5. **P5–P9：工作品質優先。** 先通過 Hermes 代表性案例，再診斷 thinking；MTP、`max-num-seqs` 與 KV 實驗各自獨立，對照 Light 的完成時間、成功率與成本。

**當前狀態：**P1 已在 GPUtw 117 GB RTX 5090 `RUNNING` 驗證：容器 localhost auth matrix 10/10、chat completion 200、tool-choice 與完整 tool loop 成功，8K/32K context 與雙併發 sanity 通過，公開端點未授權路徑符合 401/404。instance `c2b173c7…` 另完成 cache 路徑盤點與重複 8K prompt（首 byte 1.034 s → 0.162 s）觀察，現已停止。外部 valid-key 與 Hermes 實際 continuation 尚待受信 client 驗證，因此 production 仍 **NO-GO**。完整證據見 `evidence/2026-09-13-gputw-p1-live-gate.txt`。

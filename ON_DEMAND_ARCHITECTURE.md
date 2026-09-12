# Agent 應用的 GPUtw On-Demand 架構（P4，未實作）

Agent 對外只連固定的 Gateway。Gateway 持有 durable run/lease 狀態與供應商 scoped key；每次 GPUtw instance 變更後重新發現 HTTPS endpoint，先以 authenticated `/health` 驗證，再轉送 Hermes 的 OpenAI-compatible 請求。不要把暫時性的 GPUtw URL 寫死在 Agent 設定。

| 狀態 | 進入條件 | 允許動作 |
|---|---|---|
| STOPPED | 無有效 instance | 接到工作後，鎖定 single-flight 部署；查可用容量、價格、預算，再 create/start |
| STARTING | GPUtw 正在配置或 image 啟動 | 輪詢 instance status；等待 authenticated health；超時/失敗進入 FAILED |
| READY | health 成功且 endpoint 已發現 | 接受 Agent run，建立 lease；串流轉送並記錄 in-flight |
| DRAINING | 到達 idle timeout / 成本限制 | 停接新工作；等待所有 active run、LLM request、tool call 與預期工具結果續接的 lease 結束 |
| STOPPING | drain 完成 | idempotent stop；輪詢至 STOPPED；更新實際計費區間 |
| FAILED | start/health/stop 失敗 | 有界重試、告警；不得在狀態不明時重複 create 或誤停別的 instance |

**安全停機條件**：`active_runs=0`、`inflight_llm=0`、`pending_tool_continuations=0`，且距離最後活動達 20–30 分鐘。lease 由 Gateway 在 Agent run 開始時建立，整個 tool loop 續租；網路中斷採保守超時和人工可觀察的 DRAINING 狀態。只看 GPU utilization 或 HTTP 連線數不足以判斷 Agent 已結束。

**控制**：每個部署記錄 idempotency key / instance ID / image digest / SKU / 最大 RUNNING 時間 / 預算上限。先查 `GET /api/instances/active`，再決定是否 create；以 `GET /api/instances/{id}/status` 輪詢啟動；停止後查 `GET /api/instances/{id}/runs` 核對費用。GPUtw 公開文件提供 create、stop、status、runs；停止後原 instance 的再次 start 語意尚未確認，P4 不可臆造呼叫。[建立與停止](https://docs.gputw.ai/docs/rest-api-quickstart)、[狀態與計費](https://docs.gputw.ai/zh-TW/docs/instance-runtime)

P4 驗收至少包含：同時兩個 Agent 只開一台、啟動重試不重複計費、工具等待 30 分鐘內不誤停、stream 斷線後正確排空、endpoint ID 變更能恢復、超時觸發 drain/告警、stop 失敗可恢復。P1/P2/P3 通過之前不啟用自動停機。

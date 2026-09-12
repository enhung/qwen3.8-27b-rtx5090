# Agent 工作成本模型

主要 KPI：每個**成功完成**的 Agent 工作成本，而非單純 tok/s 或 GPU utilization。

`每次啟動成本 = 時費率 × (拉取/啟動/預熱分鐘 + 有效工作分鐘 + 安全閒置分鐘) / 60`。若多個工作共享同一次 RUNNING 區間，將區間實際費用按工作耗時或 token/資源用量分攤；失敗工作也要列入總成本分子。另記錄供應商儲存、流量及最低計費規則（目前未核實）。

Handoff 的較便宜候選是 **約 NT$17.94/hr**，未重新核價，也未通過 53 GB RAM cold-start 資格。只作情境計算：以 handoff 約 14m48s ready 時間計，啟動等待約 NT$4.43；20 / 30 分鐘安全閒置分別約 NT$5.98 / NT$8.97。這些數字不含工作時間、映像拉取差異、失敗重試及其他費用，不是採購報價。

P3 應先用**未改的 Light baseline**量測 53 GB RAM 機型：cold start RAM 峰值、JIT/autotune/graph、131K config、ready 時間、Hermes tool loop、錯誤與實際 runs 費率。若 P2 cache 改善啟動，再用相同 image、相同 host、相同模型分別量 cold/warm；不得把不同 SKU 或不同 cache 狀態混作單一改善幅度。

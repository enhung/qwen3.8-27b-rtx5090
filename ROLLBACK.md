# GPUtw P1 回退

基準：repo commit `207222ca131da2b488bcc1b9490edd1fb5e43777`；原 image `ghcr.io/enhung/qwen38-rtx5090:v2@sha256:6f2f5c227aea70f48cd53c650626640723d6a93cca4b2bdf6865058c71cb0298`；模型 revision `0cc27958cefbbe231782ec8511de8c4eb5233348` 與 `/vault/qwen38/models/qwen3.8-27b-nvfp4` 均不得覆蓋或刪除。

1. P1 新 image 只用獨立 tag 建立**新的** GPUtw instance，先保持 v2 instance / 設定可回退；先記錄兩個 image digest、instance ID、原本 port access 與 Hermes endpoint（不要記錄 secret）。
2. 若新 image 起不來、401 異常、工具呼叫退化或發現 auth bypass：停止把流量導向 P1，將 Hermes / Gateway endpoint 指回 v2，並依原有網路限制處理 v2 的公開 8000。**不可**把沒有完整認證的 v2 直接重新公開到 Internet。
3. 驗證 v2 的已知 Light 啟動、`/v1/models`、Hermes 一輪 tool loop；保留 P1 失敗的已遮罩 logs、HTTP status 與 instance run 記錄。
4. 不執行 `/vault` 清理、不升級 runtime、不改模型 revision。P1 問題單獨修正後再重新測。

目前未有 live instance ID / P1 image digest，因此本文件是可操作的回退程序，不是已演練成功的紀錄。

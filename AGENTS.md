# godot-worldspace-editor — AI agent 專案備忘

godot-worldspace-editor = **用 Godot 4 離線編輯 Skyrim 地形與物件擺放、匯出 heightmap／splatmap PNG 與 `placements.json` 給 ModForge 生成 LAND／REFR 的前端（CK 地形／場景編輯的替代）**。本檔是最頂層路由器，只指向下一層；細節不寫這裡（分層原則見 [STRUCTURE.md](wf/STRUCTURE.md)）。

## 開場與入口

- 每個 session 先跑 `grep -c '^- \[' wf/SESSION-LOG.md`：非 0 才開 [SESSION-LOG.md](wf/SESSION-LOG.md)（進度）；等使用者的事一律記母 repo [WAIT_USER.md](../../WAIT_USER.md)。
- **專案本身**（人類向入口）→ [README.md](README.md)；設計文檔 → [design/](design/README.md)。
- **碰原始碼前**：慣例與 code map → [workflows/common/conventions.md](wf/workflows/common/conventions.md)、[workflows/common/code-map.md](wf/workflows/common/code-map.md)；環境與指令 → [workflows/dev-env.md](wf/workflows/dev-env.md)。
<!-- wf-insert:AGENTS -->
- **要你動手做事** → [WORKFLOWS.md](wf/WORKFLOWS.md) 依意圖派發，再讀該工作流入口檔。
- **想看專案結構** → [INDEX.md](wf/INDEX.md)。
- 使用者偏好與邊界 → [workflows/common/user.md](wf/workflows/common/user.md)。

## 鐵律（always-on，隨時適用）

1. 重構 / 整理**不改原意**：開發＝行為不變且驗證綠燈（headless Godot 契約測試，指令見 [testing](wf/workflows/testing.md)）；非開發＝原意不變，照 `Done when:` 驗收。
2. **不可逆或對外的動作**（push、刪除、對外送出、動 DB）要有**授權來源**：使用者當場確認，或他親自登記在清單裡（routines / schedule）。都沒有就先問。
3. **條列走資料檔、導航留 md**：給 AI 消化的表／清單 >1 KB 存 `.json`／`.csv`（契約 `wf-table/1`，見 [data-files](wf/workflows/common/data-files.md)），用 `tools/tabledb.py` 讀寫、不整份讀進 context；給人點的導航連結留 md。
4. **具體流程**在各工作流入口檔，不在頂層。

<!-- wf-kernel v0.6+368468a (2026-10-26 導入) -->

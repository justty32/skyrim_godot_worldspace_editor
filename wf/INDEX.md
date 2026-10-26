# INDEX — godot-worldspace-editor 專案地圖

godot-worldspace-editor = **用 Godot 4 離線編輯 Skyrim 地形與物件擺放、匯出 heightmap／splatmap PNG 與 `placements.json` 給 ModForge 生成 LAND／REFR 的前端（CK 地形／場景編輯的替代）**。本檔只描述**頂層**：每列一句話＋連結；目錄內部複雜就放它自己的 README / INDEX。

## Repo 佈局

| 路徑 | 內容 |
|------|------|
| `godot/` | Godot 4 專案（`main.tscn`），前端 `.gd`；逐檔職責見 [design/frontend-structure.md](../design/frontend-structure.md) |
| `design/` | 設計／決策／座標系／placements 格式（[index](../design/README.md)）；已鎖定決策在 [decisions.md](../design/decisions.md) |
| `docs/` | 單題說明（如 [object-texture-preview](../docs/object-texture-preview.md)）；調查筆記也放這 |
| `tests/` | Python 驅動的 headless Godot 契約測試（`tests/test_*.py`＋`godot/tests/*.gd`）；`tools/` ＝ `nif_textures.py` |
| `workflows/` | 工作流（派發見 [WORKFLOWS.md](WORKFLOWS.md)；共享區 [workflows/common/](workflows/common/README.md)）|
| `.claude/commands/` | slash 指令適配層（可選）。Claude Code 為例：只讀專案根的這層，非侵入式佈局也留在根；沒有 slash 機制的工具忽略本目錄，直接跑 `tools/wf-lint.sh` |
| `tools/` | kernel 工具：`wf-lint.sh`（檢查）、`tabledb.py`（資料檔 CRUD／連結）、`find_big_lists.py`、`fix_moved_links.py`；非侵入式佈局在 `wf/tools/`；資料檔契約見 [workflows/common/data-files.md](workflows/common/data-files.md) |
<!-- wf-insert:INDEX -->

## 頂層文件

| 檔案 | 角色 |
|------|------|
| [WORKFLOWS.md](WORKFLOWS.md) | 派發器：意圖 → 工作流入口 |
| [STRUCTURE.md](STRUCTURE.md) | 結構整理參考（被動）：分層、膨脹即拆、四級成長、archive、工作流形式 |
| [SESSION-LOG.md](SESSION-LOG.md) | 我的 open 進度 |
| [WAIT_USER.md](../../../WAIT_USER.md) | 等使用者親自做 / 驗證的事（記在母 repo） |

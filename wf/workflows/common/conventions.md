# conventions — 程式碼慣例（碰原始碼的工作流共用）

[common/README](README.md)｜[INDEX](../../INDEX.md)

碰原始碼的工作流（feature-dev / refactor / investigation）共用這套規矩：**寫碼時要遵守什麼**。哪個檔負責什麼領域、測試在哪 → [code-map](code-map.md)；真相層優先序也在 [code-map](code-map.md)。結構整理原則 → [STRUCTURE](../../STRUCTURE.md)。

## 慣例

| 項目 | 規矩 |
|------|------|
| 檔案拆分 | 一支 `.gd` 一個職責、多數約 100 行；>300 行照 [STRUCTURE](../../STRUCTURE.md) 檢視；增刪 `.gd` 要同步 [frontend-structure.json](../../../design/frontend-structure.json) |
| 地形實作 | 自製 terrain，不引入 HTerrain（[decisions](../../../design/decisions.md)）；`godot/texconfig.json`、`modelcache/`、`texcache/` 是本機檔，不進版控 |
| 與 ModForge 的邊界 | 只靠協議對接：輸出 heightmap／splatmap PNG 與 `placements.json`，生成端全在 ModForge，不把生成邏輯搬進本 repo |
| breaking change | 改 `placements.json` 欄位、座標換算或 PNG 格式前，先看 [placements-format](../../../design/placements-format.md)／[coord-system](../../../design/coord-system.md)，與 ModForge `GodotPlacements.cs` 同步並跑 `tests/test_placements_contract.py` |
| 測試 | 契約斷言跑在真正的 Godot runtime 上（`godot/tests/*_contract.gd`），不用 Python 重寫規則；缺 Godot 就明示 skip |
| 版本註記 | `godot/project.godot` 的 `config/features` 不手改，用 editor 開過才由它改寫 |

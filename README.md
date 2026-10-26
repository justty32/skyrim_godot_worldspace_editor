# Godot Worldspace Editor

← [idea #19](../ModForge/workflows/idea/ideas.md)｜設計文檔：[design/](design/README.md)（座標系／placements 格式／分塊拼大圖／決策與查證／前端結構）｜前端程式碼：[godot/](godot/)

> **架構轉向尚未實作、亦無遷移 plan**：轉用 **Godot 原生編輯器**（.tscn 模板 + `@tool` 匯出腳本）的方向見 [native-editor-pivot.md](design/native-editor-pivot.md)。現況仍是以 `main.tscn` 執行的「自製 app 殼」、全庫 0 支 `@tool` 腳本。**下文描述現行 app**；要不要真的轉、何時轉，待重新裁示。轉向只涉及 UI／相機／輸入層，地形格式／座標／匯出／對接 ModForge 不變。

用 **Godot 4**（**自製 terrain**，不靠 HTerrain plugin）離線做地形編輯 → 匯出 → ModForge 生 LAND/REFR → 進遊戲微調。定位是 **Creation Kit 地形/場景編輯的替代前端**（CK 在 Wine/Proton 不穩、難腳本化）。

**獨立 repo**，與 ModForge **靠協議對接、不整合**——本 repo 只負責輸出 heightmap PNG／splatmap PNG／`placements.json`，生成端全在 ModForge。

> **佈局前提**：本文中 `../ModForge/…`、`../model-converter/…` 這類連結，前提是三個 repo **同層 clone 在同一個父目錄下**（本機為 `~/repo/moddings/skyrim/projects/`）。執行期的 CLI／venv 路徑也照這個假設自動推導，可用 `godot/texconfig.json` 覆寫（見 [design/frontend-structure.md](design/frontend-structure.md)）。

---

## 三階段 pipeline

1. **Godot 粗畫**（本 repo）：刷高度 + 刷紋理 + 散佈物件 → 匯出 PNG heightmap + splatmap PNG + `placements.json`
2. **ModForge 生成**：讀 heightmap → 切 cell → LAND（VHGT/VNML）；讀 splatmap → BTXT/VTXT 紋理層；讀 placements → REFR → ESP + BSA
3. **遊戲內微調**：[scene-capture-bridge](../scene-capture-bridge/README.md)（同層獨立 repo，SKSE C++ DLL）在遊戲內細調並匯出 `scene.json` 回餵 ModForge

---

## MVP scope（已達成並超出）

支援 **多格 heightmap**（VHGT/VNML/seam）、**物件擺放 → REFR**、**地形紋理**（單層 baseTexture + 多層 splatmap → BTXT/VTXT）整鏈離線完成，2026-06-18 已 Godot GUI 實跑＋in-game 確認；剩 VTXT position row/col 序與物件 rotation 的實機目視（見 [WAIT_USER](../ModForge/wait_todo/worldspace-editor.md)）。

---

## 資料流

```
Godot（自製 terrain）               ModForge
  HeightMap  → terrain.png ─────┐
  SplatMap   → splatmap.png ────┼──→ 按 cell grid 切割（每 cell 4096 units）
  物件 Node3D → placements.json ┘     → 每 cell 採樣 33×33 → VHGT + 重算 VNML → LAND
  （editorID + transform）            → splatmap → BTXT/VTXT 紋理層
                                      → placements → REFR → ESP + BSA
```

**已知難點**：
- **Cell seam**：高度已靠單張 PNG 共用邊緣欄自動對齊；殘留風險是 **VNML 法線**——邊緣頂點重算法線需參考鄰格高度，切割後要保留 1px overlap
- **NIF 預覽**：Godot 不讀 NIF，靠 glTF proxy（fo76utils / NifSkope 批量轉換前置，Linux+Windows 雙平台可用）
- **Navmesh**：複雜地形 flat-quad 會卡 NPC，精確 navmesh 後排

**大世界＝分塊編輯 → 拼大圖**：一次編十幾格 cell 的 chunk，最後把各 chunk 的 PNG **合成成一張大 PNG**（先合成再讓 ModForge 切，VNML 邊界縫自動消失）+ 合併 placements。邊界**手動對齊**（開新塊先 import 鄰邊起步），stitch 工具純貼上不混合。完整工作流與鎖定決策見 [stitching.md](design/stitching.md)。

**物件擺放可程序化（GDScript）**：除手動 Place Mode，可寫 GDScript 用 `terrain.get_height()`+`PlacementTool` 迴圈/noise 程序生成、貼地、按現成匯出鈕出 `placements.json`（ModForge 零改動）。scatter/grid/聚落量產的最佳前端——詳見 [stitching.md § GDScript](design/stitching.md#相關gdscript-程序化擺放)。

---

## 決策（已鎖定）

地形系統 / heightmap 格式與切割 / 物件 metadata / 座標轉換 / 紋理 / placements.json 約定等已鎖定決策 → 全表見 [decisions.md](design/decisions.md)。

---

## ModForge 後端對接（全部已實作）

對接細節真相在 [SPEC-worldspaces](../ModForge/docs/spec/SPEC-worldspaces.md) + [CODE_MAP.world](../ModForge/workflows/common/code-map/CODE_MAP.world.md)；下表只留「哪個前端輸出 → 哪個後端入口」的對照。

| 前端輸出 | 後端入口 | 狀態 |
|---|---|---|
| heightmap PNG | spec `heightmap` → `Heightmap.cs` → `Vhgt.Encode`（33×33 row-wise signed-int8 delta）+ seam stitching | ✅ |
| — | `Vnml.Compute`（35×35 中心差分重算法線，1px overlap） | ✅ |
| splatmap PNG | spec `baseTexture`（BTXT）/ `textureLayers[].splatmap`（`Splatmap.cs`→`Vtxt.cs` ATXT/VTXT） | ✅ in-game 確認；position 序待目視 |
| `placements.json` | spec `godotPlacements` → `GodotPlacements.cs`（`godot4_y_up`→Skyrim 換算）→ 合流 `placements[]` | ✅ |

BTXT base 層與稀疏 ATXT/VTXT alpha 層都按每格四象限輸出；後端契約由 `WorldspaceBaseTextureTests`／`WorldspaceSplatmapTests` 覆蓋。

平坦地形（`WorldspaceCellSpec.Height` → VHGT 全格同高）、SubCells block tree、flat-quad navmesh、水位預設皆已有；**不需動**：水位 / REGN / navmesh（暫夠）。

---

## 已查證

VHGT 編碼（signed int8 delta、每 delta=8 units）、NIF→glTF 工具選型等查證結論 → 見 [decisions.md](design/decisions.md)。

---

## 前端結構（`godot/`）

現行 app 支援 display scale、Walk Mode 與高度著色。`godot/` 各 `.gd`（~100 行/檔）的逐檔職責、顯示縮放與高度著色規則 → 見 [frontend-structure.md](design/frontend-structure.md)。

## 離線 placement 契約測試

執行環境、各契約的覆蓋範圍與 consumer E2E 建置副作用 → [tests/README.md](tests/README.md)。

## 物件與紋理預覽

Place Mode 支援 base ref／instanceId／rotationY／scale、吸地表的 hash 配色 box proxy、place／undo／clear 與 `placements.json` 匯出／匯入。匯出時還原 display scale，與後端 `GodotPlacements.cs` 欄位及座標換算一致；Place Mode 與 Splat Mode 互斥。

按「Load real models」→ CLI `nifexport` 抽 NIF → `nif2gltf --flat` 轉 glTF → `model_fetch.gd` 以 `GLTFDocument` 載入、替換 box。diffuse 由 [sidecar 管線](docs/object-texture-preview.md) 補上；normal／spec 不在 flat 契約內。

地形 WYSIWYG 走獨立的 `texexport`（LTEX → BSA diffuse DDS → PNG）、`tex_fetch.gd`（快取 `res://texcache/`）及 `terrain_material.gd`（ShaderMaterial，無貼圖 fallback 頂點色）。base + 至多 4 層 per-vertex alpha 混合；預覽 alpha 與匯出 splatmap 共用資料，PNG Y-flip／網格約定與後端一致。Splat Mode 提供多層 alpha 筆、active 層即時上色、8-bit 灰階 PNG 及可貼入 spec 的片段。

## Open

LE-format 真檔 NIF 未驗（vanilla 多 SSE）；VTXT position row/col 序與物件 rotation 待實機目視，見 [worldspace 待驗項](../ModForge/wait_todo/worldspace-editor.md)。Godot GUI／xEdit byte-verify 驗收入口見 [WAIT_USER](../ModForge/WAIT_USER.md)，不擋離線開發。

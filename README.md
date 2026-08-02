# Godot Worldspace Editor

← [idea #19](../../workflows/idea/ideas.md)｜設計文檔：[design/](design/README.md)（座標系／placements 格式／分塊拼大圖／決策與查證／前端結構）｜前端程式碼：[godot/](godot/)

> **⚠️ 架構轉向（2026-06-24,未實作）**:擬棄「自製 app 殼」改吃 **Godot 原生編輯器**（.tscn 模板 + `@tool` 匯出腳本）。下述 app 形式的 UI/相機/輸入描述屆時會大改;地形格式/座標/匯出/對接 ModForge 不變。詳 [native-editor-pivot.md](design/native-editor-pivot.md)。

用 **Godot 4**（**自製 terrain**，不靠 HTerrain plugin）離線做地形編輯 → 匯出 → ModForge 生 LAND/REFR → 進遊戲微調。定位是 **Creation Kit 地形/場景編輯的替代前端**（CK 在 Wine/Proton 不穩、難腳本化）。

前期作為 sub_proj（輸出 JSON spec 對接 ModForge）→ 體量大了再移成獨立 repo，對接方式不變。

---

## 三階段 pipeline

1. **Godot 粗畫**（本 sub_proj）：刷高度 + 刷紋理 + 散佈物件 → 匯出 PNG heightmap + splatmap PNG + `placements.json`
2. **ModForge 生成**：讀 heightmap → 切 cell → LAND（VHGT/VNML）；讀 splatmap → BTXT/VTXT 紋理層；讀 placements → REFR → ESP + BSA
3. **遊戲內微調**（獨立 C++/SKSE repo）：SkyrimIngameEditor 細調，不在 ModForge 範圍

---

## MVP scope（已達成並超出）

原始 MVP＝**單格 PNG → LAND → COW 進入、地形有起伏**。現況已遠超：**多格 heightmap**（VHGT/VNML/seam）、**物件擺放 → REFR**、**地形紋理**（單層 baseTexture + 多層 splatmap → BTXT/VTXT）整鏈離線完成；剩主力機驗收（Godot GUI 實跑、xEdit byte-verify）與 box proxy 換真實 glTF。

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

對接細節真相在 [SPEC-worldspaces](../../docs/spec/SPEC-worldspaces.md) + [CODE_MAP.world](../../workflows/common/code-map/CODE_MAP.world.md)；下表只留「哪個前端輸出 → 哪個後端入口」的對照。

| 前端輸出 | 後端入口 | 狀態 |
|---|---|---|
| heightmap PNG | spec `heightmap` → `Heightmap.cs` → `Vhgt.Encode`（33×33 row-wise signed-int8 delta）+ seam stitching | ✅ |
| — | `Vnml.Compute`（35×35 中心差分重算法線，1px overlap） | ✅ |
| splatmap PNG | spec `baseTexture`（BTXT）/ `textureLayers[].splatmap`（`Splatmap.cs`→`Vtxt.cs` ATXT/VTXT） | ✅ 待 xEdit byte-verify |
| `placements.json` | spec `godotPlacements` → `GodotPlacements.cs`（`godot4_y_up`→Skyrim 換算）→ 合流 `placements[]` | ✅ |

平坦地形（`WorldspaceCellSpec.Height` → VHGT 全格同高）、SubCells block tree、flat-quad navmesh、水位預設皆已有；**不需動**：水位 / REGN / navmesh（暫夠）。

---

## 已查證

VHGT 編碼（signed int8 delta、每 delta=8 units）、NIF→glTF 工具選型等查證結論 → 見 [decisions.md](design/decisions.md)。

---

## 前端結構（`godot/`）

`godot/` 各 `.gd`（~100 行/檔）的逐檔職責、顯示縮放與高度著色規則 → 見 [frontend-structure.md](design/frontend-structure.md)。

## Open

- **小尾巴（不擋使用）**：物件 glTF 只取 diffuse 貼圖（無 normal/spec）；LE-format 真檔 nif 未驗（vanilla 多 SSE）；VTXT position row/col 序待最終目視（見 [WAIT_USER](../../wait_todo/worldspace-editor.md)）。

~~box proxy → 真實 glTF + 貼圖~~ ✅ **GUI 確認 2026-06-18**：placement 顯示真實 vanilla 模型 + 真實貼圖（非方塊/灰模）。按 placement UI「Load real models」→ CLI `nifexport` 抽 model NIF → `nif2gltf`（解 shape→shader→textureset diffuse，[model-converter](../model-converter/README.md) 已對真實 SSE nif 修復）→ CLI `texpath` 抽貼圖 → `model_fetch.gd` GLTFDocument 載入 + `placement.set_model` 換 box。同款 BSA-抽取 pipeline as `texexport`。

~~地形紋理 WYSIWYG（Godot 直接顯示真實草/泥土貼圖）~~ ✅ **in-game 確認 2026-06-18**：splat 筆刷下顯示真實 vanilla ground 貼圖（非平色 tint），base + 至多 4 層 per-vertex alpha 混合。CLI `texexport`（LTEX→diffuse .dds 從遊戲 BSA→PNG）+ `tex_fetch.gd`（OS.execute 呼叫、快取 res://texcache/）+ `terrain_material.gd`（ShaderMaterial，無貼圖 fallback 頂點色）。預覽 alpha 格＝匯出 splatmap 同份資料，所見＝VTXT 烘出。

> 主力機驗收項（Godot GUI 實跑、xEdit byte-verify）列在 [WAIT_USER](../../WAIT_USER.md)，不擋離線開發。

~~紋理 B 路線（單層 BTXT + 多層 VTXT splatmap + 前端 splat 筆刷）~~ ✅ 2026-06-17（離線實作，**待主力機 Godot GUI + xEdit byte-verify**）：① spec `worldspace.baseTexture` → 每格四象限 BTXT base 層（測 `WorldspaceBaseTextureTests`）；② spec `worldspace.textureLayers`（LTEX + 灰階 splatmap PNG）→ 每格四象限稀疏 ATXT+VTXT alpha 層（`Splatmap.cs`/`Vtxt.cs`，測 `WorldspaceSplatmapTests`）；③ Godot 前端 Splat Mode 多層 alpha 筆 + active 層即時上色 + 8-bit 灰階 splatmap PNG 匯出（含可貼 spec 片段）：`splat_tool.gd`/`splat_ui.gd`/`splatmap_io.gd` + `terrain`/`terrain_mesh` overlay + `main.gd` 路由（與 Place Mode 互斥）。PNG Y-flip/網格約定前後端一致。

~~物件擺放（Godot 前端）~~ ✅ 2026-06-17（離線實作，**待主力機 Godot GUI 跑一次**）：Place Mode 切換 + placement 筆（base ref / instanceId / rotationY / scale）+ box proxy（hash 配色，Y 吸地表）+ `placements.json` 匯出/匯入。檔：`placement.gd`（PlacedObject 薄節點）/ `placement_tool.gd`（list + place/undo/clear）/ `placements_io.gd`（JSON I/O，顯示 scale 除掉還原 canonical 公尺）/ `placement_ui.gd`（側欄 PLACEMENT 段）；`terrain.gd` 加 `world_to_canonical_meters`/`canonical_meters_to_world`/`surface_display_y`；`main.gd` 接 Place Mode 輸入路由。**離線已核對**前端輸出欄位 + 座標換算與後端 `GodotPlacements.cs` 逐欄一致（round-trip 自洽）。

~~godotPlacements 讀取（後端）~~ ✅ 2026-06-16（`GodotPlacements.cs` + test：解 JSON、godot4_y_up→Skyrim 座標換算、rad→deg、合流 `placements[]`，已接進 `Generator.Build.Worldspace.cs:198`）
~~Godot 前端骨架~~ ✅ 2026-06-16（自製 terrain，不靠 HTerrain）
~~前端拆檔 + display scale + Walk Mode + 高度著色~~ ✅ 2026-06-16
~~Godot 專案開啟測試~~ ✅ 2026-06-16（使用者主力機驗證：terrain/筆刷/PNG 匯出可用）
~~VNML 重算（後端）~~ ✅ 2026-06-16（`Vnml.cs` + `SampleCellExtended`，35×35 中心差分）
~~待主力機收尾：Tamriel VHGT 反解比對~~ ✅ 2026-06-16（20 格 delta 完全一致）
~~VNML axis/編碼驗證~~ ✅ 2026-06-16（對 vanilla Tamriel VNML 逐 byte 比對，修了 3 bug：轉置 / StepUnits 8→128 / signed-byte up=(0,0,127)；見 [landed/world.md](../../workflows/feature-dev/landed/world.md)）

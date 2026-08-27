# Godot Worldspace Editor

← [idea #19](../ModForge/workflows/idea/ideas.md)｜設計文檔：[design/](design/README.md)（座標系／placements 格式／分塊拼大圖／決策與查證／前端結構）｜前端程式碼：[godot/](godot/)

> **⚠️ 架構轉向（2026-06-24,未實作）**:擬棄「自製 app 殼」改吃 **Godot 原生編輯器**（.tscn 模板 + `@tool` 匯出腳本）。下述 app 形式的 UI/相機/輸入描述屆時會大改;地形格式/座標/匯出/對接 ModForge 不變。詳 [native-editor-pivot.md](design/native-editor-pivot.md)。

用 **Godot 4**（**自製 terrain**，不靠 HTerrain plugin）離線做地形編輯 → 匯出 → ModForge 生 LAND/REFR → 進遊戲微調。定位是 **Creation Kit 地形/場景編輯的替代前端**（CK 在 Wine/Proton 不穩、難腳本化）。

**獨立 repo**（2026-08-02 自 ModForge `sub_projs/godot-worldspace-editor` 抽出，未帶舊 commit 歷史）。與 ModForge 的關係不變：**靠協議對接、不整合**——本 repo 只負責輸出 heightmap PNG／splatmap PNG／`placements.json`，生成端全在 ModForge。

> **佈局前提**：本文中 `../ModForge/…`、`../model-converter/…` 這類連結，前提是三個 repo **同層 clone 在同一個父目錄下**（本機為 `~/repo/moddings/skyrim/projects/`）。執行期的 CLI／venv 路徑也照這個假設自動推導，可用 `godot/texconfig.json` 覆寫（見 [design/frontend-structure.md](design/frontend-structure.md)）。

---

## 三階段 pipeline

1. **Godot 粗畫**（本 repo）：刷高度 + 刷紋理 + 散佈物件 → 匯出 PNG heightmap + splatmap PNG + `placements.json`
2. **ModForge 生成**：讀 heightmap → 切 cell → LAND（VHGT/VNML）；讀 splatmap → BTXT/VTXT 紋理層；讀 placements → REFR → ESP + BSA
3. **遊戲內微調**：[scene-capture-bridge](../scene-capture-bridge/README.md)（同層獨立 repo，SKSE C++ DLL）在遊戲內細調並匯出 `scene.json` 回餵 ModForge

---

## MVP scope（已達成並超出）

原始 MVP＝**單格 PNG → LAND → COW 進入、地形有起伏**。現況已遠超：**多格 heightmap**（VHGT/VNML/seam）、**物件擺放 → REFR**、**地形紋理**（單層 baseTexture + 多層 splatmap → BTXT/VTXT）整鏈離線完成；剩主力機驗收（Godot GUI 實跑、xEdit byte-verify）。

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
| splatmap PNG | spec `baseTexture`（BTXT）/ `textureLayers[].splatmap`（`Splatmap.cs`→`Vtxt.cs` ATXT/VTXT） | ✅ 待 xEdit byte-verify |
| `placements.json` | spec `godotPlacements` → `GodotPlacements.cs`（`godot4_y_up`→Skyrim 換算）→ 合流 `placements[]` | ✅ |

平坦地形（`WorldspaceCellSpec.Height` → VHGT 全格同高）、SubCells block tree、flat-quad navmesh、水位預設皆已有；**不需動**：水位 / REGN / navmesh（暫夠）。

---

## 已查證

VHGT 編碼（signed int8 delta、每 delta=8 units）、NIF→glTF 工具選型等查證結論 → 見 [decisions.md](design/decisions.md)。

---

## 前端結構（`godot/`）

`godot/` 各 `.gd`（~100 行/檔）的逐檔職責、顯示縮放與高度著色規則 → 見 [frontend-structure.md](design/frontend-structure.md)。

## 離線 placement 契約測試

`tests/test_placements_contract.py` 把真正的 Godot exporter 輸出一路驗到 ModForge
寫出的 REFR；會鎖定 format version、座標系、display scale 還原、origin offset、
instanceId、base、rotation 軸轉換與 scale。執行：

```bash
python tests/test_placements_contract.py
```

快速 source gate 永遠執行；runtime 層需要 Godot 4 在 PATH（自動找 `godot4` / `godot` /
`godot-mono`），或設定 `GODOT_BIN`。本機 Manjaro 走 `godot-mono`（`/usr/bin/godot-mono`，
4.7.2.stable.mono），headless 即可，不必開 GUI。
同層 `../ModForge` 存在時會再執行完整 consumer E2E（不同層可設 `MODFORGE_DIR`）；
缺 Godot 時 unittest 會明示 skip，而不是拿手寫 JSON 冒充 exporter 輸出。

`tests/test_skyrim_ref.py` 驗 `SkyrimRef`／`RepoLayout`：ref 的驗證與正規化規則直接決定
快取檔名與 CLI argv，斷言跑在真正的 Godot runtime 上（`godot/tests/skyrim_ref_contract.gd`），
不是拿 Python 重寫一份規則來對。

`tests/test_gdscript_parses.py` 是重構護欄：把 `godot/` 每一支 `.gd` 都用
`godot --headless --check-only --script` 掃一遍，parse 或型別解析失敗就紅。兩支契約測試只會
執行自己用得到的那幾支腳本（PlacementsIo／TerrainCoords／ModelFetch 及其相依），像
`tex_fetch.gd` 這種只有 SplatTool 走得到的檔壞掉時兩支都還是綠的；headless **editor** 掃描
雖然會印 `SCRIPT ERROR: Parse Error`，但 **exit code 仍是 0**，也擋不住。`--check-only`
會回非零，且連帶解析外部 `class_name` 成員，所以引用到壞類別的檔會一起紅。

`tests/test_model_fetch_contract.py` 另驗 model-converter → Godot 的真實 process boundary：
synthetic NIF 經 production `nif2gltf` CLI 產生 `.gltf + .bin`，再由 production
`ModelFetch._load_gltf()` 載入並檢查 mesh、primitive、頂點軸向與尺度；也覆蓋 missing
bin、bad glTF、converter nonzero 與 repo cache 不污染。執行方式相同，runtime 層可用
`GODOT_BIN`、`MODEL_CONVERTER_DIR` 覆寫工具位置。

## Open

- **小尾巴（不擋使用）**：物件 glTF 目前是無貼圖的 flat proxy；LE-format 真檔 nif 未驗（vanilla 多 SSE）；VTXT position row/col 序待最終目視（見 [WAIT_USER](../ModForge/wait_todo/worldspace-editor.md)）。

~~box proxy → 真實 glTF 幾何~~ ✅ **GUI 確認 2026-06-18**：placement 顯示真實 vanilla 模型幾何（非方塊）。按 placement UI「Load real models」→ CLI `nifexport` 抽 model NIF → `nif2gltf --flat` 轉為平色 glTF proxy → `model_fetch.gd` 以 `GLTFDocument` 載入 + `placement.set_model` 換 box。物件 diffuse/normal/spec 貼圖不在現行 converter 的 flat 契約內；地形 LTEX 貼圖仍由獨立 `texexport` pipeline 提供。

~~地形紋理 WYSIWYG（Godot 直接顯示真實草/泥土貼圖）~~ ✅ **in-game 確認 2026-06-18**：splat 筆刷下顯示真實 vanilla ground 貼圖（非平色 tint），base + 至多 4 層 per-vertex alpha 混合。CLI `texexport`（LTEX→diffuse .dds 從遊戲 BSA→PNG）+ `tex_fetch.gd`（OS.execute 呼叫、快取 res://texcache/）+ `terrain_material.gd`（ShaderMaterial，無貼圖 fallback 頂點色）。預覽 alpha 格＝匯出 splatmap 同份資料，所見＝VTXT 烘出。

> 主力機驗收項（Godot GUI 實跑、xEdit byte-verify）列在 [WAIT_USER](../ModForge/WAIT_USER.md)，不擋離線開發。

~~紋理 B 路線（單層 BTXT + 多層 VTXT splatmap + 前端 splat 筆刷）~~ ✅ 2026-06-17（離線實作，**待主力機 Godot GUI + xEdit byte-verify**）：① spec `worldspace.baseTexture` → 每格四象限 BTXT base 層（測 `WorldspaceBaseTextureTests`）；② spec `worldspace.textureLayers`（LTEX + 灰階 splatmap PNG）→ 每格四象限稀疏 ATXT+VTXT alpha 層（`Splatmap.cs`/`Vtxt.cs`，測 `WorldspaceSplatmapTests`）；③ Godot 前端 Splat Mode 多層 alpha 筆 + active 層即時上色 + 8-bit 灰階 splatmap PNG 匯出（含可貼 spec 片段）：`splat_tool.gd`/`splat_ui.gd`/`splatmap_io.gd` + `terrain`/`terrain_mesh` overlay + `main.gd` 路由（與 Place Mode 互斥）。PNG Y-flip/網格約定前後端一致。

~~物件擺放（Godot 前端）~~ ✅ 2026-06-17（離線實作，**待主力機 Godot GUI 跑一次**）：Place Mode 切換 + placement 筆（base ref / instanceId / rotationY / scale）+ box proxy（hash 配色，Y 吸地表）+ `placements.json` 匯出/匯入。檔：`placement.gd`（PlacedObject 薄節點）/ `placement_tool.gd`（list + place/undo/clear）/ `placements_io.gd`（JSON I/O，顯示 scale 除掉還原 canonical 公尺）/ `placement_ui.gd`（側欄 PLACEMENT 段）；`terrain.gd` 加 `world_to_canonical_meters`/`canonical_meters_to_world`/`surface_display_y`；`main.gd` 接 Place Mode 輸入路由。**離線已核對**前端輸出欄位 + 座標換算與後端 `GodotPlacements.cs` 逐欄一致（round-trip 自洽）。

~~godotPlacements 讀取（後端）~~ ✅ 2026-06-16（`GodotPlacements.cs` + test：解 JSON、godot4_y_up→Skyrim 座標換算、rad→deg、合流 `placements[]`，已接進 `Generator.Build.Worldspace.cs:198`）
~~Godot 前端骨架~~ ✅ 2026-06-16（自製 terrain，不靠 HTerrain）
~~前端拆檔 + display scale + Walk Mode + 高度著色~~ ✅ 2026-06-16
~~Godot 專案開啟測試~~ ✅ 2026-06-16（使用者主力機驗證：terrain/筆刷/PNG 匯出可用）
~~VNML 重算（後端）~~ ✅ 2026-06-16（`Vnml.cs` + `SampleCellExtended`，35×35 中心差分）
~~待主力機收尾：Tamriel VHGT 反解比對~~ ✅ 2026-06-16（20 格 delta 完全一致）
~~VNML axis/編碼驗證~~ ✅ 2026-06-16（對 vanilla Tamriel VNML 逐 byte 比對，修了 3 bug：轉置 / StepUnits 8→128 / signed-byte up=(0,0,127)；見 [landed/world.md](../ModForge/workflows/feature-dev/landed/world.md)）

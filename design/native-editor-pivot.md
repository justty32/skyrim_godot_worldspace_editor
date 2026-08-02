# 決策：轉向 Godot 原生編輯器（棄自製 app 殼）

← [design index](README.md)｜sub_proj：[README](../README.md)｜[decisions](decisions.md)｜[frontend-structure](frontend-structure.md)

> 狀態：**方向已拍板（2026-06-24）、未實作**。本文記錄「為什麼轉」與「轉成什麼」,實際遷移待出 plan。

## 一句話

現在的 `godot/` 是一個 **獨立執行的 app**（`run/main_scene="res://main.tscn"`）,自幹了相機、輸入、選取、UI 一整套——而這些 **Godot 原生編輯器本來就免費送**。轉成「**.tscn 場景模板 + `@tool` 匯出腳本,其餘吃 Godot 原生編輯器**」,維護面積砍半、能力反而更強。

## 動機:我們在重造編輯器

2412 行 GDScript 裡,**一大半在重造輪子**,原生編輯器全都有且更強:

| 我們自製的 | Godot 原生對應 |
|---|---|
| `camera_rig` / `walk_mode` / `player_controller` / `editor_input` / `shift_scroll` | 編輯器視窗相機導覽 |
| `placement_ui` / `grid_ui` / `world_ui` / `splat_ui` / `ui_section` / `io_dialog` | Inspector + 場景樹 + FileSystem dock |
| `placement_tool`（選取/擺放/undo） | gizmo 拖移、多選、複製陣列、undo/redo |
| `scene_builder`（組相機/環境/格線） | 編輯器內建 |

## 關鍵:資料模型早就對了

`placement.gd` 的 `PlacedObject` **已經是**「原生編輯想要的那種帶 metadata 的節點」:

```gdscript
class_name PlacedObject
extends Node3D                  # 真 Node3D,掛真 mesh,只有 transform 進 export
var skyrim_base: String        # base form ref
var instance_id: String        # 選填,REFR editorId
var uniform_scale: float       # REFR scale
```

只差把它從「app 跑起來給你點」翻成「editor 場景讓你拖」。**資料層零改**。

## 轉成什麼

1. `PlacedObject` 加 `@tool` + `@export`,`skyrim_base`/`uniform_scale`/`instance_id` 直接在原生 **Inspector** 編輯;`@tool` `_ready` 自己 fetch 真 mesh（`model_fetch` 既有邏輯,只是改在編輯器執行緒跑）。
2. 場景存成真 `.tscn`,在 Godot **編輯器裡開**（不是 run）,用原生 gizmo 擺/移/複製。
3. 一支 `@tool` **EditorScript**（選單按鈕）走訪場景樹 → 套用既有座標轉換 → 吐 `placements.json`（格式不變,見 [placements-format](placements-format.md)）。
4. **擺新物件 = 從 FileSystem dock 拖**:每個 vanilla base 預生一個薄 `.tscn`（內含一個 `skyrim_base` 設好的 `PlacedObject`）;或單一 `PlacedObject` 場景,拖進去後在 Inspector 改 `skyrim_base` 即自抓 mesh。

## 保留 vs 砍掉

| | 檔 |
|---|---|
| **保留（核心價值）** | `terrain_mesh`（ArrayMesh 建模）、`terrain_material` / `splat_render`（WYSIWYG 貼圖）、`model_fetch` / `tex_fetch`（nif→glTF / LTEX→PNG）、`terrain_coords`（座標換算）、`png16*` / `splatmap_io` / `placements_io`（編解碼,export 改由 EditorScript 呼叫）、`placement.gd`（升級成 `@tool`）|
| **砍掉（原生取代）** | `main` / `scene_builder` / `camera_rig` / `walk_mode` / `player_controller` / `editor_input` / `shift_scroll` / `ui_section` / `world_ui` / `grid_ui` / `placement_ui` / `splat_ui` / `io_dialog` / `placement_tool` |

→ 約砍掉一半的碼,且砍的全是「維護負擔高、價值低」的殼層。

## 老實講一個代價:地形雕刻/貼圖筆刷

原生編輯器**沒有 terrain sculpt / splat paint**,所以 `terrain_brush` / `splat_tool` 是**唯一不能被原生取代**的能力。兩條出路:

- **(A) 接上 stitching 決策**（推薦）:大世界結構已拍板「外部合成一張 PNG heightmap,ModForge 切片」（見 [stitching](stitching.md)、[decisions](decisions.md) 大世界結構列）——地形本來就走外部影像編輯,**不靠 Godot 筆刷**。在新工作流下這代價幾乎不痛:Godot 場景只**載入** heightmap/splatmap 當地表背景,在其上擺物件。
- **(B) 若仍要 in-editor 雕刻**:`terrain_brush` / `splat_tool` 改寫成一個 `EditorPlugin` dock 保留——但這是可選,非 MVP。

## 加碼:跟既有設計天作之合

- **錨點命名免費**:原生**場景樹**幫節點命名（`BrelinBedRef`、`RiverwatchForgeRef`）——那個節點名**就是** [settlements macro](../../../workflows/specs/archive/2026-06-24-settlement-population-design.md) 錨點要吃的 editorId。場景樹 = 免費的錨點命名 UI。
- **程序化擺放更順**:[decisions「程序化擺放」](decisions.md) 那條(GDScript 生 placement)在原生下變成「`@tool` 腳本往場景樹塞 `PlacedObject` 節點」,跟手動拖的結果同構、同一支 export 吐出。

## 性質轉變（這才是重點）

**從「我們維護一個編輯器 app」→「我們提供一個 .tscn 場景模板 + 一支 export 腳本,剩下吃 Godot 原生」。** 我們不再跟 Godot 的 UI/相機/選取競爭,只專注在它沒有的:Skyrim 資產橋接（mesh/texture fetch）、座標轉換、placements 匯出。

## 未決（出 plan 時定）

- `@tool` 下 `model_fetch`（呼叫 ModForge CLI 的 `OS.execute`）在編輯器執行緒的行為與快取路徑。
- vanilla base 的「調色盤」最終形式:預生 `.tscn` 庫 vs 單一可改 `skyrim_base` 的場景 vs 一個輕量 dock 列表。
- 地形代價走 (A) 純外部 還是 (B) 保留一個雕刻 dock。
- 遷移策略:漸進（先做 export EditorScript、app 與 editor 並存一陣）vs 一次切。

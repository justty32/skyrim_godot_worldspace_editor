# 決策與查證

← [design index](README.md)｜sub_proj：[README](../README.md)

## 決策（已鎖定）

> **⚠️ 架構轉向（2026-06-24,未實作）**:棄「自製 app 殼」改吃 **Godot 原生編輯器**——`.tscn` 場景模板 + `@tool` 匯出腳本,砍掉相機/輸入/UI/選取整層。下表多數 UI/輸入相關決策將被取代;地形/座標/格式/錨點決策仍有效。詳 [native-editor-pivot.md](native-editor-pivot.md)。

| 主題 | 決策 |
|---|---|
| 地形系統 | **Godot 4 自製 terrain**（ArrayMesh + 自寫高度/splat 筆刷 + 自寫 PNG codec）。原評估 HTerrain plugin，實作時棄用改自製 |
| Heightmap 格式 | 16-bit grayscale PNG，spec 寫路徑 |
| Heightmap 切割 | 單張大 PNG，ModForge 切；N 格寬 → PNG 寬 `N×32+1` px，相鄰格共用邊緣欄 → seam 零誤差 |
| 物件 metadata | 薄 script + `@export var skyrim_base`（base form ref）+ `@export var instance_id`（選填） |
| 座標轉換 | Godot 原生座標（公尺 + Y-up），ModForge 轉 game units + Z-up；換算唯一真相在 ModForge |
| 物件 scale | 鎖 uniform；Godot script 限制等比縮放，非等比取主軸並 warn |
| 物件預覽 | fo76utils / NifSkope 批量轉 glTF 作視覺代理 |
| 紋理 | 兩段：單層 `baseTexture`（全格 BTXT）+ 多層 `textureLayers`（每層 LTEX + 灰階 splatmap PNG → VTXT/ATXT alpha 層）。已實作 |
| Navmesh | MVP 跳過，只生 LAND |
| placements.json | header 包一層（`version` + `coordinate_system: "godot4_y_up"`），rotation 單位 radians |
| instanceId | 選填可省略（≠ 空字串）；省略 = 匿名 REFR；有值 = 此 REFR 的 editorId |
| 掛進 spec | `godotPlacements` 巢狀在 worldspace 節點下，ModForge 轉換後合流進 `placements[]` pipeline |
| 大世界結構 | **分塊編輯 → 合成一張大 PNG → ModForge 切**（非 N 個 worldspace 黏接）；先合成再切 → VNML 邊界縫自動消失。詳 [stitching.md](stitching.md) |
| 邊界對齊 | **手動對齊**（不做骨架先行自動化）；前提＝編輯時看得到鄰邊，慣例＝開新塊先 import 鄰塊邊緣起步 |
| stitch 工具 | **純貼上不混合不羽化**（信任手調）；可選「共用邊取平均」清 1–2px 殘差；ModForge 核心零改動 |
| 全局約定 | 紋理 layer→LTEX **調色盤全局共用**；`instanceId` **全局命名空間**合併去重 |
| 程序化擺放 | 物件可走 **GDScript 程序化**（`terrain.get_height()`+`PlacementTool`→ 現成匯出鏈，ModForge 零改動），與手動 Place Mode 並存 |

## 已查證

- ✅ **VHGT 編碼**：signed int8 delta、row-wise 累積、每 delta = 8 game units（Mutagen 0.53.1 + UESP + xEdit，2026-06-16）——詳見 [worldspace-editor-design.md](../../../workflows/specs/worldspace-editor-design.md)
- ✅ **NIF → glTF**：fo76utils / NifSkope（Linux+Windows 雙平台）；`nif2gltf` Rust CLI 不存在（Gemini 捏造）——見 [`gemini-research/worldspace-editor/nif-gltf-conversion.md`](../../gemini-research/worldspace-editor/nif-gltf-conversion.md)

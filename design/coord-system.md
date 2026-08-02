# Skyrim ↔ Godot 座標換算

← [design index](README.md)｜sub_proj：[README](../README.md)

## 從 codebase 確認的數值

**來源：`Generator.Build.Navmesh.cs` 行 24–25、60–61、104**

```csharp
float wx0 = cs.X * 4096f, wy0 = cs.Y * 4096f;
float wx1 = wx0 + 4096f,  wy1 = wy0 + 4096f;
data.MaxDistanceX = 4096f;
data.MaxDistanceY = 4096f;
(short)Math.Round(info.Min.X / 4096f), (short)Math.Round(info.Min.Y / 4096f)
```

→ **1 cell = 4096 × 4096 game units**（confirmed，不是估算）

**來源：`Generator.Build.Worldspace.cs` 行 99、135**

```csharp
// Flat LAND: all 33×33 height-map deltas = 0
HeightMap = new Noggog.Array2d<byte>(33, 33, 0),
```

→ **LAND = 33×33 頂點**，相鄰點間距 = 4096 / 32 = **128 game units**

**來源：`Spec.Worldspace.cs` 行 58–60 + `Generator.Build.Worldspace.cs` 行 134**

```csharp
// Terrain height in game units. Offset stored as Height/8 in VHGT (Skyrim's scale factor).
public float Height { get; set; } = 4000f;
// actual_Z = Offset * 8
land.VertexHeightMap = new LandscapeVertexHeightMap { Offset = cs.Height / 8f, ... }
```

→ **VHGT 編碼**：`Offset = Height_in_game_units / 8`，`actual_Z = Offset * 8`  
→ HeightMap 的 33×33 是每個頂點相對前一頂點的 **signed delta**，**每單位 = 8 game units**（delta=1 → +8 units；與 Offset 同尺度）。  
✅ **已查證（Mutagen 0.53.1 原碼 + UESP + xEdit + 主力機 round-trip，2026-06-16）**：① delta 是 **signed int8**（−128~127）——Mutagen 寫 byte 原值不轉換，ModForge 須自做二補數；② **row-wise 累積**：第 0 欄沿列往北累積成各列基準、第 1–32 欄沿列內往東累積；③ Tamriel 20 格 decode→encode delta bytes 完全一致（596 tests，含 RequiresSkyrim）。詳見 [worldspace-editor-design.md](../../../workflows/specs/worldspace-editor-design.md)。  
⚠️ **舊版這裡曾誤寫「每單位 = 1/8 game unit（+0.125）」——錯**（1/8 單步最大僅 ±16 units，做不出山）。正解 ×8。

**來源：`Spec.Worldspace.cs` 行 59（developer 備註）**

```
// Default 4000 puts terrain ~280m above sea level (Z=0), safely above water.
```

→ 提示換算比例約 4000 units ≈ 280m，但這是開發者備註，**不是精確值**（見「不確定」區）

---

## 換算表

| 單位 | Skyrim game units | Godot（公尺，推估） |
|---|---|---|
| 1 cell 寬/高 | 4096 units | ~58.5m（社群共識）或 ~287m（codebase 備註） |
| LAND 頂點間距（33×33） | 128 units | ~1.83m（社群共識）或 ~9m（codebase 備註） |
| VHGT 1 delta 單位 | **8 units**（同 Offset 尺度） | ~0.11m |
| 1 signed byte delta（max 127） | **1016 units** | ~14.5m（單步坡度上限） |
| player 角色身高（通常引用） | ~128 units | ~1.8m → 1 unit ≈ 1.4cm |

---

## 地形尺度 / heightmap 換算

> 註：實作走**自製 terrain**（ArrayMesh + 自寫 PNG codec），非 HTerrain plugin；下列換算與網格規則不變，只是由自製程式碼實現。

**換算選定：社群共識（1 unit ≈ 1.4286cm = 0.014286m）**——與 player 角色高度對得上（128 units ≈ 1.8m）；codebase 備註的 ~7cm/unit（1 cell ≈ 287m）與角色比例不符，僅作參考。

```
terrain size (per cell) = 4096 × 0.014286 ≈ 58.5m
頂點網格                 = cell_count × 32 + 1     （每 cell 33×33，相鄰格共用邊緣欄）
heightmap export        = 16-bit grayscale PNG（splatmap = 8-bit grayscale）
```

**高度映射**：不需絕對精度。Godot 出 16-bit PNG（0~65535），ModForge 讀檔時自訂 `skyrim_height = png_value / 65535 × max_height_units`，只要在 spec/文件記錄換算係數即可。`max_height_units` 取多少待定（與不確定 #4 PNG 精度連動）。

---

## 不確定 / 需外部驗證的部分

1. **game units → 公尺的精確比例**：codebase 只有 "~280m" 的備註（`Spec.Worldspace.cs:59`），不是精確定義。社群共識（1 unit = 1.4286cm，player 高度 128 units ≈ 1.8m）更可信，但應查 UESP wiki 或 Bethesda 官方資料確認。

2. ~~**VHGT delta 是 signed 還是 unsigned**~~ ✅ **已解（2026-06-16）**：Mutagen 寫 byte 原值不轉換，引擎讀成 **signed int8** → ModForge 自做二補數（存 −10 = byte 246）。

3. ~~**VHGT delta 是 per-row 重置還是全域累積**~~ ✅ **已解（2026-06-16）**：**row-wise 累積**——第 0 欄沿列往北累積成各列基準、第 1–32 欄沿列內往東累積；offset 與每 delta 都 ×8 game units。✅ **主力機 round-trip 已驗（2026-06-16）**：Tamriel 20 格 decode→encode delta bytes 完全一致。

4. **PNG heightmap 精度**：16-bit grayscale PNG 可表示 65536 個高度級別，對應 Skyrim VHGT offset 的 signed float 範圍是否足夠？需查 Skyrim 實際地形高度範圍（Tamriel 最高峰 Throat of the World 約多少 game units）。

# Godot Placements 格式詳述

← [design index](README.md)｜repo：[README](../README.md)

## Godot 出圖檔案（`godot_export/placements.json`）

```json
{
  "version": 1,
  "coordinate_system": "godot4_y_up",
  "placements": [
    {
      "base": "Skyrim.esm:0x000D4B52",
      "position": { "x": 12.5, "y": 3.2, "z": -8.1 },
      "rotation": { "x": 0.0, "y": 0.785, "z": 0.0 },
      "scale": 1.5
    },
    {
      "base": "Skyrim.esm:0x000034",
      "instanceId": "MyPatrolMarker01",
      "position": { "x": 5.0, "y": 0.1, "z": 2.0 },
      "rotation": { "x": 0.0, "y": 1.571, "z": 0.0 },
      "scale": 1.0
    }
  ]
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `version` | int | 格式版本（目前 1） |
| `coordinate_system` | string | `"godot4_y_up"` — Godot 4 標準座標（X=東、Y=上、Z=南） |
| `base` | string | Skyrim base form ref（`<master>:0xFORMID`；1–6 位 hex，也容忍 8 位前導零）或 in-spec editorId |
| `position` | Vec3 | **公尺**，Godot 原生座標 |
| `rotation` | Vec3 | **radians**，Godot 原生 Euler；ModForge 讀時轉 degrees |
| `scale` | float | uniform 縮放；Godot plugin 限制等比，非等比取主軸並 warn |
| `instanceId` | string? | **選填，可省略**（省略 ≠ `""`）；省略 = 匿名 REFR；有值 = 此 REFR 的 editorId |

## 掛進 worldspace spec

```json
{
  "worldspaces": [
    {
      "editorId": "MyWorld",
      "heightmap": { "path": "terrain.png", "originX": 0, "originY": 0, "minHeight": 0, "maxHeight": 8192 },
      "godotPlacements": {
        "path": "godot_export/placements.json",
        "originX": 0,
        "originY": 0
      }
    }
  ]
}
```

`godotPlacements` 巢狀在 worldspace 節點下；`path` 指向 Godot 匯出檔，
`originX` / `originY` 是該檔所屬 chunk 的 worldspace cell 原點（省略時皆為 0）。

## 可執行契約

格式 producer 的真相是 `godot/placements_io.gd:PlacementsIo._serialize`；
`godot/tests/placements_contract.gd` 用實際 `PlacedObject` node 呼叫它，不另造一份
JSON fixture。`tests/test_placements_contract.py` 在 Godot 4 headless 下檢查輸出，並於
同層 ModForge 存在時以公開 CLI build plugin，再透過其公開 `PluginIo.Load` 讀回最終
REFR。這會讓 producer 的 version／欄位／display-scale 還原，或 consumer 的
origin／座標／rotation／instanceId／base／scale 任一協議漂移直接使測試失敗。

```powershell
python tests/test_placements_contract.py
```

Godot 不在 PATH 時可設 `GODOT_BIN`；ModForge 不在同層時可設 `MODFORGE_DIR`。

## ModForge 座標換算（`coordinate_system: "godot4_y_up"`）

```
skyrim_x = OriginX * 4096  +  godot_pos.x / 0.014286
skyrim_y = OriginY * 4096  -  godot_pos.z / 0.014286   ← Godot +Z 朝南，Skyrim +Y 朝北，方向相反
skyrim_z =                     godot_pos.y / 0.014286
```

比例常數 `0.014286 m/unit`（1 unit ≈ 1.4286cm，社群共識；待主力機 UESP 確認，不擋 MVP）。

rotation：各軸 `deg = rad × (180 / π)`，且軸跟著座標系換（與 position 同一個基底變換 M=Rx(90°)）：
```
skyrim_rotX =  godot_rot.x   ← 東軸不變
skyrim_rotY = -godot_rot.z   ← Godot +Z(南) → Skyrim −Y(北)，反號
skyrim_rotZ =  godot_rot.y   ← Godot +Y(上) yaw → Skyrim +Z(上) yaw＝heading
```
單軸旋轉（編輯器主要情境，多為 yaw）完全正確；複合 Euler 因兩邊套用順序不同有殘差，待主力機實機對朝向校準。

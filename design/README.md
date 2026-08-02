# 設計文檔索引

← sub_proj：[README](../README.md)

本夾放 godot-worldspace-editor 的設計/決策 markdown（純文檔，不含程式碼；`godot/` 前端程式碼在[上一層](../godot/)）。

| 檔 | 內容 |
|---|---|
| [decisions.md](decisions.md) | 已鎖定決策總表 + 已查證結論（VHGT 編碼、NIF→glTF 工具選型） |
| [coord-system.md](coord-system.md) | Skyrim ↔ Godot 座標換算（cell/units/公尺換算表、VHGT 編碼細節） |
| [placements-format.md](placements-format.md) | `placements.json` 欄位格式 + ModForge 座標/旋轉換算公式 |
| [stitching.md](stitching.md) | 分塊編輯 → 拼大圖工作流與鎖定決策（含 GDScript 程序化擺放） |
| [frontend-structure.md](frontend-structure.md) | `godot/` 各 `.gd` 逐檔職責、顯示縮放與高度著色規則 |
| [native-editor-pivot.md](native-editor-pivot.md) | 轉向 Godot 原生編輯器的決策紀錄（2026-06-24，方向已定、未實作） |

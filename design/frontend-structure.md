# 前端結構（`godot/`）

← [design index](README.md)｜repo：[README](../README.md)

各 `.gd` 按職責分層拆檔（多數 ~100 行；資料節點 `terrain.gd` 略多）。

`godot/` 下每支 `.gd`（及 headless 契約 probe）的職責表已抽到 [frontend-structure.json](frontend-structure.json)（32 列：`godot/` 根 30 列、`tests/` 下 2 列）。

- `檔`：`godot/` 下的檔名（`png16.gd` / `png16_codec.gd` 合一列；`tests/` 開頭的是 headless 契約 probe）。
- `職責`：class 名、職責、與其他模組的委派關係；有測試釘住的會寫測試檔名。

分層概要：根場景 `main.gd` 只留狀態與 callback，組裝在 `editor_setup.gd`、輸入在 `editor_input.gd`／`walk_mode.gd`；地形資料／座標／網格／筆刷分在 `terrain*.gd`；側欄 UI 分 `world_ui`／`grid_ui`／`placement_ui`／`splat_ui`；Skyrim 資產橋接是 `model_fetch`／`tex_fetch`（共用 `skyrim_ref`、`repo_layout`）；編解碼是 `png16*`／`splatmap_io`／`placements_io`。

## 外部工具路徑（`texconfig.json`）

`tex_fetch.gd` / `model_fetch.gd` 要 shell out 到**本 repo 之外**的兩個工具。預設值由**同層 repo 佈局**推導——`res://` 是 `<projects>/godot-worldspace-editor/godot`，於是 ModForge＝`<projects>/ModForge`、model-converter＝`<projects>/model-converter`。

三個 repo 不同層擺放時，在 `godot/texconfig.json`（gitignore，本機檔）覆寫：

```json
{
  "data_dir":    "/path/to/Skyrim Special Edition/Data",
  "cli_project": "/path/to/ModForge/src/ModForge.Cli",
  "mc_dir":      "/path/to/model-converter",
  "mc_python":   "/path/to/model-converter/.venv/bin/python"
}
```

省略 `mc_python` 時，Linux/macOS 取 `<mc_dir>/.venv/bin/python`，Windows 取
`<mc_dir>/.venv/Scripts/python.exe`。`ModelFetch` 的 converter 優先序為：
`MODFORGE_NIF2GLTF_BIN`（直接接 `--in/--out/--flat`）＞ 上述同層／texconfig
`mc_python -m nif2gltf` fallback。明示的 env hook 不存在時不會偷偷改跑 fallback。
其餘值全部可省，省的走推導值。

---

**顯示縮放**：`vis_height_scale`（Y）與 `vis_surface_scale`（X/Z）只影響顯示，資料恆為 game units；`Y=(h-min)·MPU·scale` 讓地板固定 Y=0。**高度著色**：以中間高度為基準，下沉→淺藍→深藍（水），上升→草綠→岩石→雪。**游標黃圈**（`_update_cursor`）半徑跟隨**當前模式**：Splat Mode 取 `SplatTool.radius`，否則取 `TerrainGrid.brush_radius`。**加 cell**：`TerrainGrid.resize_cells` + `SplatTool.resize_grid`（main `_add_cells` 串接）保 SW 原點、邊緣延伸，placements 座標不動。

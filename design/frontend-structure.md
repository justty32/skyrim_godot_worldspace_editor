# 前端結構（`godot/`）

← [design index](README.md)｜repo：[README](../README.md)

各 `.gd` 按職責分層拆檔（多數 ~100 行；資料節點 `terrain.gd` 略多）：

| 檔 | 職責 |
|---|---|
| `main.gd` | 根場景 `WorldspaceEditor`：常數與狀態、display 同步、`_add_cells`、export/import + 模式切換 callback；組裝委派 `editor_setup`，輸入/walk 委派下兩檔 |
| `editor_setup.gd` | `EditorSetup`（static，吃 `WorldspaceEditor`）：`_ready` 的整段組裝——env／terrain／camera rig／cursor／格線／四個工具節點，以及由四個 UI 模組拼出的側欄。**順序是有意義的**（terrain 要先於 camera、工具要先於側欄拿它們的 callback），由 `tests/test_editor_boot.py` 釘住 |
| `editor_input.gd` | `EditorInput`（static，吃 `WorldspaceEditor`）：LMB place/paint 派發、逐幀 cursor + 高度讀數 + paint tick（筆刷模式改由側欄按鈕選，原 R/L/F/S 熱鍵移除——S 會和 WASD 後退衝突）|
| `walk_mode.gd` | `WalkMode`（static）：第一人稱走地形預覽 enter/exit（生 PlayerController、暫停編輯輸入） |
| `terrain.gd` | 高度資料 + 碰撞 body（`TerrainGrid`）；座標換算委派 `terrain_coords` |
| `terrain_coords.gd` | `TerrainCoords`（static）：Skyrim↔Godot↔display↔vertex 座標換算 + ray 取點。`get_hit_position` 只把螢幕座標換成射線，交給 `raycast_surface(t, from, dir)` 沿射線 **raymarch 打地形表面**（雙線性 `surface_y_at` 取高度、`_slab` 先夾 footprint 限步數）→ 抬起的地形會擋住游標，非固定中平面。拆成兩層是為了讓落點判定不必有 Camera3D／Viewport 也能離線驗（`tests/test_terrain_coords.py`）。射線**從側面**進入 footprint 時，第一個取樣點已在地表下代表它從地形側壁進去，回進入點；只有射線起點就在 footprint 內（＝相機真的在地下）才回 `Vector3.ZERO` |
| `terrain_mesh.gd` | 從高度建 ArrayMesh（vertex/normal/uv + 高度漸層頂點色 + active splat 層 alpha overlay blend） |
| `terrain_brush.gd` | 4 brush 模式（raise/lower/flatten/smooth） |
| `camera_rig.gd` | orbit 編輯相機（middle orbit / scroll zoom / right pan）；**WASD 在地面平面平移**（依相機朝向，`_process`，文字框聚焦時跳過）；**Shift+滾輪不縮放**（讓位給側欄捲動）|
| `shift_scroll.gd` | `ShiftScroll`（`ScrollContainer` 子類）：側欄**只在 Shift+滾輪時上下捲**，平常滾輪吞掉（保留給相機縮放）|
| `ui_section.gd` | `UiSection`（static）：可收合側欄大項——標題 toggle 鈕（▼/▶）+ 內容 VBox，點擊收合整段。三大項 Height/Object/Texture 各包一個 |
| `grid_ui.gd` | `GridUi`：側欄 GRID 段——即時 cell/vert 維度 + 加/減東向欄(X+)、北向列(Y+) 的 cell（`terrain.resize_cells` 保 SW 原點）|
| `player_controller.gd` | Walk Mode 人形 `CharacterBody3D`（第一人稱 + WASD/跳/ESC） |
| `scene_builder.gd` | env / 編輯相機 / cursor / 格線 工廠 |
| `world_ui.gd` | 側欄（`ShiftScroll` + slider/spinbox）：頂層放 View/Walk/Info，其餘地形控制包進可收合「HEIGHT」大項 |
| `io_dialog.gd` | 高度 PNG export/import FileDialog |
| `png16.gd` / `png16_codec.gd` | 16-bit PNG encode/decode + chunk/CRC |
| `placement.gd` | `PlacedObject` 薄節點：metadata（base/instanceId/uniform_scale）+ box proxy 視覺；`set_model` 換成真實 glTF 模型（game-unit×METERS_PER_UNIT→顯示公尺，box 當 fallback）|
| `skyrim_ref.gd` | `SkyrimRef`（static）：`"<master>:0xFORMID"` 這個文字型 ref 的**驗證與正規化**。`is_valid` 是安全邊界——ref 會直接變成 `res://texcache`／`res://modelcache` 底下的檔名、也會直接進 ModForge CLI 的 argv，所以擋掉空 master、`/`、`\`、`..`、非 hex FormID 與超過 24 bit 的值；`canonical` 讓 `0x18199` 與 `0x018199` 共用同一個快取鍵。原本 `tex_fetch.gd` 與 `model_fetch.gd` 各有一份逐字相同的私有複本且兩份都沒有測試 |
| `repo_layout.gd` | `RepoLayout`（static）：**repo 之外**兩個工具與遊戲 Data dir 的位置解析——同層 repo 佈局推導預設值，`res://texconfig.json` 覆寫（見下）。回 `{data_dir, cli_project, mc_dir, mc_python}`。原本兩個 fetcher 各自推導，`tex_fetch.gd` 只解一部分，兩邊對「同一個 Data dir」的認定可能漂開；現在解一次 |
| `model_fetch.gd` | `ModelFetch`：base ref → 真實模型的平色 proxy 節點。兩段：CLI `nifexport`（抽 model .nif）→ `nif2gltf --flat` 轉 glTF，快取 res://modelcache/，`GLTFDocument` runtime 載入。converter 優先走 `MODFORGE_NIF2GLTF_BIN` 黑盒 executable；未設才走同層 model-converter venv 的 `python -m nif2gltf` fallback。nonzero／缺 `.gltf`／缺 `.bin`／Godot 無法解析皆 fail closed 並清掉整對 partial/stale cache，讓下次 explicit fetch 可重試。主力機限定，抽不到→留 box |
| `placement_tool.gd` | `PlacementTool`：placement 筆狀態 + 物件 list（place 吸地表 / restore / undo / clear）；rotation 三軸 `current_rot_x/y/z`|
| `placement_ui.gd` | 可收合「OBJECT」大項（mode 切換、base/instance 欄、**rotation X/Y/Z**/scale、count、JSON I/O 按鈕）|
| `placements_io.gd` | `placements.json` 匯出/匯入（顯示 scale 除掉還原 canonical 公尺）|
| `tests/placements_contract.gd` | headless placement contract producer：建立真實 `PlacedObject` 並呼叫 production `PlacementsIo._serialize`；外層 `tests/test_placements_contract.py` 餵同層 ModForge build 並讀回 REFR |
| `tests/model_fetch_contract.gd` | headless model consumer probe（只在 temporary project copy 執行）；外層 `tests/test_model_fetch_contract.py` 以 model-converter synthetic NIF + production CLI 驗 `ModelFetch` executable priority、Godot mesh/primitive/vertices/軸向尺度與 missing-bin/bad-glTF/nonzero fail-closed |
| `splat_tool.gd` | `SplatTool`：紋理 alpha 筆 — 層模型（多層 LTEX ref + alpha 格）+ paint（active 層、radius/strength/erase falloff）+ base 貼圖；地形視覺委派 `splat_render` |
| `splat_render.gd` | `SplatRender`（static，吃 `SplatTool`）：層資料 → 地形視覺橋——WYSIWYG 真實貼圖混合（`TerrainMaterial`）或頂點色 tint fallback |
| `splat_ui.gd` | 可收合「TEXTURE」大項（Splat Mode 切換、base 貼圖欄、層選擇+新增、LTEX ref〔Enter 抓圖〕、Paint/Erase、radius〔改 → 更新游標〕/strength、清層、Load real textures、splatmap PNG I/O）|
| `splatmap_io.gd` | splatmap 8-bit 灰階 PNG 匯出/匯入（Y-flip 頂=北，同 Png16/Heightmap 約定）+ 印出可貼進 spec 的 `textureLayers` 片段 |
| `tex_fetch.gd` | `TexFetch`：LTEX ref → 真實貼圖。OS.execute 呼叫 ModForge CLI `texexport`（LTEX→diffuse .dds 從遊戲 BSA→PNG），快取 res://texcache/；CLI 路徑由**同層 repo 佈局**推導、Data dir 自動偵測（可 texconfig.json 覆寫，見下）。主力機限定，抽不到→退回 tint |
| `terrain_material.gd` | `TerrainMaterial`：地形 WYSIWYG ShaderMaterial — tiled base 貼圖 + 至多 4 層 alpha 混合（alpha 格→R-float 貼圖，UV 取樣）；無真實貼圖時 fallback 頂點高度漸層色 |

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

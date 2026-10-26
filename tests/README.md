# 離線契約測試

← [repo README](../README.md)｜驗證規則：[testing](../wf/workflows/testing.md)

以下指令與程式碼路徑均以 repo 根目錄為基準。

## 離線 placement 契約測試

`tests/test_placements_contract.py` 把真正的 Godot exporter 輸出一路驗到 ModForge
寫出的 REFR；會鎖定 format version、座標系、display scale 還原、origin offset、
instanceId、base、rotation 軸轉換與 scale。執行：

```bash
python tests/test_placements_contract.py
```

快速 source gate 永遠執行；runtime 層需要 Godot 4 在 PATH（自動找 `godot4` / `godot` /
`godot-mono`），或設定 `GODOT_BIN`。本機 Manjaro 走 `godot-mono`（`/usr/bin/godot-mono`，
4.7.2.stable.mono），headless 即可，不必開 GUI。`godot/project.godot` 的 `config/features` 仍標 4.6，用 4.7 GUI 開過後才會由 editor 改寫，不手改。
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

`tests/test_terrain_mesh.py` 驗高度筆刷與增量網格更新——heightmap 是這個編輯器的主要產物
（ModForge 拿它生 LAND/VHGT），而每一個筆刷 tick 都走 `TerrainBrush.apply` ＋
`TerrainMeshBuilder.update_region`。增量路徑存在的唯一理由就是它應該跟整份重建等價，
而這句話先前只寫在註解裡沒人驗。五種筆劃（RAISE 中央／RAISE 角落／LOWER／FLATTEN／SMOOTH）
各比對一次增量與 `build_full` 的**已上傳 surface**（不是 `_m_*` 來源陣列——那樣會放過
「算完忘了 upload」）；另驗 smoothstep falloff 在半徑處歸零、筆刷不越界、以及長筆劃會在
`max_height` 飽和而不是溢出高度範圍。

`tests/test_terrain_coords.py` 驗 `TerrainCoords.raycast_surface`——游標與點擊的落點判定。
每個編輯模式（高度筆刷、splat 筆刷、物件擺放）都吃它的結果，`Vector3.ZERO` 是講好的「沒打到」
哨兵值。斷言跑在真正的 Godot runtime 上（`godot/tests/terrain_coords_contract.gd`），不需要
Camera3D：`get_hit_position` 只把螢幕座標換成一條射線，行進、footprint 裁切與各種 miss 都在
`raycast_surface` 裡。含一條回歸：**射線從側面低角度進入抬高地形**時，第一個取樣點是
footprint 進入點而不是相機位置，舊碼把它當成「相機在地下」而回 ZERO。

`tests/test_splat_contract.py` 驗 splatmap PNG（ModForge `textureLayers[].splatmap` 的生產者契約）
與兩個只在筆刷按住時才出現的側欄行為。PNG 的 **north-on-top 列序**是拿 Python 自己寫的 8-bit
解碼器驗的，不是拿 Godot 的 reader——writer 與 reader 一起弄反時 round-trip 測試照樣全綠，
只有獨立解碼器擋得住。另外覆蓋尺寸不符要拒收、`SplatTool.set_active` 在圖層被清空時不能變成 -1、
以及 `SplatUi.sync_layer_controls` 必須冪等（`paint()` 每 tick 都 `changed.emit()`）。

`tests/test_model_fetch_contract.py` 另驗 model-converter → Godot 的真實 process boundary：
synthetic NIF 經 production `nif2gltf` CLI 產生 `.gltf + .bin`，再由 production
`ModelFetch._load_gltf()` 載入並檢查 mesh、primitive、頂點軸向與尺度；也覆蓋 missing
bin、bad glTF、converter nonzero 與 repo cache 不污染。執行方式相同，runtime 層可用
`GODOT_BIN`、`MODEL_CONVERTER_DIR` 覆寫工具位置。

其餘三支同樣跑在 headless Godot runtime：`tests/test_editor_boot.py` 驗 `main.tscn` 組出的整個編輯器（地形、相機、游標、四個工具節點與側欄接線）；`tests/test_png16_contract.py` 驗 16-bit heightmap PNG；`tests/test_object_texture_contract.py` 驗 synthetic NIF → diffuse sidecar → Godot 套貼圖（固定讀同層 `../model-converter`）。全套逐支 `python tests/test_*.py`。

注意：consumer E2E 會在 `MODFORGE_DIR`（預設同層 `../ModForge`）裡 `dotnet build` 出 Debug 產物；不想動 ModForge 主樹時，把 `MODFORGE_DIR` 指向 ModForge 的 git worktree。


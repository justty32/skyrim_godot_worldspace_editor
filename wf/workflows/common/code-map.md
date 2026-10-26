# code-map — 程式碼導航 index（哪個檔負責什麼）

[common/README](README.md)｜[INDEX](../../INDEX.md)

碰原始碼前先查這張表，只讀相關領域列出的檔；動完再照維護鏈把表更新回去。寫碼慣例本身在 [conventions](conventions.md)。

## 領域表

| 領域 | 檔案 | 職責 | 測試在哪 |
|------|------|------|---------|
| 地形資料／網格／筆刷 | `godot/terrain*.gd` | 高度圖、座標與射線、增量網格、筆刷 | `tests/test_terrain_mesh.py`、`test_terrain_coords.py` |
| 紋理／splat | `godot/splat_*.gd`、`splatmap_io.gd`、`tex_fetch.gd` | splat 筆、splatmap PNG、貼圖抓取 | `tests/test_splat_contract.py` |
| 物件擺放 | `godot/placement*.gd`、`model_fetch.gd`、`obj_tex_fetch.gd` | placement 節點／工具／JSON、模型與貼圖預覽 | `tests/test_placements_contract.py`、`test_model_fetch_contract.py`、`test_object_texture_contract.py` |
| 編解碼 | `godot/png16*.gd` | 16-bit heightmap PNG | `tests/test_png16_contract.py` |
| 組裝／輸入／UI | `godot/main.gd`、`editor_setup.gd`、`editor_input.gd`、`*_ui.gd` | 根場景、節點組裝、輸入路由、側欄 | `tests/test_editor_boot.py` |
| Skyrim 路徑 | `godot/skyrim_ref.gd`、`repo_layout.gd` | ref 正規化、同層 repo 佈局 | `tests/test_skyrim_ref.py` |
| 全部 `.gd` | `godot/*.gd` | parse 護欄；逐檔職責見 [frontend-structure.json](../../../design/frontend-structure.json) | `tests/test_gdscript_parses.py` |

## 真相層優先序

各專案可以改自己的優先序，但必須明確。預設：

```text
code/tests > schema/examples/fixtures > code map > docs > generated
```

- 上層與下層衝突時，**以上層為準並修正下層**。
- generated（產生出來的檔、html）永遠不是唯一真相。
- 原始來源與摘要衝突時，以**原始來源**為準。
- code map 是**導航不是規格**；行為以 code/tests 為準。

## 維護鏈：程式碼 > code map > 文檔

**優先級**（衝突或時間不夠時，依序保持一致）：程式碼 > code map > 文檔。
**code map 與程式碼衝突時以程式碼為準，立刻改 code map。**

1. **修改前**：先讀本表找到相關領域，只讀清單裡的檔——不讀無關領域的檔。
2. **修改後**：新增／刪除了原始碼檔案，或某檔職責顯著改變，必須同步更新本表。
3. 原始碼裡**不加**「對應 code map」的註釋（維護成本過高）；反向查找直接 grep 本檔。
4. 迭代期間本表可暫時落後，**commit 前必須對齊**（見 [feature-dev](../feature-dev/README.md)）。

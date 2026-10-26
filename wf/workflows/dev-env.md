# dev-env — 開發環境、指令、外部工具

[WORKFLOWS](../WORKFLOWS.md)｜[INDEX](../INDEX.md)

這台機器上要能開發需要什麼、怎麼裝、跑什麼指令；外部工具設定與 env var 也收在這裡。

**何時用**：fresh clone、換機器、裝不起來、忘了指令、要加一個外部工具或環境變數。
**何時不用**：驗證 / 測試怎麼跑 → [testing](testing.md)；程式碼慣例 → [common/conventions](common/conventions.md)。

## Done when

- 照「流程（fresh clone 後）」走完，`python3 tests/test_terrain_coords.py` 回傳 0。
- 下面三張表沒有空欄；要使用者親自做的（帳號、授權、金鑰）在 [WAIT_USER](../../../../WAIT_USER.md) 各佔一行。

## 流程（fresh clone 後）

1. 取得原始碼；`../ModForge`、`../model-converter` 同層 clone 在同一父目錄（本機 `~/repo/moddings/skyrim/projects/`）——測試與執行期路徑都依此推導。
2. 裝 Godot 4：本機 Manjaro 是 `godot-mono`（`/usr/bin/godot-mono`，4.7.2.stable.mono），headless 即可。無須安裝其他依賴。
3. 跑一次冒煙指令確認：`python3 tests/test_terrain_coords.py`（約 4 秒）。

## 指令表

| 做什麼 | 指令 | 備註 |
|--------|------|------|
| 安裝依賴 | 無 | 只需 Godot 與 Python 3 |
| build | 無 | |
| 跑起來 | `godot-mono --path godot` | 進入點 `res://main.tscn`；GUI 實跑歸使用者 |
| lint / 型別 | `python3 tests/test_gdscript_parses.py` | `godot --headless --check-only` 掃全部 `.gd`，約 50 秒 |

驗證與測試指令不列這裡——連同「誰跑」一起在 [testing](testing.md)。

## 跨機 / 離線差異

| 環境 | 能跑 | 跑不了的 → 怎麼辦 |
|------|------|------------------|
| 本機 Manjaro（有 `godot-mono`）| 全部 `tests/test_*.py` | Godot GUI 目視（VTXT position 序等）記母 repo WAIT_USER |
| 無 Godot／無同層 ModForge | 各測試的 source gate | runtime 層缺 Godot 會明示 skip；consumer E2E 缺 ModForge 不跑 |

## 外部工具與 env var

| 名稱 | 用途 | 怎麼取得 / 設定 |
|------|------|----------------|
| `godot-mono` | headless 契約測試與 GUI | 系統套件；自動找 `godot4`／`godot`／`godot-mono` |
| `GODOT_BIN` | 指定 Godot 執行檔 | 環境變數，預設自動尋找 |
| `MODFORGE_DIR` | consumer E2E 的 ModForge 位置 | 預設同層 `../ModForge`；E2E 會在其中 `dotnet build` Debug 產物，不想動主樹就指向 git worktree |
| `MODEL_CONVERTER_DIR` | `nif2gltf` 工具位置 | 預設同層 `../model-converter` |
| `godot/texconfig.json` | 覆寫外部工具路徑 | 本機檔、gitignore；見 [frontend-structure](../../design/frontend-structure.md) |

需要帳號、付費、授權才能取得的：守鐵律 2（授權來源），並在 [WAIT_USER](../../../../WAIT_USER.md) 記一行。

## 交接

- 環境就緒要開工 → [feature-dev](feature-dev/README.md)；先確認驗證跑得動 → [testing](testing.md)。
- 同一個裝機坑第二次撞到 → [common/gotchas](common/gotchas.md)。

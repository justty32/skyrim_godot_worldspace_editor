# 物件貼圖預覽 — 規格（STAT diffuse WYSIWYG）

← [README](../README.md)｜相關：[frontend-structure](../design/frontend-structure.md)（地形貼圖既有管線）｜[decisions](../design/decisions.md)

**現況**：物件走 `nifexport` → `nif2gltf --flat` → `GLTFDocument` 的真實幾何，但材質是硬編灰色平色；
「物件 diffuse/normal/spec 貼圖不在現行 converter 的 flat 契約內」（[README.md:140](../README.md)）。
地形那條 LTEX→PNG 是**另一套**管線（`tex_fetch.gd` + `terrain_material.gd`），不能當物件規格。

本規格補的就是這個缺口：**讓 placement 的真實 mesh 帶上真實 diffuse**。

## 目標與非目標

| | |
|---|---|
| 目標 | 按下既有「Load real models」後，placement 顯示 **真實幾何 + 真實 diffuse**，離線可驗、不開 Skyrim |
| 非目標（v1） | normal / specular / glow / environment map；alpha test 與雙面判定；材質參數（gloss、tint）；LE-format nif；動態 mesh（TREE 擺動）|
| 非目標（永遠） | 把貼圖寫回 ModForge 契約——這是**前端預覽**，`placements.json` 不變、後端零改動 |

`placements.json` 的形狀（`version` / `coordinate_system` / `placements[]`）**不動**。貼圖純粹是前端顯示層。

## 資料從哪來（三段，全部已存在）

已用真實 vanilla 素材離線實證（2026-09-18，`Skyrim.esm:0x10C0E3` Barrel02Static）：

1. **base → .nif**：`nifexport <dataDir> <outDir> <master:0xFORMID>` 從 mesh BSA 抽出模型。
   已在用（`godot/model_fetch.gd`）。實測 → `Clutter\Barrel02.nif`。
2. **.nif → diffuse 路徑**：NIF 的 `BSLightingShaderProperty` → `BSShaderTextureSet` → `diffuse`。
   `nif2gltf` 的 parser **早就解出來了**並寫進 `Mesh.texture`（[nif_reader.py:144](../../model-converter/nif2gltf/nif_reader.py)、
   [geometry.py:35](../../model-converter/nif2gltf/geometry.py)），只是 `gltf_writer` 丟掉不用。
   實測 → `textures\clutter\Barrel02.dds`，且 **UV 已經有寫出**（`TEXCOORD_0`，`gltf_writer.py:115`）——這點關鍵，代表幾何端零改動。
3. **貼圖路徑 → PNG**：`texpath <dataDir> <outDir> <texPath>[,…]` 從 texture BSA 抽 .dds 轉 PNG。
   **這支 CLI 已經存在**（[TexExport.cs:60](../../ModForge/src/ModForge.Cli/Commands/TexExport.cs)），它的註解原本就寫著
   「Feeds the Godot object pipeline」，但 Godot 端從來沒呼叫過。實測 → 512×1024 PNG，742 KB。

**結論：三段都現成，缺的只有第 2 段的輸出通道與第 3 段的呼叫端。ModForge 零改動。**

## 契約擴充：`<stem>.textures.json` sidecar

glTF 本身**維持 flat**（不塞 image、不改材質），貼圖走旁邊一份 sidecar。理由：不動 `--flat` 契約就不會
踩到既有 glTF 結構測試，也不必在 Python 端做 base64 embed。`gltf_writer.py:139` **已經有清理
`<stem>.textures.json` 的邏輯**——這個檔名是上游預留的掛勾，只是從沒有人寫過它。

```json
{
  "contract": "gltf-textures/1",
  "source": "Skyrim.esm_0x10C0E3.nif",
  "meshes": [
    { "index": 0, "name": "shape_7", "diffuse": "textures\\clutter\\Barrel02.dds" }
  ]
}
```

- `meshes[]` 的**順序與 glTF 的 mesh 順序一一對應**；`index` 是該序號，`name` 是 `Mesh.name`。
- `diffuse` 是 NIF 原樣宣告的反斜線路徑（不正規化、不小寫化）；解不到貼圖的 shape 寫 `""`。
- 消費端**先用 `name` 配對，配不到才退回 `index`**。兩者都配不到就維持平色，不是錯誤。

### 誰產生這份 sidecar（我替使用者做的取捨）

正統的家是 `nif2gltf --textures`（[PROTOCOL.md:39](../../model-converter/PROTOCOL.md) 寫著「MVP 不實作」）。
但 `model-converter` 今天是 DSPort 線的資產，**本線不寫別隊的 repo**。
因此 v1 由本 repo 自備一支薄 shim：`tools/nif_textures.py`，**唯讀 import** sibling 的 `nif2gltf.nif_reader`，
產出上面那份 sidecar。等 `nif2gltf --textures` 正式落地，Godot 端把 shim 拔掉、改吃 converter 直接產的同一份檔即可
（sidecar 契約刻意訂成兩邊都能產的形狀，就是為了這個換手）。

## Godot 端怎麼載

沿用地形那套的形狀（`tex_fetch.gd` 是範本），新增 `godot/obj_tex_fetch.gd`：

| 項目 | 地形（既有） | 物件（本規格） |
|---|---|---|
| 鍵 | LTEX ref `master:0xID` | 貼圖路徑 `textures\…\x.dds` |
| CLI | `texexport` | `texpath` |
| 快取 | `res://texcache` | `res://texcache/obj/<hash>/` |
| 材質 | `ShaderMaterial`（多層 alpha 混合）| `StandardMaterial3D.albedo_texture` |

- 外部路徑一律走既有的 `RepoLayout.resolve()`，**不另外推導**（那正是 RepoLayout 存在的理由）。
- **快取用雜湊子目錄，不用裸 basename**：`texpath` 輸出檔名是 `<basename>.png`，
  vanilla 有大量同名不同目錄的 .dds（`stone01.dds` 之類），共用一層會互相覆蓋。
  子目錄名＝完整貼圖路徑（小寫、`\`→`/`）的 SHA-1 前 16 碼。這是**消費端自保**，ModForge 不用改。
- 套用點：`PlacedObject.set_model()` 之後呼叫 `apply_textures(sidecar)`，
  逐 `MeshInstance3D` surface 設 `material_override`（`StandardMaterial3D`，`albedo_texture = tex`）。
  UV 已在 glTF 裡，不需任何幾何處理。
- **觸發時機不新增開關**：沿用既有 `allow_fetch` 與「Load real models」按鈕。
  按鈕按一次 = 模型與貼圖一起帶出來。使用者不需要學新東西。
- **離線降級不是錯誤**：`data_dir` 為空（沒裝遊戲的機器）、貼圖不在 BSA、sidecar 不存在——
  全部安靜退回現有平色 proxy，只在 log 記一行。這條沿用 `RepoLayout.available()` 的既有語意。

## 效能上限

實測單張 512×1024 RGB8 PNG ＝ 742 KB 磁碟、mipmap 後約 2 MB VRAM；vanilla 常見 1024²／2048² 會再上去 4–16 倍。

| 閘門 | 值 | 理由 |
|---|---|---|
| 同一貼圖路徑只抓一次 | 記憶體 + 磁碟兩層快取 | 一片場景幾十個桶子共用一張圖，這是最大宗的省 |
| 單次「Load real models」抓取上限 | **64 個相異貼圖** | 超過就停、面板顯示「還有 N 張未載入」，再按一次繼續 |
| 單張貼圖大小上限 | **16 MB PNG** | 超過跳過並記 log，避免 4096² 未壓縮 PNG 打爆記憶體 |
| `texpath` 呼叫批次 | 一次呼叫最多 32 條路徑（逗號分隔）| CLI 支援批次；減少 `dotnet run` 啟動成本（每次約數秒）|
| mipmap | 開（比照 `tex_fetch._load_png`）| 遠處物件不閃爍 |

v1 **不做**非同步載入：沿用地形貼圖「按鈕按下去會卡一下」的既有體感，先求正確。

## 驗證（不開 Skyrim）

比照 `tests/test_model_fetch_contract.py` 的 process-boundary 寫法，新增 `tests/test_object_texture_contract.py`：

1. **sidecar 產生器**：synthetic NIF（帶已知 diffuse 路徑）→ `tools/nif_textures.py` → 驗 sidecar 的 `contract`／`meshes[].name`／`diffuse` 逐欄相符。
2. **Godot 端套用**：headless GDScript probe 載入 flat glTF + 一張合成 PNG，
   驗每個 `MeshInstance3D` 的 `material_override.albedo_texture` **非 null 且尺寸相符**（不是只驗「有呼叫」）。
3. **降級**：sidecar 缺席／`diffuse` 為空／PNG 不存在 → 不丟例外，維持平色 proxy。
4. **快取鍵**：兩條**不同目錄、同 basename** 的貼圖路徑必須落在不同快取子目錄（擋上面那個覆蓋陷阱）。

真實素材端到端（有遊戲檔的機器才跑，缺 Data 就 skip）：
`Skyrim.esm:0x10C0E3` 走完三段應得到 512×1024 的 `Barrel02` PNG。

## 我替使用者做的假設（可翻案）

1. **v1 只做 diffuse**，normal/spec 延後。理由：diffuse 給出 90% 的「看起來對了」，normal 需要切線與
   綠通道慣例判定，spec 在 Skyrim 是塞在 normal 的 alpha，兩者都會讓 v1 變成材質工程。
2. **sidecar shim 放本 repo，不改 `model-converter`**。理由：那是別隊的 repo。代價是同一份契約短期有兩個可能的產生者。
3. **契約走 sidecar，不走 glTF 內嵌材質**。理由：不動 `--flat` 契約、不碰既有 glTF 結構測試。
4. **不新增 UI 開關**，跟著「Load real models」一起走。
5. **貼圖不進 `placements.json`**，後端零改動。

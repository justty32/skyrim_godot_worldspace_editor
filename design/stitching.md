# 分塊編輯 → 拼大圖（stitching）

← [design index](README.md)｜sub_proj：[README](../README.md)｜相關：[座標系](coord-system.md)　[placements 格式](placements-format.md)　[決策](decisions.md)

大世界的作法不是「畫一張巨圖」，而是**一次編十幾格 cell 的 chunk，最後拼成一張大 PNG 再交給 ModForge 當「一個 worldspace」生成**。本檔記這條工作流與其鎖定決策。

## 核心觀念：大圖 = 一張大 PNG，不是 N 個世界黏起來

ModForge 是「**一張 heightmap PNG → 切 N×M cell grid → LAND**」。所以拼接的正解是把各 chunk 的 PNG **合成成一張大 PNG**（height + splat）+ 一份合併的 placements，**再讓 ModForge 切**。

白賺的好處：**VNML 法線在 chunk 邊界自動正確**——ModForge 在「已連續的大 PNG」上重算法線、切割，邊界縫不存在。故「先合成大 PNG 再切」遠優於「每 chunk 各生一個 worldspace 再黏」。

## 邊界對齊＝手動（鎖定）

各 chunk 獨立編輯，相鄰邊高度/紋理不會自然吻合 → 交界處會有懸崖/紋理斷層。**決策：手動對齊**（不做骨架先行的自動化）。可行前提是「編輯一塊時看得到鄰塊的邊緣」，慣例：

- **開新 chunk 時先 import 已完成鄰塊的邊緣**（共用那一排頂點高度直接複製當起點），只往內側編 → 共用邊**天生吻合**，不用「對」。是「手動」但有輔助。
- 退一步：編輯器把鄰塊邊緣顯示成 ghost 參考，照著刷。

## stitch 工具＝純貼上（鎖定）

按 manifest 把各 chunk 的 PNG 貼到大圖對應像素位置（**不混合、不羽化**，相信手調結果）；placements 平移到大圖絕對座標後串接、`instanceId` 去重。頂多一個**可選**「共用邊取平均」保險清掉 1–2px 殘差，不碰內部。**ModForge 核心零改動。**

## 拼接三件事（皆確定性運算）

每 chunk 匯出三樣：`heightmap.png` + `splatmap.png` + `placements.json`。

1. **manifest（版圖清單）**：每 chunk 的 `(chunkCol, chunkRow)` → 大 PNG 像素偏移 + cell 座標原點。
2. **影像合成**：各 height/splat PNG 貼到對應位置（相鄰格共用邊緣欄，承襲既有單張 PNG 的 seam 約定）。
3. **placements 合併**：各 chunk 座標按其原點平移到大圖絕對座標、串接、`instanceId` 去重。`godotPlacements` 已有 `originX/originY`，偏移機制現成。

## 兩個全局約定（與對齊無關，但必守）

- **紋理調色盤全局共用**：chunk 間 splat layer index 必須對到**同一個 LTEX**，否則合成後同層代表不同地表。→ 在地圖層級定一份 texture palette，chunk 都引用它。
- **instanceId 全局命名空間**：合併時去重，避免兩 chunk 撞名。

## 編輯器要長出的能力（待做）

- **載入大圖的一個子區域編輯**（origin + size，`resize_grid` 已有雛形）+ **import/顯示鄰塊邊緣**（手動對齊的前提）。
- **stitch 步驟**（離線工具）：吃 manifest + N 個 chunk 匯出 → 吐一張大 height PNG + 大 splat PNG + 合併 placements.json。

## 天花板（老實講）

大 worldspace = 大 PNG + 多 cell + 多 ref，**遠景 LOD（xLODGen）**是已知硬點；務實短期靠霧遮、規模先小後大。不影響「分塊編輯→拼大圖」流程本身成立——LOD 是出貨打磨階段的事。

## 相關：GDScript 程序化擺放

物件擺放除了手動 Place Mode，也可用 **GDScript 程序化**：編輯器已有 `terrain.get_height()` / 座標換算 / `PlacementTool`（`restore` 即「給座標放一個」）/ 匯出鈕，寫迴圈+noise 算座標、取地表貼地、塞進場景，按現成匯出鈕即可，**ModForge 零改動**。詳見 [README 資料流](../README.md#資料流)。注意 `placements.json` 只裝物件 REFR；map marker（XMRK）走 spec `mapMarkers[]`，LCTN 可發現地點記錄 ModForge 尚未生成（獨立缺口）。

# 專案：雙人連線 Roguelite

2D 俯視角、雙人連線的奇幻 roguelite 割草遊戲。劍與魔法設定，未來要能擴充到更多玩家。

參考《雨中冒險 2》的系統設計：一連串小房間、難度隨時間持續上升、道具撿到就生效且可無限堆疊，後期堆到「隨便一擊就滿螢幕閃電與爆炸」的爽快感。

## 你的角色

你是這個專案的資深工程師。我是獨立開發者，程式能力普通，Godot 經驗有限。

- 寫出**乾淨、有註解、我看得懂**的程式碼
- **每完成一個可驗證的階段就停下來**，讓我先跑起來確認，再繼續下一步
- 不要一次把整個里程碑寫完就交給我
- 每個步驟結束時，明確告訴我**怎麼驗證它有效**、**該看什麼**、**預期看到什麼**
- 需要目視確認的事情你做不到（你看不到我的螢幕），請明確請我回報

有任何你覺得我的決策不合理的地方，直說。

## 開發環境

Godot 執行檔：`.\Godot_v4.7.2-stable_win64_console.exe`（在專案根目錄；Windows 上要用 console 版才看得到 stdout）

```bash
# 匯入專案、產生 .godot 快取（新專案第一次必跑）
godot --headless --quit --path .

# 跑測試腳本，直接讀 stdout
godot --headless --path . --script res://tests/<file>.gd

# 跑專用伺服器
godot --headless --path . -- --server

# 匯出 dedicated server（需先安裝 export templates）
godot --headless --path . --export-release windows_server
```

**邏輯層改動後，請自己跑一次測試再交給我。**

## 不可違反的核心原則

這六條貫穿所有里程碑，任何時候都不可偏離：

1. **固定 tick**：所有遊戲邏輯跑在 60Hz 的 `_physics_process`，用 tick 編號當時間單位。**絕對不要用秒數或 delta time 描述遊戲事件的時刻。**
2. **server-authoritative**：伺服器跑所有遊戲邏輯與判定，客戶端只送輸入、收結果。
3. **輸入抽象層**：角色永遠不直接讀鍵盤或手把，只接受 `InputFrame`。
4. **不假設玩家數量**：一律用 `Dictionary[peer_id]`，不可出現 `player1` / `player2` 這種變數。
5. **雙模式**：同一份程式碼要能以「本機主機兼玩家」或「雲端專用伺服器」啟動，用 `OS.has_feature("dedicated_server")` 分岔。
6. **不使用 `MultiplayerSynchronizer` 同步角色位置**。它沒有預測和插值，會抖。位置同步自己寫。（血量、分數這類低頻狀態可以用）

## 技術決策（已定案，如有疑慮先問我）

- Godot 4.7.2、GDScript（不用 C#）
- 2D 俯視角
- 傳輸層 `ENetMultiplayerPeer`，**不引入任何外部連線框架**（Photon、Mirror、Nakama 都不要）
- **不做幀級的精確閃避或彈反**。敵人攻擊預告時間長、危險範圍明確，玩家靠走位躲避

## 美術方向

**全程使用純色幾何圖形當佔位素材。不要花任何時間在美術、動畫、音效、UI 美化上，直到戰鬥手感確定為止。**

唯一例外是**顏色編碼**——危險色的規則從第一天就要遵守，它是架構的一部分，不是美術。見 `docs/05-readability.md`。

## 文件索引

| 文件 | 內容 | 何時讀 |
|---|---|---|
| `docs/00-design-overview.md` | 遊戲定位、技術性的定位、單場時長目標 | **開始任何工作前先讀** |
| `docs/01-networking.md` | 連線架構：tick、輸入層、預測與和解、插值、雙模式 | M1 |
| `docs/02-characters.md` | 三職業設計、開發順序、隊友向技能 | M2、M6 |
| `docs/03-items-modifiers.md` | 觸發係數、事件匯流排、堆疊公式、道具清單 | M3 |
| `docs/04-progression.md` | 難度時鐘、房間循環、經濟、岔路結局、紀錄板、解鎖 | M4 |
| `docs/05-readability.md` | 危險色、渲染層、特效管理、死亡回放 | M5（但顏色規則從 M1 就遵守） |
| `docs/milestones.md` | 里程碑拆分與驗收標準 | 每個里程碑開始前 |

## 目前狀態

**M1（連線骨架）已完成**（2026-08-31，驗收 5 點全過）。

- 預測/和解：100ms/向延遲下和解修正 0 次
- 匯出的 dedicated server 以 feature 分岔自動啟動，雙客戶端同連通過
- 測試：`tests/` 下四個 headless 測試腳本，邏輯改動後都要跑
- 除錯：F1 切換模擬延遲；`--server`、`--join <ip>`、`--bot`、`--latency <ms>`、`--quit-after-ticks <n>`

**下一步：M2（戰鬥基礎，只做劍士）。** 開發以單機先行（見 `docs/milestones.md` 註記）。

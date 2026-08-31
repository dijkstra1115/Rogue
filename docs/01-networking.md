# 連線架構（M1）

## 目標

兩台電腦（或本機開兩個實例）能連線，畫面上各自出現兩個方塊，都能用手把移動，且**本地玩家的移動沒有任何可感知的輸入延遲**，遠端玩家的移動平滑不抖動。

美術用純色 `ColorRect` 或 `Polygon2D` 即可。

## 1. Tick 系統

- 專案設定 `physics/common/physics_ticks_per_second = 60`
- 一個全域 tick 計數器，所有網路訊息都攜帶 tick 編號
- 遊戲邏輯只在 `_physics_process` 執行，`_process` 只做視覺插值

```gdscript
var current_tick: int = 0

func _physics_process(_delta: float) -> void:
    current_tick += 1
    simulate_tick(current_tick)
```

**每個輸入、每次攻擊、每個時間窗口，都用 tick 編號記錄，不用秒數。** 這樣兩台電腦談論同一個時刻時才有共同語言。

## 2. 輸入抽象層

建立 `InputFrame` 資料結構：

```gdscript
class_name InputFrame

var tick: int
var move: Vector2
var aim: Vector2
var primary: bool
var secondary: bool
var utility: bool
var special: bool
var interact: bool
```

**技能欄位用通用名稱（primary/secondary/utility/special），不要用 attack/dodge 這種綁定特定動作的名字**——三個職業的技能內容完全不同。

- 本地玩家：從手把／鍵盤產生 `InputFrame`
- 遠端玩家：從網路封包產生 `InputFrame`
- AI（未來）：也產生 `InputFrame`

**角色的模擬函式只接受 `InputFrame`，對來源一無所知。** 這一層是整個架構的關鍵，請做紮實。

## 3. 玩家管理

- **不可以出現 `player1` / `player2` 這種變數**
- 一律用 `Dictionary`，以 `peer_id` 為 key
- 鏡頭、UI、玩家清單全部由資料驅動
- 房間人數上限寫成一個常數，方便未來調整

## 4. 連線建立

```gdscript
const PORT := 7777
const MAX_PLAYERS := 8   # 未來要 32 就改這個數字

func host_game() -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_server(PORT, MAX_PLAYERS)
    multiplayer.multiplayer_peer = peer

func join_game(ip: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_client(ip, PORT)
    multiplayer.multiplayer_peer = peer
```

輸入上傳：

```gdscript
@rpc("any_peer", "unreliable_ordered")
func submit_input(input_data: Dictionary) -> void:
    if not multiplayer.is_server():
        return
    var sender_id := multiplayer.get_remote_sender_id()
    input_buffers[sender_id].append(InputFrame.from_dict(input_data))
```

## 5. 客戶端預測與和解

**這是最難也最有價值的一步。**

- 客戶端送出 `InputFrame` 後，**立刻**本地模擬，不等伺服器
- 保留已送出但未確認的輸入佇列，以及對應的狀態歷史
- 收到伺服器狀態後比對：一致就清掉歷史；不一致就回到伺服器位置，重跑之後所有未確認的輸入
- **位置修正要平滑，不要瞬移**

```gdscript
func on_server_state(tick: int, pos: Vector2) -> void:
    if pending_inputs.is_empty():
        return
    var predicted: Vector2 = state_history[tick]
    if predicted.distance_to(pos) < 0.5:
        prune_history(tick)   # 猜對了
        return
    # 猜錯了：回到伺服器位置，重跑之後的輸入
    global_position = pos
    for frame in pending_inputs.filter(func(f): return f.tick > tick):
        simulate(frame)
```

## 6. 遠端實體插值

- 遠端實體維持一個狀態緩衝區
- 以約 **100ms 的延後時間點**做插值渲染
- 緩衝區空掉時要有合理的外推或凍結行為，不要爆炸

## 7. 雙模式啟動

```gdscript
func _ready() -> void:
    if OS.has_feature("dedicated_server"):
        host_game()          # 純伺服器，不生成本地玩家，不建立鏡頭
    else:
        show_main_menu()     # 一般客戶端（Host / Join）
```

也請支援命令列參數（`--server`、`--join <ip>`）方便測試。

**未來要部署到雲端 VPS 時，這是唯一需要的分岔——遊戲邏輯一行都不用改。**

## 8. 專案結構

規劃清楚的資料夾與腳本分層，讓**網路層、模擬層、表現層**明確分離。表現層（動畫、特效）之後才會加，但現在就要留好位置。

## 9. 除錯疊層（必需，不是加分項）

顯示：當前 tick、ping、未確認輸入數量、和解修正次數。

**連線出問題時，沒有這個東西你會完全瞎掉。** 後續開發會一直用到。

## 明確禁止

- ❌ **不要用 `MultiplayerSynchronizer` 同步角色位置**（沒有預測和插值，會抖）
- ❌ 不要引入任何外部連線框架或 addon
- ❌ 不要寫 Steam 整合、NAT 打洞、房間配對
- ❌ 不要做分割畫面
- ❌ 不要做戰鬥、敵人、傷害、血條
- ❌ 不要做道具、難度時鐘、房間切換（M3/M4）
- ❌ 不要做幀級無敵閃避或彈反，本專案不需要
- ❌ 不要用秒數描述遊戲事件時刻

## 為後續里程碑預留

- **技能系統要能指定目標為「隊友」**，不可寫死成只作用於自身
- **所有傷害事件要能攜帶額外欄位**（觸發係數、遞迴深度等），M3 會用到
- **玩家的屬性要能被外部修飾器動態改寫**，不要寫成固定常數

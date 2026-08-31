# 道具與 Modifier 架構（M3）

**這是整個遊戲的技術核心。架構做對了，之後每加一個道具都會自動和所有既有道具產生交互；做錯了，效果數量一多就會爆炸。**

## 一、觸發係數（Proc Coefficient）— 優先於任何單一道具

**沒有這個機制，三個職業一定會失衡。**

弓手每秒攻擊 10 次、劍士每秒 1 次。同一個「命中時 25% 觸發閃電」的符文，弓手會比劍士強 10 倍。

解法：每一次傷害事件攜帶一個觸發係數，所有「命中觸發類」效果的機率都要乘上它。

| 攻擊類型 | 建議係數 |
|---|---|
| 慢速重擊（劍士揮擊、法師爆發） | 1.0 |
| 中速攻擊 | 0.6 |
| 快速連射（弓手每一箭） | 0.2 – 0.5 |
| 持續傷害（流血、燃燒） | 0.0 |
| 由觸發效果產生的傷害（連鎖閃電本身） | 0.0 – 0.2 |

**設計意圖**：劍士每一下都很可能觸發，弓手靠次數堆積。期望值接近，但體感完全不同。

```gdscript
class_name HitContext

var attacker: Player
var target: Enemy
var damage: float
var proc_coefficient: float = 1.0
var proc_depth: int = 0        # 防止觸發引發觸發的無限遞迴
var tick: int
```

## 二、兩種堆疊曲線（必須嚴格區分）

```gdscript
# 線性堆疊：給玩家失控的爽感
# 用於：傷害、攻速、投射物數量、爆炸範圍、觸發次數
func linear_stack(base: float, per_stack: float, count: int) -> float:
    return base + per_stack * count

# 遞減堆疊：守住遊戲不會停止運作
# 用於：暴擊率、傷害減免、閃避率、冷卻縮減、任何「機率」與「減免」
func hyperbolic_stack(k: float, count: int) -> float:
    return 1.0 - 1.0 / (1.0 + k * count)
```

**判斷規則**：這個效果疊到極限會讓遊戲**更誇張** → 線性；會讓遊戲**停止運作**（無敵、無限資源、秒殺全場）→ 遞減。

## 三、事件匯流排

### 絕對禁止

```gdscript
# ❌ 絕對不要這樣寫
if has_triple_shot: ...
if has_homing: ...
if has_chain_lightning: ...
```

### 事件節點

- `on_attack_start` — 攻擊發動時（可修改投射物數量、散布角）
- `on_projectile_spawn` — 每個投射物生成時（可掛載行為元件）
- `on_hit` — 命中時（可修改傷害、觸發額外效果）
- `on_kill` — 擊殺時（可觸發爆炸、回復、生成物）
- `on_take_damage` — 受傷時
- `on_room_clear` — 房間清空時
- `on_ally_hit` / `on_ally_low_health` — 隊友相關

### 基底類別

```gdscript
class_name Modifier

var stack_count: int = 1
var priority: int = 0   # 決定同一事件上的執行順序

func on_attack_start(ctx: AttackContext) -> void: pass
func on_projectile_spawn(proj: Projectile) -> void: pass
func on_hit(ctx: HitContext) -> void: pass
func on_kill(ctx: KillContext) -> void: pass
```

### 範例

```gdscript
# 三重奏：在攻擊發動時增加投射物數量
class TripleShot extends Modifier:
    func on_attack_start(ctx: AttackContext) -> void:
        ctx.projectile_count += 2 * stack_count
        ctx.spread_angle += 15.0

# 追魂箭羽：在投射物生成時掛上追蹤行為
class HomingFletching extends Modifier:
    func on_projectile_spawn(proj: Projectile) -> void:
        proj.add_behavior(HomingBehavior.new(3.0 * stack_count))

# 雷紋符文：命中時有機率連鎖閃電
class LightningRune extends Modifier:
    func on_hit(ctx: HitContext) -> void:
        if ctx.proc_depth >= MAX_PROC_DEPTH:
            return
        var chance := hyperbolic_stack(0.25, stack_count) * ctx.proc_coefficient
        if randf() < chance:
            spawn_chain_lightning(ctx, 2 + stack_count)
```

**這三個道具的作者互不知道彼此存在，但它們會自動組合。** 每新增一個道具，它會自動和所有既有道具產生交互，不需要寫任何額外程式碼。

## 四、必要的防護

- **內部冷卻**：任何會回復資源或觸發連鎖的效果，必須有最小觸發間隔（例如 0.2 秒）
- **遞迴深度上限**：`proc_depth` 超過上限（建議 3）就不再觸發
- **每幀觸發上限**：防止後期效能崩潰
- **觸發產生的傷害，其 `proc_coefficient` 必須大幅降低或設為 0**，否則形成正回饋迴圈

## 五、六種設計原型

新增道具時，每一個都應該屬於以下其中一種：

1. **純數值** — 傷害、攻速、移速、血量。無聊但必要，它們是後期爆炸的燃料
2. **命中觸發** — 「滿螢幕特效」的引擎
3. **擊殺觸發** — 屍體爆炸、回血、掉落。後期會產生連鎖反應
4. **條件加成** — 滿血時傷害翻倍、對高血量敵人加傷。這類會**改變打法**
5. **冷卻型大招** — 保命符，構築的核心
6. **詛咒** — 高風險高回報，**唯一會讓玩家猶豫要不要撿**的類別

## 六、起始 20 個道具

**M3 只需實作其中 10 個**，優先選擇涵蓋所有事件節點的組合。M3 的目標是驗證架構能自動組合，不是內容量。

### 白（常見）

| 名稱 | 效果 | 事件節點 | 堆疊 |
|---|---|---|---|
| 磨刀石 | 傷害 +12% | 被動數值 | 線性 |
| 疾風羽 | 攻速 +15% | 被動數值 | 線性 |
| 旅人靴 | 移速 +14% | 被動數值 | 線性 |
| 生命草 | 最大生命 +25 | 被動數值 | 線性 |
| 火花符文 | 命中時 8% 機率造成小範圍爆炸 | `on_hit` | 遞減（機率） |
| 荊棘之種 | 命中時造成流血（持續傷害，可疊層） | `on_hit` | 線性 |
| 破甲釘 | 對滿血敵人傷害 +75% | `on_hit` | 線性 |

### 綠（罕見）

| 名稱 | 效果 | 事件節點 | 堆疊 |
|---|---|---|---|
| 雷紋符文 | 命中時 25% 機率連鎖閃電，跳 3 個目標 | `on_hit` | 遞減（機率）／線性（跳數） |
| 追魂箭羽 | 投射物獲得追蹤能力 | `on_projectile_spawn` | 線性（轉向速度） |
| 穿刺之刃 | 投射物穿透 +1 個敵人 | `on_projectile_spawn` | 線性 |
| 亡者餘燼 | 擊殺時屍體爆炸 | `on_kill` | 線性（範圍與傷害） |
| 吸血符文 | 命中時回復 1.5 點生命 | `on_hit` | 線性 |
| 石膚護符 | 15% 機率完全格擋一次攻擊 | `on_take_damage` | **遞減（必須）** |
| 迴響之石 | 技能冷卻縮減 10% | 被動數值 | **遞減（必須）** |

### 紅（傳說）

| 名稱 | 效果 | 事件節點 | 堆疊 |
|---|---|---|---|
| 三重奏 | 攻擊分裂成 3 發（傷害各 60%） | `on_attack_start` | 線性（+2 發／層） |
| 天罰符文 | 命中時 5% 機率召喚範圍落雷 | `on_hit` | 遞減（機率）／線性（傷害） |
| 不滅之心 | 受致命傷害時免疫並回復 40% 血量，冷卻 45 秒 | `on_take_damage` | 線性（減冷卻） |
| 連禱之鏈 | **所有觸發效果的觸發係數 +30%** | 全域修飾 | **遞減（必須）** |

### 紫（詛咒）

| 名稱 | 效果 |
|---|---|
| 碎裂之鏡 | 傷害 ×2，最大生命 −50% |
| 貪婪契約 | 寶箱掉落數量 +1，但難度時鐘走得快 25% |

### 需要特別盯緊的兩個

**連禱之鏈** 是乘法型道具，強化所有其他觸發效果。這類東西疊多了會讓遊戲崩壞，**必須遞減堆疊**。但它也正是玩家會尖叫的那種道具，值得保留。

**貪婪契約** 把遊戲的核心抉擇（時間 vs 強度）直接做成一個可以撿的東西。對雙人來說，撿不撿是需要商量的——這是刻意的。

### 法師專屬道具（M6 才做）

法力回復速度、蓄力速度、爆發範圍、蓄力期間傷害減免。

## 七、測試模式（早點做，你會用它幾百次）

一個獨立場景：

- 空房間 + 一隻不會反擊的沙包敵人
- 選單可直接給自己任意道具、任意堆疊數量
- 顯示即時 DPS、每秒觸發次數、當前特效數量
- 可直接切換角色、調整難度值

**Supergiant 在 Hades II 正式發售一年後仍在修祝福之間的組合衝突。** 這個測試模式是唯一能有效率發現這類問題的工具。

## 八、新增道具的三個檢驗

1. **它會和既有道具產生交互嗎？** 至少一半的道具要是會交互的
2. **疊到 20 個會怎樣？** 如果答案是「遊戲停止運作」，改成遞減堆疊
3. **玩家撿到會不會有反應？** 如果撿到跟沒撿到感覺一樣，它就太弱了——**在這類遊戲裡，無聊比失衡更致命**

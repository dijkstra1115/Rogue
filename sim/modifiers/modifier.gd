## 道具（Modifier）基底類別（M3）——事件匯流排的掛點。
##
## 鐵律（docs/03）：絕對不要在戰鬥程式碼裡寫 `if has_某道具`。
## 每個道具只覆寫自己需要的掛點；作者互不知道彼此存在，但會自動組合。
##
## ctx 一律用 Dictionary（與傷害事件同風格），內容依事件而異，
## 修改 ctx 的欄位就是道具生效的方式（例如把 ctx.damage 加倍）。
class_name Modifier
extends RefCounted

## 觸發引發觸發的遞迴深度上限（防護，docs/03 第四節）
const MAX_PROC_DEPTH := 3

var id: String = ""              # 唯一識別（"whetstone"）
var display_name: String = ""    # 顯示名稱（「磨刀石」）
var rarity: String = "white"     # white / green / red / purple
var stack_count: int = 1
var priority: int = 0            # 同一事件上的執行順序（小的先跑）


## 被動屬性修飾：直接改寫 stats 欄位（damage_mult、attack_speed、
## move_speed_mult、max_hp）。每次堆疊變動時整組重算，不做增量修補。
func modify_stats(_stats: Dictionary) -> void:
	pass


## 攻擊發動時（可改 arc_count、spread_deg、damage_scale——三重奏在這裡）
func on_attack_start(_ctx: Dictionary) -> void:
	pass


## 命中時（可改 ctx.damage、依 proc_coefficient 擲觸發——符文都在這裡）
func on_hit(_ctx: Dictionary) -> void:
	pass


## 擊殺時（屍爆、回復——ctx 有 pos、enemy_id、killer）
func on_kill(_ctx: Dictionary) -> void:
	pass


## 受傷時（可改 ctx.amount 或設 ctx.blocked = true——石膚在這裡）
func on_take_damage(_ctx: Dictionary) -> void:
	pass

## 技能基底類別（M2 步驟 1）。
##
## 架構要求（docs/02）：目標類型必須支援「隊友」，不可寫死只作用於自身——
## 劍士抓鉤拉隊友、弓手給隊友護盾、法師的增益法陣都會用到 TargetKind。
##
## 冷卻一律用 tick 計算（核心原則 1）。執行流程由伺服器驅動：
##   game_world 消化 InputFrame → is_ready() → mark_used() → execute()
## 客戶端不執行技能（攻擊不預測），只收事件呈現視覺。
class_name Ability
extends RefCounted

## 技能的目標類型（M6 的弓手/法師會用到 ALLY 與 POINT）
enum TargetKind { SELF, ENEMIES, ALLY, POINT }

var target_kind: TargetKind = TargetKind.SELF

## 基礎冷卻（tick）。實際冷卻可能被攻速縮放（見下）
var base_cooldown_ticks: int = 60

## 攻擊類技能隨攻速縮放冷卻；位移/輔助類（衝刺、抓鉤）不縮放
var scales_with_attack_speed: bool = false

## 下次可使用的 tick
var _ready_at_tick: int = 0


func is_ready(tick: int) -> bool:
	return tick >= _ready_at_tick


## 進入冷卻。attack_speed 是玩家屬性（M3 的 modifier 會動態改寫）。
func mark_used(tick: int, attack_speed: float = 1.0) -> void:
	var cooldown := base_cooldown_ticks
	if scales_with_attack_speed:
		cooldown = maxi(1, roundi(base_cooldown_ticks / attack_speed))
	_ready_at_tick = tick + cooldown


## 執行技能（只在伺服器呼叫）。子類別覆寫。
## world = game_world（拿玩家狀態、排入事件）；frame 提供 aim 等輸入。
## 回傳是否成功發動——false 代表沒有有效目標等情況，「不消耗冷卻」。
func execute(_world: Node2D, _caster_id: int, _frame: InputFrame, _tick: int) -> bool:
	return false

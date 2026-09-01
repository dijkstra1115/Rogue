## 敵人攻擊預告（危險區域視覺）。
##
## docs/05 的鐵律：品紅色系「只」給敵人危險區域用，任何玩家特效不得使用；
## 而且必須畫在專屬 CanvasLayer（DangerLayer），永遠蓋在玩家特效之上。
##
## 時間軸用 world.telegraph_clock()：伺服器＝current_tick，
## 客戶端＝插值渲染時鐘——這樣預告和「延遲 100ms 渲染的敵人」用同一個時間座標，
## 圓圈的充能進度與敵人動作對得上。
class_name TelegraphFx
extends Node2D

## 危險色：品紅（保留色，玩家特效禁用）
const DANGER_COLOR := Color(1.0, 0.1, 0.5)

## 結算瞬間的亮閃長度（tick）
const FLASH_TICKS := 6

var radius: float = 48.0
var start_tick: int = 0
var end_tick: int = 1
var world: Node2D = null

var _flash_age: int = 0


func _ready() -> void:
	add_to_group("fx")   # 測試模式統計特效數量用


func _draw() -> void:
	var clock: float = world.telegraph_clock()
	if clock < end_tick:
		# 前搖中：外框＋淡填充，內圈隨進度長大（充能感）
		var progress := clampf(
			(clock - start_tick) / maxf(1.0, float(end_tick - start_tick)), 0.0, 1.0
		)
		draw_circle(Vector2.ZERO, radius, Color(DANGER_COLOR, 0.18))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(DANGER_COLOR, 0.9), 2.0)
		draw_circle(Vector2.ZERO, radius * progress, Color(DANGER_COLOR, 0.35))
	else:
		# 結算瞬間：整圈亮閃後消失
		var alpha := 0.7 * (1.0 - float(_flash_age) / FLASH_TICKS)
		draw_circle(Vector2.ZERO, radius, Color(DANGER_COLOR, alpha))


func _physics_process(_delta: float) -> void:
	if world == null:
		queue_free()
		return
	if world.telegraph_clock() >= end_tick:
		_flash_age += 1
		if _flash_age > FLASH_TICKS:
			queue_free()
			return
	queue_redraw()

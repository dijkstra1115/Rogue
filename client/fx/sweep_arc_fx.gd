## 揮劍扇形的佔位視覺（純表現層，不參與任何判定）。
## 白色半透明扇形，10 tick 內淡出後自毀。
## 注意：這裡的生命週期用 tick 數只是圖方便統一；它是視覺，不是遊戲事件。
class_name SweepArcFx
extends Node2D

const LIFETIME_TICKS := 10

var aim: Vector2 = Vector2.RIGHT
var arc_deg: float = SwordSweep.ARC_DEG
var range_px: float = SwordSweep.RANGE

var _age: int = 0


func _draw() -> void:
	var points: PackedVector2Array = [Vector2.ZERO]
	var base_angle := aim.angle()
	var half := deg_to_rad(arc_deg) * 0.5
	const STEPS := 12
	for i in STEPS + 1:
		var angle := base_angle - half + deg_to_rad(arc_deg) * i / STEPS
		points.append(Vector2.from_angle(angle) * range_px)
	# 白色系佔位——品紅/橘紅保留給敵人危險區域（docs/05），玩家特效不可用
	draw_colored_polygon(points, Color(1.0, 1.0, 1.0, 0.35))


func _physics_process(_delta: float) -> void:
	_age += 1
	modulate.a = 1.0 - float(_age) / LIFETIME_TICKS
	if _age >= LIFETIME_TICKS:
		queue_free()

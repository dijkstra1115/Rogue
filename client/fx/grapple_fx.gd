## 抓鉤的佔位視覺：從隊友原位到落點的一條淡出線。純表現層。
class_name GrappleFx
extends Node2D

const LIFETIME_TICKS := 12

var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO

var _age: int = 0


func _draw() -> void:
	# 淺藍白色系——危險色（品紅/橘紅）保留給敵人
	draw_line(from_pos, to_pos, Color(0.7, 0.85, 1.0, 0.8), 3.0)
	draw_circle(to_pos, 6.0, Color(0.7, 0.85, 1.0, 0.8))


func _physics_process(_delta: float) -> void:
	_age += 1
	modulate.a = 1.0 - float(_age) / LIFETIME_TICKS
	if _age >= LIFETIME_TICKS:
		queue_free()

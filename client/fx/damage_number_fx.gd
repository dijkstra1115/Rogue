## 傷害數字（純表現層）：白色數字上飄淡出後自毀。
class_name DamageNumberFx
extends Node2D

const LIFETIME_TICKS := 40
const RISE_PER_TICK := 0.8

var amount: float = 0.0

var _age: int = 0
var _label: Label


func _ready() -> void:
	add_to_group("fx")   # 測試模式統計特效數量用
	_label = Label.new()
	_label.text = str(roundi(amount))
	_label.position = Vector2(-12.0, -36.0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	add_child(_label)


func _physics_process(_delta: float) -> void:
	_age += 1
	position.y -= RISE_PER_TICK
	if _age > LIFETIME_TICKS / 2:
		modulate.a = 1.0 - float(_age - LIFETIME_TICKS / 2) / (LIFETIME_TICKS / 2)
	if _age >= LIFETIME_TICKS:
		queue_free()

## 磨刀石（白）：傷害 +12%／層，線性堆疊。
## 純數值原型——無聊但必要，是後期爆炸的燃料（docs/03 原型 1）。
class_name Whetstone
extends Modifier


func _init() -> void:
	id = "whetstone"
	display_name = "磨刀石"
	rarity = "white"


func modify_stats(stats: Dictionary) -> void:
	stats.damage_mult = Stacking.linear(stats.damage_mult, 0.12, stack_count)

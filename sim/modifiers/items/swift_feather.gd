## 疾風羽（白）：攻速 +15%／層，線性堆疊。
## 純數值原型。攻速會縮短揮擊冷卻（Ability.mark_used 的縮放）。
class_name SwiftFeather
extends Modifier


func _init() -> void:
	id = "swift_feather"
	display_name = "疾風羽"
	rarity = "white"


func modify_stats(stats: Dictionary) -> void:
	stats.attack_speed = Stacking.linear(stats.attack_speed, 0.15, stack_count)

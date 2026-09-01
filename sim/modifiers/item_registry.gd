## 道具註冊表（M3）：id → 道具腳本。
## 新增道具 = 寫一個 Modifier 子類別 + 在這裡登記一行，其他什麼都不用改。
class_name ItemRegistry
extends RefCounted

const ITEMS := {
	"whetstone": preload("res://sim/modifiers/items/whetstone.gd"),
	"swift_feather": preload("res://sim/modifiers/items/swift_feather.gd"),
	"shattered_mirror": preload("res://sim/modifiers/items/shattered_mirror.gd"),
}


static func create(item_id: String, stacks: int = 1) -> Modifier:
	var modifier: Modifier = ITEMS[item_id].new()
	modifier.stack_count = stacks
	return modifier


static func all_ids() -> Array:
	return ITEMS.keys()

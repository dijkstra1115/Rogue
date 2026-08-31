## 一位玩家持有的全部道具（M3）。只存在於伺服器（權威）。
##
## 同 id 的道具合併堆疊（stack_count 累加）；分發事件時按 priority 排序。
class_name ModifierStack
extends RefCounted

## id -> Modifier 實例
var modifiers: Dictionary = {}

## priority 排序快取（堆疊變動時失效）
var _sorted_cache: Array[Modifier] = []
var _cache_dirty: bool = true


## 加入道具：已持有就疊層，否則收進來。
func add(modifier: Modifier) -> void:
	if modifiers.has(modifier.id):
		modifiers[modifier.id].stack_count += modifier.stack_count
	else:
		modifiers[modifier.id] = modifier
	_cache_dirty = true


func stack_count_of(item_id: String) -> int:
	if not modifiers.has(item_id):
		return 0
	return modifiers[item_id].stack_count


## 從基礎屬性算出最終屬性（純函式：不改 base，回傳新 Dictionary）。
func compute_stats(base: Dictionary) -> Dictionary:
	var stats := base.duplicate()
	for modifier in _sorted():
		modifier.modify_stats(stats)
	return stats


func dispatch_attack_start(ctx: Dictionary) -> void:
	for modifier in _sorted():
		modifier.on_attack_start(ctx)


func dispatch_hit(ctx: Dictionary) -> void:
	for modifier in _sorted():
		modifier.on_hit(ctx)


func dispatch_kill(ctx: Dictionary) -> void:
	for modifier in _sorted():
		modifier.on_kill(ctx)


func dispatch_take_damage(ctx: Dictionary) -> void:
	for modifier in _sorted():
		modifier.on_take_damage(ctx)


func _sorted() -> Array[Modifier]:
	if _cache_dirty:
		_sorted_cache.clear()
		for modifier: Modifier in modifiers.values():
			_sorted_cache.append(modifier)
		_sorted_cache.sort_custom(
			func(a: Modifier, b: Modifier) -> bool: return a.priority < b.priority
		)
		_cache_dirty = false
	return _sorted_cache

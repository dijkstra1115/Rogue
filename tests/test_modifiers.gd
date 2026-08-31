## M3 步驟 1 的 headless 測試：堆疊公式、ModifierStack、屬性計算、事件分發。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_modifiers.gd
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 10

var failed_count: int = 0
var check_count: int = 0


## 測試用道具：傷害 +12%/層（線性）
class TestDamageUp:
	extends Modifier
	func _init() -> void:
		id = "test_damage"
		display_name = "測試磨刀石"
	func modify_stats(stats: Dictionary) -> void:
		stats.damage_mult = Stacking.linear(stats.damage_mult, 0.12, stack_count)


## 測試用道具：命中傷害翻倍（priority 10，比加法晚跑）
class TestHitDouble:
	extends Modifier
	func _init() -> void:
		id = "test_double"
		priority = 10
	func on_hit(ctx: Dictionary) -> void:
		ctx.damage *= 2.0


## 測試用道具：命中傷害 +5（priority 0，先跑）
class TestHitPlus:
	extends Modifier
	func _init() -> void:
		id = "test_plus"
		priority = 0
	func on_hit(ctx: Dictionary) -> void:
		ctx.damage += 5.0


func _init() -> void:
	_test_stacking_formulas()
	_test_stack_merge()
	_test_compute_stats()
	_test_dispatch_priority()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: Modifier 測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## 線性無上限、遞減永遠到不了 1.0
func _test_stacking_formulas() -> void:
	_check(absf(Stacking.linear(1.0, 0.12, 3) - 1.36) < 0.001, "線性：1.0 + 0.12×3 = 1.36")
	_check(absf(Stacking.hyperbolic(0.25, 1) - 0.2) < 0.001, "遞減：k=0.25 單層 = 20%")
	_check(Stacking.hyperbolic(0.25, 1000) < 1.0, "遞減疊 1000 層仍 < 100%（守住遊戲）")
	_check(
		Stacking.hyperbolic(0.25, 10) > Stacking.hyperbolic(0.25, 5),
		"遞減仍然單調遞增（多疊有感）"
	)


## 同 id 合併堆疊，不同 id 各自存在
func _test_stack_merge() -> void:
	var stack := ModifierStack.new()
	stack.add(TestDamageUp.new())
	stack.add(TestDamageUp.new())
	stack.add(TestHitDouble.new())
	_check(stack.stack_count_of("test_damage") == 2, "同 id 合併成 2 層")
	_check(stack.modifiers.size() == 2, "不同 id 各自存在")


## 屬性計算：不改基礎值、堆疊生效
func _test_compute_stats() -> void:
	var stack := ModifierStack.new()
	var item := TestDamageUp.new()
	item.stack_count = 3
	stack.add(item)
	var base := {"damage_mult": 1.0, "max_hp": 100.0}
	var stats := stack.compute_stats(base)
	_check(absf(stats.damage_mult - 1.36) < 0.001, "3 層 +12% → damage_mult 1.36")
	_check(base.damage_mult == 1.0, "基礎值不被污染（純函式）")


## 事件分發按 priority：+5 先跑、×2 後跑 → (10+5)×2 = 30
func _test_dispatch_priority() -> void:
	var stack := ModifierStack.new()
	stack.add(TestHitDouble.new())   # priority 10
	stack.add(TestHitPlus.new())     # priority 0
	var ctx := {"damage": 10.0}
	stack.dispatch_hit(ctx)
	_check(ctx.damage == 30.0, "priority 順序正確：(10+5)×2 = 30")
	# 顛倒加入順序，結果必須一樣（順序由 priority 決定，不是加入順序）
	var stack2 := ModifierStack.new()
	stack2.add(TestHitPlus.new())
	stack2.add(TestHitDouble.new())
	var ctx2 := {"damage": 10.0}
	stack2.dispatch_hit(ctx2)
	_check(ctx2.damage == 30.0, "加入順序不影響結果")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

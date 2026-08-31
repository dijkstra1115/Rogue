## M2 步驟 1 的 headless 測試：技能冷卻與扇形命中幾何。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_abilities.gd
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 13

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_cooldown()
	_test_attack_speed_scaling()
	_test_sector_geometry()
	_test_grapple_targeting()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 技能測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## 冷卻：用了之後要等滿 base_cooldown_ticks 才能再用
func _test_cooldown() -> void:
	var ability := SwordSweep.new()
	_check(ability.is_ready(1), "初始狀態可使用")
	ability.mark_used(100, 1.0)
	_check(not ability.is_ready(100 + ability.base_cooldown_ticks - 1), "冷卻中不可使用")
	_check(ability.is_ready(100 + ability.base_cooldown_ticks), "冷卻結束恰好可使用")


## 攻速 2.0 → 冷卻減半；衝刺類（不縮放）不受攻速影響
func _test_attack_speed_scaling() -> void:
	var sweep := SwordSweep.new()
	sweep.mark_used(0, 2.0)
	_check(sweep.is_ready(sweep.base_cooldown_ticks / 2), "攻速 2.0 冷卻減半")

	var utility_ability := Ability.new()   # 基底預設不隨攻速縮放
	utility_ability.base_cooldown_ticks = 60
	utility_ability.mark_used(0, 4.0)
	_check(not utility_ability.is_ready(30) and utility_ability.is_ready(60), "非攻擊技能冷卻不受攻速影響")


## 扇形命中：前方近距離命中、背後不中、超距不中、邊界角內中、原點重疊必中
func _test_sector_geometry() -> void:
	var origin := Vector2.ZERO
	var aim := Vector2.RIGHT
	_check(SwordSweep.is_in_sector(origin, aim, Vector2(50, 0), 90.0, 100.0), "正前方命中")
	_check(not SwordSweep.is_in_sector(origin, aim, Vector2(-50, 0), 90.0, 100.0), "背後不中")
	_check(not SwordSweep.is_in_sector(origin, aim, Vector2(120, 0), 90.0, 100.0), "超出半徑不中")
	# 100 度扇形 → 半角 50 度；45 度方向應命中
	var diagonal := Vector2.from_angle(deg_to_rad(45.0)) * 60.0
	_check(SwordSweep.is_in_sector(origin, aim, diagonal, 90.0, 100.0), "45 度（半角 50 度內）命中")
	_check(SwordSweep.is_in_sector(origin, aim, Vector2.ZERO, 90.0, 100.0), "原點重疊必中")


## 抓鉤選目標：挑最近的隊友、排除自己、範圍外沒目標
func _test_grapple_targeting() -> void:
	var players := {
		1: {"pos": Vector2(100.0, 100.0)},   # 施放者
		2: {"pos": Vector2(300.0, 100.0)},   # 距離 200
		3: {"pos": Vector2(150.0, 100.0)},   # 距離 50（最近）
	}
	_check(Grapple.find_nearest_ally(players, 1, 600.0) == 3, "挑最近的隊友")
	_check(Grapple.find_nearest_ally({1: {"pos": Vector2.ZERO}}, 1, 600.0) == -1, "只有自己時沒有目標")
	_check(Grapple.find_nearest_ally(players, 1, 30.0) == -1, "全部超出範圍時沒有目標")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

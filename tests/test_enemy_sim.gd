## M2 步驟 3 的 headless 測試：敵人追擊與分離。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_sim.gd
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 8

const BOUNDS := Rect2(40, 40, 1200, 640)

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_chase()
	_test_stop_range()
	_test_separation()
	_test_players_hit()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 敵人模擬測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## 追擊：每 tick 朝目標前進 speed/60，方向正確
func _test_chase() -> void:
	var pos := Vector2(100.0, 100.0)
	var target := Vector2(500.0, 100.0)
	var new_pos := EnemySim.simulate_chase(pos, target, 140.0, 30.0, BOUNDS)
	var expected := Vector2(100.0 + 140.0 / 60.0, 100.0)
	_check(new_pos.distance_to(expected) < 0.01, "每 tick 前進 speed/60 像素、方向正確")

	# 追 600 tick（10 秒）必定到達停止距離邊上
	for i in 600:
		pos = EnemySim.simulate_chase(pos, target, 140.0, 30.0, BOUNDS)
	_check(absf(pos.distance_to(target) - 30.0) < 0.01, "最終停在停止距離邊上，不會衝過頭")


## 已在停止距離內：完全不動（不抖）
func _test_stop_range() -> void:
	var pos := Vector2(480.0, 100.0)
	var target := Vector2(500.0, 100.0)   # 距離 20 < 30
	var new_pos := EnemySim.simulate_chase(pos, target, 140.0, 30.0, BOUNDS)
	_check(new_pos == pos, "停止距離內不移動")


## 分離：重疊的兩隻被推開到最小距離；推不出邊界
func _test_separation() -> void:
	var states := {
		1: {"pos": Vector2(300.0, 300.0)},
		2: {"pos": Vector2(302.0, 300.0)},
	}
	EnemySim.apply_separation(states, 26.0, BOUNDS)
	var dist: float = states[1].pos.distance_to(states[2].pos)
	_check(absf(dist - 26.0) < 0.01, "被推開到恰好最小距離")

	# 完全重疊也能分開（不除以零）
	var overlap := {
		1: {"pos": Vector2(300.0, 300.0)},
		2: {"pos": Vector2(300.0, 300.0)},
	}
	EnemySim.apply_separation(overlap, 26.0, BOUNDS)
	_check(overlap[1].pos.distance_to(overlap[2].pos) > 25.0, "完全重疊也能分開")

	# 貼著牆分離不會被推出界（敵人半寬 14 → x 最小 54）
	var corner := {
		1: {"pos": Vector2(54.0, 300.0)},
		2: {"pos": Vector2(55.0, 300.0)},
	}
	EnemySim.apply_separation(corner, 26.0, BOUNDS)
	var min_x: float = minf(corner[1].pos.x, corner[2].pos.x)
	_check(min_x >= 54.0, "分離不會推出邊界")


## 攻擊結算：圈內命中、圈外不中
func _test_players_hit() -> void:
	var players := {
		1: {"pos": Vector2(300.0, 300.0)},   # 距中心 30 → 中
		2: {"pos": Vector2(400.0, 300.0)},   # 距中心 70 → 不中
	}
	var hit := EnemySim.players_hit(players, Vector2(330.0, 300.0), 48.0)
	_check(hit == [1], "半徑內的玩家被命中")
	_check(EnemySim.players_hit(players, Vector2(1000.0, 1000.0), 48.0).is_empty(), "沒人站圈裡就沒人受傷")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

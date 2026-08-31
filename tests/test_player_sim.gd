## 步驟 2 的 headless 測試：InputFrame 序列化 + 移動模擬的正確性與確定性。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_player_sim.gd
extends SceneTree

const BOUNDS := Rect2(40, 40, 1200, 640)
const SPEED := 320.0

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 6

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_input_frame_roundtrip()
	_test_movement_speed()
	_test_diagonal_not_faster()
	_test_wall_clamp()
	_test_determinism()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 玩家模擬測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## to_dict / from_dict 往返後每個欄位都要一致
func _test_input_frame_roundtrip() -> void:
	var original := InputFrame.new()
	original.tick = 42
	original.move = Vector2(0.5, -0.25)
	original.aim = Vector2.DOWN
	original.primary = true
	original.interact = true
	var restored := InputFrame.from_dict(original.to_dict())
	_check(
		restored.tick == 42
			and restored.move == original.move
			and restored.aim == original.aim
			and restored.primary
			and restored.interact
			and not restored.secondary
			and not restored.utility
			and not restored.special,
		"InputFrame 序列化往返一致"
	)
	# 空 Dictionary（壞封包）不炸，回安全預設值
	var fallback := InputFrame.from_dict({})
	_check(fallback.tick == 0 and fallback.move == Vector2.ZERO, "空 Dictionary 回安全預設值")


## 全速向右跑 60 tick（一秒）應恰好前進 move_speed 像素
func _test_movement_speed() -> void:
	var frame := InputFrame.new()
	frame.move = Vector2.RIGHT
	var pos := Vector2(200.0, 200.0)
	for i in 60:
		pos = PlayerSim.simulate_movement(pos, frame, SPEED, BOUNDS)
	_check(pos.distance_to(Vector2(200.0 + SPEED, 200.0)) < 0.01, "全速 60 tick 前進 move_speed 像素")


## 斜向（1,1）要被正規化，60 tick 後總位移仍是 move_speed，不會 ×1.414
func _test_diagonal_not_faster() -> void:
	var frame := InputFrame.new()
	frame.move = Vector2(1.0, 1.0)
	var start := Vector2(200.0, 200.0)
	var pos := start
	for i in 60:
		pos = PlayerSim.simulate_movement(pos, frame, SPEED, BOUNDS)
	_check(absf(pos.distance_to(start) - SPEED) < 0.01, "斜走不比直走快")


## 一直往左推，最後要停在牆邊（bounds 左緣 + 半個方塊），不會穿出去
func _test_wall_clamp() -> void:
	var frame := InputFrame.new()
	frame.move = Vector2.LEFT
	var pos := Vector2(200.0, 200.0)
	for i in 600:
		pos = PlayerSim.simulate_movement(pos, frame, SPEED, BOUNDS)
	var expected_x := BOUNDS.position.x + PlayerSim.PLAYER_HALF_SIZE
	_check(pos.x == expected_x and pos.y == 200.0, "夾牆：停在左緣 x=%.0f" % expected_x)


## 同樣的輸入序列跑兩次，逐 tick 結果完全相同（預測/和解的前提）
func _test_determinism() -> void:
	var frames: Array[InputFrame] = []
	for i in 120:
		var f := InputFrame.new()
		f.tick = i
		# 用 tick 編號做出變化的（但可重現的）輸入
		f.move = Vector2(sin(i * 0.1), cos(i * 0.13))
		frames.append(f)

	var run_a := _run_sim(frames)
	var run_b := _run_sim(frames)
	_check(run_a == run_b, "同輸入兩次模擬結果逐 tick 相同（確定性）")


func _run_sim(frames: Array[InputFrame]) -> Array[Vector2]:
	var pos := Vector2(600.0, 300.0)
	var history: Array[Vector2] = []
	for frame in frames:
		pos = PlayerSim.simulate_movement(pos, frame, SPEED, BOUNDS)
		history.append(pos)
	return history


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

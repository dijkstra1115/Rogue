## headless 測試：InputFrame 序列化 + 移動/衝刺模擬的正確性與確定性。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_player_sim.gd
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 10

const BOUNDS := Rect2(40, 40, 1200, 640)
const SPEED := 320.0

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_input_frame_roundtrip()
	_test_movement_speed()
	_test_diagonal_not_faster()
	_test_wall_clamp()
	_test_dash()
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


func _make_state(pos: Vector2) -> Dictionary:
	var state: Dictionary = {}
	PlayerSim.init_movement(state, pos, SPEED)
	return state


func _make_frame(tick: int, move: Vector2, utility: bool = false) -> InputFrame:
	var frame := InputFrame.new()
	frame.tick = tick
	frame.move = move
	frame.utility = utility
	return frame


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
	var fallback := InputFrame.from_dict({})
	_check(fallback.tick == 0 and fallback.move == Vector2.ZERO, "空 Dictionary 回安全預設值")


## 全速向右跑 60 tick（一秒）應恰好前進 move_speed 像素
func _test_movement_speed() -> void:
	var state := _make_state(Vector2(200.0, 200.0))
	for i in 60:
		PlayerSim.step(state, _make_frame(i + 1, Vector2.RIGHT), BOUNDS)
	_check(state.pos.distance_to(Vector2(200.0 + SPEED, 200.0)) < 0.01, "全速 60 tick 前進 move_speed 像素")


## 斜向（1,1）要被正規化，總位移仍是 move_speed
func _test_diagonal_not_faster() -> void:
	var state := _make_state(Vector2(200.0, 200.0))
	for i in 60:
		PlayerSim.step(state, _make_frame(i + 1, Vector2(1.0, 1.0)), BOUNDS)
	_check(absf(state.pos.distance_to(Vector2(200.0, 200.0)) - SPEED) < 0.01, "斜走不比直走快")


## 一直往左推，停在牆邊不穿出
func _test_wall_clamp() -> void:
	var state := _make_state(Vector2(200.0, 200.0))
	for i in 600:
		PlayerSim.step(state, _make_frame(i + 1, Vector2.LEFT), BOUNDS)
	var expected_x := BOUNDS.position.x + PlayerSim.PLAYER_HALF_SIZE
	_check(state.pos.x == expected_x and state.pos.y == 200.0, "夾牆：停在左緣 x=%.0f" % expected_x)


## 衝刺：位移正確、按住不重複觸發、冷卻生效
func _test_dash() -> void:
	# 按下 utility 起衝：DASH_TICKS 個 tick 共位移 DASH_SPEED/60*DASH_TICKS
	var state := _make_state(Vector2(200.0, 200.0))
	for i in PlayerSim.DASH_TICKS:
		PlayerSim.step(state, _make_frame(i + 1, Vector2.RIGHT, true), BOUNDS)
	var dash_distance := PlayerSim.DASH_SPEED / 60.0 * PlayerSim.DASH_TICKS
	_check(
		absf(state.pos.x - (200.0 + dash_distance)) < 0.01,
		"衝刺 %d tick 位移 %.0f 像素" % [PlayerSim.DASH_TICKS, dash_distance]
	)

	# 一直按住：衝刺結束後回到普通速度（上升沿才觸發，不會連環衝）
	var held := _make_state(Vector2(200.0, 200.0))
	for i in 60:
		PlayerSim.step(held, _make_frame(i + 1, Vector2.RIGHT, true), BOUNDS)
	var expected := 200.0 + dash_distance + (60 - PlayerSim.DASH_TICKS) * SPEED / 60.0
	_check(absf(held.pos.x - expected) < 0.01, "按住不放只衝一次，之後恢復普通速度")

	# 放開再按（冷卻中）：不觸發第二次衝刺
	var cd := _make_state(Vector2(200.0, 200.0))
	PlayerSim.step(cd, _make_frame(1, Vector2.RIGHT, true), BOUNDS)
	for i in range(2, PlayerSim.DASH_TICKS + 1):
		PlayerSim.step(cd, _make_frame(i, Vector2.RIGHT, false), BOUNDS)
	var pos_after_dash: Vector2 = cd.pos
	PlayerSim.step(cd, _make_frame(PlayerSim.DASH_TICKS + 1, Vector2.ZERO, true), BOUNDS)
	_check(cd.pos == pos_after_dash, "冷卻中再按不觸發（原地不動）")

	# 冷卻結束後（放開再按）能再衝
	var again := _make_state(Vector2(300.0, 300.0))
	PlayerSim.step(again, _make_frame(1, Vector2.RIGHT, true), BOUNDS)
	for i in range(2, PlayerSim.DASH_COOLDOWN_TICKS + 2):
		PlayerSim.step(again, _make_frame(i, Vector2.ZERO, false), BOUNDS)
	var before: Vector2 = again.pos
	PlayerSim.step(
		again,
		_make_frame(PlayerSim.DASH_COOLDOWN_TICKS + 2, Vector2.RIGHT, true),
		BOUNDS
	)
	_check(again.pos.x - before.x > SPEED / 60.0 + 0.01, "冷卻結束後能再次衝刺")


## 同樣的輸入序列（含衝刺）跑兩次，逐 tick 結果完全相同
func _test_determinism() -> void:
	var frames: Array[InputFrame] = []
	for i in 200:
		frames.append(_make_frame(
			i + 1,
			Vector2(sin(i * 0.1), cos(i * 0.13)),
			i % 70 < 2   # 週期性衝刺
		))
	var run_a := _run_sim(frames)
	var run_b := _run_sim(frames)
	_check(run_a == run_b, "同輸入（含衝刺）兩次模擬結果逐 tick 相同（確定性）")


func _run_sim(frames: Array[InputFrame]) -> Array[Vector2]:
	var state := _make_state(Vector2(600.0, 300.0))
	var history: Array[Vector2] = []
	for frame in frames:
		PlayerSim.step(state, frame, BOUNDS)
		history.append(state.pos)
	return history


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

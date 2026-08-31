## 步驟 4 的 headless 測試：客戶端預測與和解（ClientPrediction）。
##
## 在同一個程序裡模擬「客戶端預測」與「伺服器權威模擬」兩條時間線，
## 驗證：預測正確時零修正、預測錯誤時回滾重放收斂、視覺偏移會衰減。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_prediction.gd
extends SceneTree

const BOUNDS := Rect2(40, 40, 1200, 640)
const SPEED := 320.0
const START := Vector2(600.0, 300.0)

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 11

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_perfect_network_zero_corrections()
	_test_server_jitter_zero_corrections()
	_test_mispredict_replay_converges()
	_test_pending_pruned_after_ack()
	_test_visual_error_decays()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 預測/和解測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


func _make_frame(tick: int) -> InputFrame:
	var frame := InputFrame.new()
	frame.tick = tick
	frame.move = Vector2(sin(tick * 0.05), cos(tick * 0.05))
	return frame


## 理想網路：伺服器和客戶端跑同樣的輸入序列，每 3 tick 回報一次狀態。
## 預測應該永遠正確——修正次數必須是 0。
func _test_perfect_network_zero_corrections() -> void:
	var prediction := ClientPrediction.new()
	var client_pos := START
	var server_pos := START
	for tick in range(1, 121):
		var frame := _make_frame(tick)
		client_pos = prediction.predict(client_pos, frame, SPEED, BOUNDS)
		# 伺服器晚一點但照同樣順序消化同一筆輸入
		server_pos = PlayerSim.simulate_movement(server_pos, frame, SPEED, BOUNDS)
		if tick % 3 == 0:
			client_pos = prediction.reconcile(client_pos, server_pos, tick, SPEED, BOUNDS)
	_check(prediction.correction_count == 0, "理想網路下零和解修正")
	_check(prediction.pending_inputs.is_empty(), "確認過的輸入都被清掉")
	_check(client_pos.distance_to(server_pos) < 0.01, "客戶端與伺服器位置一致")


## 網路抖動重現（實測踩過的雷）：伺服器有些 tick 收不到輸入。
## 正確行為是「凍結一格、之後照序補吃」，每筆輸入只套用一次——
## 這樣客戶端預測依然全對，修正次數必須是 0。
## （如果伺服器改成「沿用上一筆再模擬」，這個測試會炸——那正是 bug。）
func _test_server_jitter_zero_corrections() -> void:
	var prediction := ClientPrediction.new()
	var client_pos := START
	var server_pos := START
	var in_flight: Array[InputFrame] = []   # 模擬網路中的輸入佇列
	var server_ack := -1
	var max_backlog := 0
	for tick in range(1, 181):
		var frame := _make_frame(tick)
		client_pos = prediction.predict(client_pos, frame, SPEED, BOUNDS)
		in_flight.append(frame)
		# 伺服器：每 7 tick「晚到一拍」什麼都收不到；
		# 其餘 tick 照序吃一筆，積壓超過水位（2）就多吃幾筆排水（同 game_world 政策）
		if tick % 7 != 0:
			var applied := 0
			while applied < 3 and not in_flight.is_empty():
				if applied > 0 and in_flight.size() <= 2:
					break
				var served: InputFrame = in_flight.pop_front()
				server_pos = PlayerSim.simulate_movement(server_pos, served, SPEED, BOUNDS)
				server_ack = served.tick
				applied += 1
		max_backlog = maxi(max_backlog, in_flight.size())
		# 每 3 tick 回報一次狀態
		if tick % 3 == 0 and server_ack >= 0:
			client_pos = prediction.reconcile(client_pos, server_pos, server_ack, SPEED, BOUNDS)
	_check(prediction.correction_count == 0, "伺服器抖動（凍結+排水）下零和解修正")
	_check(max_backlog <= 4, "積壓有界（最大 %d 筆），不隨時間成長" % max_backlog)


## 伺服器回報一個偏掉的位置：要修正一次，且重放後的位置
## ＝「從伺服器位置重新模擬所有未確認輸入」的結果。
func _test_mispredict_replay_converges() -> void:
	var prediction := ClientPrediction.new()
	var client_pos := START
	for tick in range(1, 11):
		client_pos = prediction.predict(client_pos, _make_frame(tick), SPEED, BOUNDS)

	# 伺服器說：你的 tick 6 之後其實在別的地方（偏 10px）
	var server_pos: Vector2 = prediction.predicted_history[6] + Vector2(10.0, 0.0)
	var reconciled := prediction.reconcile(client_pos, server_pos, 6, SPEED, BOUNDS)

	# 手動從伺服器位置重放 tick 7..10，結果要跟和解一致
	var expected := server_pos
	for tick in range(7, 11):
		expected = PlayerSim.simulate_movement(expected, _make_frame(tick), SPEED, BOUNDS)
	_check(prediction.correction_count == 1, "預測錯誤修正一次")
	_check(reconciled.distance_to(expected) < 0.01, "重放結果＝從伺服器位置重新模擬")
	_check(prediction.visual_error != Vector2.ZERO, "修正後有視覺偏移（平滑用）")


## 和解後，ack 以前的輸入與歷史都要被清掉
func _test_pending_pruned_after_ack() -> void:
	var prediction := ClientPrediction.new()
	var pos := START
	for tick in range(1, 21):
		pos = prediction.predict(pos, _make_frame(tick), SPEED, BOUNDS)
	prediction.reconcile(pos, prediction.predicted_history[15], 15, SPEED, BOUNDS)
	var all_after := true
	for frame in prediction.pending_inputs:
		if frame.tick <= 15:
			all_after = false
	_check(all_after and prediction.pending_inputs.size() == 5, "ack 之前的輸入被清掉，留 5 筆")
	_check(not prediction.predicted_history.has(15), "ack 之前的歷史被清掉")


## 視覺偏移每 tick 衰減，最後歸零
func _test_visual_error_decays() -> void:
	var prediction := ClientPrediction.new()
	prediction.visual_error = Vector2(20.0, 0.0)
	for i in 30:
		prediction.decay_visual_error()
	_check(prediction.visual_error == Vector2.ZERO, "視覺偏移 30 tick 內歸零")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

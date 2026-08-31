## 步驟 5 的 headless 測試：遠端插值緩衝（RemoteInterpolation）。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_interpolation.gd
extends SceneTree

## 預期執行的檢查總數。若腳本中途出錯，檢查數會不足——
## 沒有這個守門，「一項檢查都沒跑」會被誤判成全過（踩過的雷）。
const EXPECTED_CHECKS := 9

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_basic_lerp()
	_test_edges()
	_test_gap_lerp()
	_test_out_of_order_ignored()
	_test_buffer_cap()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 插值測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## 連續狀態之間的內插要精確
func _test_basic_lerp() -> void:
	var interp := RemoteInterpolation.new()
	for tick in range(10, 21):
		interp.push_state(tick, Vector2(tick * 10.0, 0.0))
	var mid: Vector2 = interp.sample(15.5)
	_check(mid.distance_to(Vector2(155.0, 0.0)) < 0.01, "兩筆狀態間內插精確（15.5 → x=155）")


## 邊界行為：空緩衝 null、早於最舊用最舊、晚於最新凍結在最新
func _test_edges() -> void:
	var empty := RemoteInterpolation.new()
	_check(empty.sample(100.0) == null, "空緩衝回傳 null")

	var interp := RemoteInterpolation.new()
	interp.push_state(10, Vector2(100.0, 0.0))
	interp.push_state(11, Vector2(110.0, 0.0))
	_check(interp.sample(5.0) == Vector2(100.0, 0.0), "早於最舊 → 用最舊")
	_check(interp.sample(99.0) == Vector2(110.0, 0.0), "緩衝乾了 → 凍結在最新（不外推）")


## 封包丟失造成的空隙要自然補平
func _test_gap_lerp() -> void:
	var interp := RemoteInterpolation.new()
	interp.push_state(10, Vector2.ZERO)
	interp.push_state(20, Vector2(100.0, 0.0))   # 中間 9 筆全丟了
	var mid: Vector2 = interp.sample(15.0)
	_check(mid.distance_to(Vector2(50.0, 0.0)) < 0.01, "跨空隙內插（丟包自然補平）")


## 亂序／重複的過期封包要被忽略
func _test_out_of_order_ignored() -> void:
	var interp := RemoteInterpolation.new()
	interp.push_state(10, Vector2(100.0, 0.0))
	interp.push_state(12, Vector2(120.0, 0.0))
	interp.push_state(11, Vector2(999.0, 999.0))   # 過期，應被忽略
	interp.push_state(12, Vector2(888.0, 888.0))   # 重複，應被忽略
	_check(interp.size() == 2, "亂序/重複封包被忽略")
	var mid: Vector2 = interp.sample(11.0)
	_check(mid.distance_to(Vector2(110.0, 0.0)) < 0.01, "插值不受過期封包污染")


## 緩衝有上限，舊狀態被淘汰
func _test_buffer_cap() -> void:
	var interp := RemoteInterpolation.new()
	for tick in range(1, 101):
		interp.push_state(tick, Vector2(tick * 1.0, 0.0))
	_check(interp.size() == RemoteInterpolation.BUFFER_CAP, "緩衝維持上限 %d 筆" % RemoteInterpolation.BUFFER_CAP)
	_check(interp.states[0].t == 101 - RemoteInterpolation.BUFFER_CAP, "淘汰的是最舊的")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

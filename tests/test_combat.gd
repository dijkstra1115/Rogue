## M2 步驟 2 的 headless 測試：傷害事件結構與套用。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_combat.gd
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 7

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_test_event_structure()
	_test_damage_application()

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 戰鬥測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


## 傷害事件必須帶 M3 需要的欄位（觸發係數、遞迴深度）與 tick 時間戳
func _test_event_structure() -> void:
	var event := Combat.make_damage_event(1, 42, 10.0, 600)
	_check(event.trigger_coefficient == 1.0, "事件帶觸發係數（預設 1.0）")
	_check(event.recursion_depth == 0, "事件帶遞迴深度（預設 0）")
	_check(event.tick == 600 and event.source_peer == 1 and event.target == 42, "來源/目標/tick 正確")


## 套用傷害：扣血、致死回報、不打穿 0、死人不重複結算
func _test_damage_application() -> void:
	var enemy := {"hp": 30.0, "max_hp": 30.0}
	var event := Combat.make_damage_event(1, 1, 10.0, 0)
	_check(not Combat.apply_damage_to(enemy, event) and enemy.hp == 20.0, "扣血且未死")
	var overkill := Combat.make_damage_event(1, 1, 999.0, 0)
	_check(Combat.apply_damage_to(enemy, overkill), "致死回報 true")
	_check(enemy.hp == 0.0, "血量不會低於 0")
	_check(not Combat.apply_damage_to(enemy, event), "已死亡不重複結算")


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

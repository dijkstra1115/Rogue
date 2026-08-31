## 步驟 1 的 headless 測試：驗證專案基本設定。
##
## 執行方式（在專案根目錄）：
##   .\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_project_setup.gd
##
## 全部通過印出 PASS 並以 exit code 0 結束；任何失敗印出 FAIL 並以 1 結束。
extends SceneTree

## 預期執行的檢查總數（守門：腳本中途出錯時檢查數不足，不可誤判成全過）
const EXPECTED_CHECKS := 6

var failed_count: int = 0
var check_count: int = 0


func _init() -> void:
	_check(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 60,
		"physics tick 必須是 60Hz（核心原則 1）"
	)
	_check(
		ProjectSettings.get_setting("application/run/main_scene") == "res://main.tscn",
		"主場景設定為 main.tscn"
	)
	_check(ResourceLoader.exists("res://scenes/arena.tscn"), "arena.tscn 存在")
	_check(ResourceLoader.exists("res://sim/game_world.gd"), "game_world.gd 存在")

	# 場景要能實際載入（抓出 tscn 語法錯誤或壞掉的節點引用）
	var main_scene: PackedScene = load("res://main.tscn")
	_check(main_scene != null and main_scene.can_instantiate(), "main.tscn 能載入並實例化")
	var arena_scene: PackedScene = load("res://scenes/arena.tscn")
	_check(arena_scene != null and arena_scene.can_instantiate(), "arena.tscn 能載入並實例化")

	if check_count != EXPECTED_CHECKS:
		print("FAIL: 只執行了 %d/%d 項檢查（腳本中途出錯？）" % [check_count, EXPECTED_CHECKS])
		quit(1)
	elif failed_count == 0:
		print("PASS: 專案設定測試全部通過")
		quit(0)
	else:
		print("FAIL: %d 項檢查失敗" % failed_count)
		quit(1)


func _check(ok: bool, what: String) -> void:
	check_count += 1
	if ok:
		print("  ok - %s" % what)
	else:
		print("  FAILED - %s" % what)
		failed_count += 1

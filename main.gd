## 遊戲入口（main.tscn 的根節點）。
##
## 職責只有一件事：決定用哪種模式啟動——
##   1. 專用伺服器（匯出時帶 dedicated_server feature，或命令列帶 --server）
##   2. 一般客戶端（顯示 Host / Join 主選單）
##
## 核心原則 5（雙模式）的分岔點就在這裡，之後不會再有第二個地方判斷。
extends Control

## 命令列參數解析結果（放在 `--` 之後的參數，例如：godot --path . -- --join 1.2.3.4）
var wants_server: bool = false
var join_ip: String = ""

@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_parse_user_args()

	# 把模式寫進 Session（static），讓之後的場景不必重複判斷
	Session.is_dedicated_server = OS.has_feature("dedicated_server") or wants_server
	Session.join_ip = join_ip

	# 分岔：專用伺服器模式（headless，不顯示選單、不生成本地玩家）
	if Session.is_dedicated_server:
		_start_dedicated_server()
		return

	# 一般客戶端模式：接上選單按鈕
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)

	# 客戶端的連線結果（一次性，換場景前有效）
	NetworkManager.instance.connected_ok.connect(_on_connected)
	NetworkManager.instance.connect_failed.connect(_on_connect_failed)

	# 帶 --join <ip> 啟動時，自動連線（本機多開測試方便）
	if join_ip != "":
		%IPInput.text = join_ip
		_on_join_pressed()


## 讀取 `--` 之後的使用者參數。
## Godot 慣例：`--` 之前是引擎自己的參數，之後才是給遊戲的。
func _parse_user_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	wants_server = "--server" in args
	var join_index: int = args.find("--join")
	if join_index != -1 and join_index + 1 < args.size():
		join_ip = args[join_index + 1]
	var quit_index: int = args.find("--quit-after-ticks")
	if quit_index != -1 and quit_index + 1 < args.size():
		Session.quit_after_ticks = int(args[quit_index + 1])


## 專用伺服器：開 ENet 伺服器後直接進場景跑模擬。
func _start_dedicated_server() -> void:
	var err := NetworkManager.instance.host_game()
	if err != OK:
		push_error("[server] 伺服器啟動失敗：%s" % error_string(err))
		get_tree().quit(1)
		return
	print("[server] 以專用伺服器模式啟動")
	# _ready 期間不能直接換場景，要延後到這一幀結束
	get_tree().change_scene_to_file.call_deferred("res://scenes/arena.tscn")


func _on_host_pressed() -> void:
	var err := NetworkManager.instance.host_game()
	if err != OK:
		status_label.text = "開伺服器失敗：%s（port 被佔用？）" % error_string(err)
		return
	get_tree().change_scene_to_file("res://scenes/arena.tscn")


func _on_join_pressed() -> void:
	var ip: String = %IPInput.text.strip_edges()
	if ip == "":
		status_label.text = "請先輸入 IP"
		return
	var err := NetworkManager.instance.join_game(ip)
	if err != OK:
		status_label.text = "無法發起連線：%s" % error_string(err)
		return
	status_label.text = "連線中：%s ..." % ip
	_set_buttons_enabled(false)


func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/arena.tscn")


func _on_connect_failed() -> void:
	# 自動 join（--join 參數，headless 測試）失敗時直接結束，不要卡在選單
	if join_ip != "":
		push_error("[client] 自動連線 %s 失敗，結束" % join_ip)
		get_tree().quit(1)
		return
	status_label.text = "連線失敗（IP 對嗎？對方開 Host 了嗎？）"
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	%HostButton.disabled = not enabled
	%JoinButton.disabled = not enabled

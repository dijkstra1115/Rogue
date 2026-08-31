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

	# 分岔：專用伺服器模式（headless，不顯示選單、不生成本地玩家）
	if OS.has_feature("dedicated_server") or wants_server:
		_start_dedicated_server()
		return

	# 一般客戶端模式：接上選單按鈕
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)

	# 帶 --join <ip> 啟動時，先顯示出來（實際連線功能在步驟 3 實作）
	if join_ip != "":
		%IPInput.text = join_ip
		status_label.text = "偵測到 --join %s（連線功能在步驟 3 實作）" % join_ip


## 讀取 `--` 之後的使用者參數。
## Godot 慣例：`--` 之前是引擎自己的參數，之後才是給遊戲的。
func _parse_user_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	wants_server = "--server" in args
	var join_index: int = args.find("--join")
	if join_index != -1 and join_index + 1 < args.size():
		join_ip = args[join_index + 1]


## 專用伺服器：直接進入場景開始跑 tick。
## 網路層（開 port、收輸入）在步驟 3 加入；現在先確保 headless 能安全啟動。
func _start_dedicated_server() -> void:
	print("[server] 以專用伺服器模式啟動（網路層將於步驟 3 加入）")
	# _ready 期間不能直接換場景，要延後到這一幀結束
	get_tree().change_scene_to_file.call_deferred("res://scenes/arena.tscn")


func _on_host_pressed() -> void:
	# 步驟 3 起這裡會先建立 ENet 伺服器；現在先單機進場，驗證 tick 系統
	get_tree().change_scene_to_file("res://scenes/arena.tscn")


func _on_join_pressed() -> void:
	status_label.text = "Join 功能在步驟 3（ENet 連線）實作，目前只有 Host 能進場"

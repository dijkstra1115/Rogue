## 世界模擬（arena.tscn 的根節點）——模擬層的核心。
##
## 核心原則 1（固定 tick）的實作位置：
##   - 所有遊戲邏輯都在 _physics_process（60Hz）裡推進
##   - 時間單位一律用 tick 編號，絕不用秒數或 delta
##   - _process 只做視覺呈現（插值、UI），不碰遊戲邏輯
##
## 之後的步驟會在這裡加入：玩家 Dictionary[peer_id]、輸入消化、狀態廣播。
extends Node2D

## 目前的 tick 編號。開場為 0，每個 physics frame +1。
var current_tick: int = 0

@onready var tick_label: Label = %TickLabel


func _physics_process(_delta: float) -> void:
	current_tick += 1
	_simulate_tick(current_tick)


## 每 tick 的模擬入口。步驟 2 起：消化 InputFrame、移動玩家。
func _simulate_tick(_tick: int) -> void:
	pass


## 視覺更新（非邏輯）。之後會擴充成完整的除錯疊層（步驟 3）。
func _process(_delta: float) -> void:
	tick_label.text = "tick: %d" % current_tick

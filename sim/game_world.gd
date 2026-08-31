## 世界模擬（arena.tscn 的根節點）——模擬層的核心。
##
## 核心原則 1（固定 tick）的實作位置：
##   - 所有遊戲邏輯都在 _physics_process（60Hz）裡推進
##   - 時間單位一律用 tick 編號，絕不用秒數或 delta
##   - _process 只做視覺呈現（UI、之後的插值），不碰遊戲邏輯
##
## 玩家一律放在以 peer_id 為 key 的 Dictionary（核心原則 4）。
## 步驟 2 只有本機一位玩家（peer_id = 1）；步驟 3 起遠端玩家會加進同一個 Dictionary。
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")

## ENet 慣例：伺服器（房主）的 peer_id 固定是 1
const HOST_PEER_ID := 1

## 可活動範圍（地板的矩形）。M4 做房間系統時改由房間提供。
const ARENA_BOUNDS := Rect2(40, 40, 1200, 640)

## 預設移動速度（像素/秒）。這是「初始值」，放進每位玩家的狀態裡，
## M3 的 modifier 會動態改寫個別玩家的屬性，所以不能當常數用。
const DEFAULT_MOVE_SPEED := 320.0

## 目前的 tick 編號。開場為 0，每個 physics frame +1。
var current_tick: int = 0

## peer_id -> 模擬狀態（pos、move_speed...）。模擬層只碰這個，不碰節點。
var player_states: Dictionary = {}

## peer_id -> 場景節點（表現層）。位置永遠是從模擬狀態抄過去的。
var player_nodes: Dictionary = {}

@onready var tick_label: Label = %TickLabel


func _ready() -> void:
	# 專用伺服器沒有本地玩家；一般客戶端生成自己（步驟 3 起改用真正的 peer_id）
	if not Session.is_dedicated_server:
		_spawn_player(HOST_PEER_ID)


func _physics_process(_delta: float) -> void:
	current_tick += 1
	_simulate_tick(current_tick)


## 每 tick 的模擬入口。
func _simulate_tick(tick: int) -> void:
	# 本地玩家：拍一張 InputFrame，餵給模擬。
	# 注意：模擬函式只認得 InputFrame，完全不知道輸入來自鍵盤還是網路。
	if player_states.has(HOST_PEER_ID):
		var state: Dictionary = player_states[HOST_PEER_ID]
		var frame := LocalInput.capture(tick, self, state.pos)
		state.pos = PlayerSim.simulate_movement(
			state.pos, frame, state.move_speed, ARENA_BOUNDS
		)

	# 模擬結果 → 節點位置（步驟 5 起，遠端玩家會改成延遲插值）
	for peer_id: int in player_states:
		player_nodes[peer_id].position = player_states[peer_id].pos


## 生成一位玩家：建立模擬狀態 + 場景節點，都以 peer_id 為 key。
func _spawn_player(peer_id: int) -> void:
	var node: Node2D = PLAYER_SCENE.instantiate()
	node.position = ARENA_BOUNDS.get_center()
	add_child(node)
	player_states[peer_id] = {
		"pos": node.position,
		"move_speed": DEFAULT_MOVE_SPEED,
	}
	player_nodes[peer_id] = node


## 視覺更新（非邏輯）。之後會擴充成完整的除錯疊層（步驟 3）。
func _process(_delta: float) -> void:
	tick_label.text = "tick: %d" % current_tick

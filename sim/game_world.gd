## 世界模擬（arena.tscn 的根節點）——模擬層的核心。
##
## 核心原則 1（固定 tick）：邏輯只在 _physics_process（60Hz）推進，時間單位是 tick 編號。
## 核心原則 2（server-authoritative）：只有伺服器跑模擬；客戶端送輸入、收狀態。
## 核心原則 4（不假設玩家數量）：玩家一律放 Dictionary[peer_id]。
##
## 步驟 3 的同步方式（過渡期）：
##   客戶端上傳輸入 → 伺服器模擬 → 廣播位置 → 客戶端直接套用。
##   在真實網路下這會讓「自己的角色」有延遲、別人的角色會抖——
##   步驟 4（預測/和解）與步驟 5（插值）就是來解決這兩件事的。
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")

## 可活動範圍（地板的矩形）。M4 做房間系統時改由房間提供。
const ARENA_BOUNDS := Rect2(40, 40, 1200, 640)

## 預設移動速度（像素/秒）。放進每位玩家的狀態，M3 的 modifier 會動態改寫。
const DEFAULT_MOVE_SPEED := 320.0

## 佔位配色：自己藍色、別人綠色。（品紅/橘紅保留給敵人危險區域，不可用）
const COLOR_SELF := Color(0.3, 0.62, 1.0)
const COLOR_OTHER := Color(0.35, 0.85, 0.45)

## 目前的 tick 編號。開場為 0，每個 physics frame +1。
var current_tick: int = 0

## peer_id -> 模擬狀態（pos、move_speed、last_input...）。模擬層只碰這個。
var player_states: Dictionary = {}

## peer_id -> 場景節點（表現層）。位置永遠是從模擬狀態抄過去的。
var player_nodes: Dictionary = {}

## 客戶端：最近一次收到的伺服器狀態是哪個 tick（除錯疊層要看）
var last_server_state_tick: int = -1

## 客戶端：收到上次狀態之後，本地又過了幾個 tick（判斷斷線/卡頓）
var ticks_since_server_state: int = 0


func _ready() -> void:
	var net := NetworkManager.instance
	if net.is_server():
		# host 兼玩家：生成自己。專用伺服器沒有本地玩家。
		if not Session.is_dedicated_server:
			_spawn_player(NetworkManager.SERVER_PEER_ID)
		# 之後才連上的玩家（換場景前就連上的理論上沒有，保險起見也補生成）
		net.peer_joined.connect(_on_peer_joined)
		net.peer_left.connect(_on_peer_left)
		for peer_id in multiplayer.get_peers():
			_spawn_player(peer_id)
	else:
		# 客戶端：伺服器斷線就回主選單
		net.server_lost.connect(_on_server_lost)


func _physics_process(_delta: float) -> void:
	current_tick += 1
	_simulate_tick(current_tick)

	# 測試用：跑滿指定 tick 數自動結束（headless 煙霧測試）
	if Session.quit_after_ticks > 0 and current_tick >= Session.quit_after_ticks:
		print("[world] 跑滿 %d tick，結束" % current_tick)
		get_tree().quit()


## 每 tick 的模擬入口。
func _simulate_tick(tick: int) -> void:
	var net := NetworkManager.instance
	if net.is_server():
		_server_tick(tick, net)
	else:
		_client_tick(tick, net)

	# 模擬結果 → 節點位置（表現層永遠只是抄狀態）
	for peer_id: int in player_states:
		player_nodes[peer_id].position = player_states[peer_id].pos


## 伺服器：權威模擬所有玩家，然後廣播狀態。
func _server_tick(tick: int, net: NetworkManager) -> void:
	# host 兼玩家：自己的輸入不走網路，直接進同一個緩衝（和遠端玩家走完全相同的路徑）
	if not Session.is_dedicated_server:
		var my_state: Dictionary = player_states[NetworkManager.SERVER_PEER_ID]
		net.push_input(NetworkManager.SERVER_PEER_ID, LocalInput.capture(tick, self, my_state.pos))

	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		var frame: InputFrame = net.consume_latest_input(peer_id)
		if frame != null:
			state.last_input = frame
		# 這 tick 沒收到新輸入（封包丟了）就沿用上一筆，角色不會突然定住
		if state.last_input != null:
			state.pos = PlayerSim.simulate_movement(
				state.pos, state.last_input, state.move_speed, ARENA_BOUNDS
			)

	_broadcast_state(tick)


## 客戶端：上傳輸入；位置完全聽伺服器的（步驟 4 會改成本地預測）。
func _client_tick(tick: int, net: NetworkManager) -> void:
	ticks_since_server_state += 1
	var my_id := multiplayer.get_unique_id()
	var aim_origin: Vector2 = ARENA_BOUNDS.get_center()
	if player_states.has(my_id):
		aim_origin = player_states[my_id].pos
	net.submit_local_input(LocalInput.capture(tick, self, aim_origin))


## 伺服器 → 所有客戶端：全部玩家的位置。
func _broadcast_state(tick: int) -> void:
	var positions: Dictionary = {}
	for peer_id: int in player_states:
		positions[peer_id] = player_states[peer_id].pos
	_receive_state.rpc({"t": tick, "p": positions})


@rpc("authority", "unreliable_ordered")
func _receive_state(state_data: Dictionary) -> void:
	last_server_state_tick = state_data.get("t", -1)
	ticks_since_server_state = 0
	var positions: Dictionary = state_data.get("p", {})

	# 有新玩家就生成、位置照伺服器說的套用
	for peer_id: int in positions:
		if not player_states.has(peer_id):
			_spawn_player(peer_id)
		player_states[peer_id].pos = positions[peer_id]

	# 狀態裡消失的玩家＝離開了，移除
	for peer_id: int in player_states.keys():
		if not positions.has(peer_id):
			_despawn_player(peer_id)


## 生成一位玩家：模擬狀態 + 場景節點，都以 peer_id 為 key。
func _spawn_player(peer_id: int) -> void:
	if player_states.has(peer_id):
		return
	var node: Node2D = PLAYER_SCENE.instantiate()
	# 出生點：中心往右排開，避免疊在一起（依現有人數排）
	node.position = ARENA_BOUNDS.get_center() + Vector2(48.0 * player_states.size(), 0)
	add_child(node)
	# 自己藍色、別人綠色（headless 伺服器沒有「自己」，全部算別人）
	var is_me := not Session.is_dedicated_server \
		and peer_id == multiplayer.get_unique_id()
	node.get_node("Body").color = COLOR_SELF if is_me else COLOR_OTHER
	player_states[peer_id] = {
		"pos": node.position,
		"move_speed": DEFAULT_MOVE_SPEED,
		"last_input": null,
	}
	player_nodes[peer_id] = node
	print("[world] 生成玩家 peer %d" % peer_id)


func _despawn_player(peer_id: int) -> void:
	if player_nodes.has(peer_id):
		player_nodes[peer_id].queue_free()
	player_nodes.erase(peer_id)
	player_states.erase(peer_id)
	print("[world] 移除玩家 peer %d" % peer_id)


func _on_peer_joined(peer_id: int) -> void:
	_spawn_player(peer_id)


func _on_peer_left(peer_id: int) -> void:
	_despawn_player(peer_id)


func _on_server_lost() -> void:
	print("[world] 與伺服器斷線，回主選單")
	get_tree().change_scene_to_file("res://main.tscn")

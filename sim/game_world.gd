## 世界模擬（arena.tscn 的根節點）——模擬層的核心。
##
## 核心原則 1（固定 tick）：邏輯只在 _physics_process（60Hz）推進，時間單位是 tick 編號。
## 核心原則 2（server-authoritative）：只有伺服器跑模擬；客戶端送輸入、收狀態。
## 核心原則 4（不假設玩家數量）：玩家一律放 Dictionary[peer_id]。
##
## 同步方式（步驟 4 起）：
##   客戶端上傳輸入並「立刻」本地預測自己的角色（零輸入延遲）；
##   伺服器權威模擬所有人，狀態帶著 ack（最後消化的輸入 tick）廣播回來；
##   客戶端比對 ack 那格的預測歷史，不一致就回滾重放（ClientPrediction）。
##   別人的角色目前仍直接套用位置，會抖——步驟 5（插值）解決。
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

## 客戶端：自己角色的預測與和解（伺服器與 host 玩家不需要，維持 null）
var prediction: ClientPrediction = null


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
		if prediction != null:
			print("[world] 和解修正 %d 次，未確認輸入 %d 筆" % [
				prediction.correction_count, prediction.pending_inputs.size(),
			])
		get_tree().quit()


## 每 tick 的模擬入口。
func _simulate_tick(tick: int) -> void:
	var net := NetworkManager.instance
	if net.is_server():
		_server_tick(tick, net)
	else:
		_client_tick(tick, net)

	# 模擬結果 → 節點位置（表現層永遠只是抄狀態）。
	# 自己的角色多加 visual_error：和解修正時平滑滑回去，不瞬移。
	for peer_id: int in player_states:
		var render_pos: Vector2 = player_states[peer_id].pos
		if prediction != null and peer_id == multiplayer.get_unique_id():
			render_pos += prediction.visual_error
		player_nodes[peer_id].position = render_pos


## 伺服器：權威模擬所有玩家，然後廣播狀態。
func _server_tick(tick: int, net: NetworkManager) -> void:
	# host 兼玩家：自己的輸入不走網路，直接進同一個緩衝（和遠端玩家走完全相同的路徑）
	if not Session.is_dedicated_server:
		var my_state: Dictionary = player_states[NetworkManager.SERVER_PEER_ID]
		net.push_input(
			NetworkManager.SERVER_PEER_ID, _capture_input(tick, my_state.pos)
		)

	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		var frame: InputFrame = net.consume_next_input(peer_id)
		if frame != null:
			state.last_input = frame
			state.ack_tick = frame.tick   # 回報給客戶端：你的輸入我消化到這裡了
		# 這 tick 沒收到新輸入（封包丟了）就沿用上一筆，角色不會突然定住
		if state.last_input != null:
			state.pos = PlayerSim.simulate_movement(
				state.pos, state.last_input, state.move_speed, ARENA_BOUNDS
			)

	_broadcast_state(tick)


## 客戶端：上傳輸入，並「立刻」本地預測自己的角色（不等伺服器）。
func _client_tick(tick: int, net: NetworkManager) -> void:
	ticks_since_server_state += 1
	var my_id := multiplayer.get_unique_id()

	# 還沒收到自己的出生狀態：先送輸入就好
	if not player_states.has(my_id):
		net.submit_local_input(_capture_input(tick, ARENA_BOUNDS.get_center()))
		return

	var state: Dictionary = player_states[my_id]
	var frame := _capture_input(tick, state.pos)
	net.submit_local_input(frame)
	# 預測：立刻用與伺服器相同的 PlayerSim 模擬（本地零輸入延遲的來源）
	state.pos = prediction.predict(state.pos, frame, state.move_speed, ARENA_BOUNDS)
	prediction.decay_visual_error()


## 產生本地輸入：正常從裝置讀（LocalInput）；--bot 模式用合成的繞圈移動
## （headless 測試沒有輸入裝置，用它來驗證預測/和解）。
func _capture_input(tick: int, aim_origin: Vector2) -> InputFrame:
	if Session.bot_mode:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.move = Vector2(sin(tick * 0.05), cos(tick * 0.05))
		return frame
	return LocalInput.capture(tick, self, aim_origin)


## 伺服器 → 所有客戶端：全部玩家的位置 + 各自的輸入 ack。
func _broadcast_state(tick: int) -> void:
	var positions: Dictionary = {}
	var acks: Dictionary = {}
	for peer_id: int in player_states:
		positions[peer_id] = player_states[peer_id].pos
		acks[peer_id] = player_states[peer_id].get("ack_tick", -1)
	_receive_state.rpc({"t": tick, "p": positions, "a": acks})


@rpc("authority", "unreliable_ordered")
func _receive_state(state_data: Dictionary) -> void:
	last_server_state_tick = state_data.get("t", -1)
	ticks_since_server_state = 0
	var positions: Dictionary = state_data.get("p", {})
	var acks: Dictionary = state_data.get("a", {})
	var my_id := multiplayer.get_unique_id()

	for peer_id: int in positions:
		if not player_states.has(peer_id):
			_spawn_player(peer_id)
		if peer_id == my_id and prediction != null:
			# 自己：走和解（比對預測歷史，必要時回滾重放）
			var state: Dictionary = player_states[peer_id]
			state.pos = prediction.reconcile(
				state.pos,
				positions[peer_id],
				acks.get(peer_id, -1),
				state.move_speed,
				ARENA_BOUNDS
			)
		else:
			# 別人：直接套用（步驟 5 改成延遲插值）
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
		"ack_tick": -1,
	}
	player_nodes[peer_id] = node
	# 客戶端為「自己」建立預測器（伺服器端與 host 玩家不需要——他們就是權威）
	if is_me and not NetworkManager.instance.is_server():
		prediction = ClientPrediction.new()
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

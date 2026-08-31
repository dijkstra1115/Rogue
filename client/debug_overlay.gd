## 除錯疊層第一版（步驟 3）：tick、模式、玩家清單、ping、狀態鮮度。
## 步驟 4 會加上：未確認輸入數、和解修正次數。
##
## 掛在 arena.tscn 的 HUD（CanvasLayer）上，父節點就是 game_world。
extends CanvasLayer

@onready var label: Label = %DebugLabel
@onready var world: Node2D = get_parent()


func _process(_delta: float) -> void:
	var net := NetworkManager.instance
	var lines: PackedStringArray = []

	lines.append("tick: %d   模式: %s" % [world.current_tick, _mode_name(net)])

	var ids: Array = world.player_states.keys()
	ids.sort()
	lines.append("玩家 x%d: %s" % [ids.size(), str(ids)])

	if net.is_server():
		lines.append("已連線 peers: %s" % str(multiplayer.get_peers()))
		var backlog: Dictionary = {}
		for peer_id: int in net.input_buffers:
			backlog[peer_id] = net.buffered_input_count(peer_id)
		lines.append("輸入積壓: %s" % str(backlog))
	else:
		lines.append("ping: %s   距上次伺服器狀態: %d tick" % [
			_ping_text(), world.ticks_since_server_state,
		])
		if world.prediction != null:
			lines.append("未確認輸入: %d   和解修正: %d" % [
				world.prediction.pending_inputs.size(),
				world.prediction.correction_count,
			])
		var interp_sizes: Dictionary = {}
		for peer_id: int in world.player_states:
			var state: Dictionary = world.player_states[peer_id]
			if state.has("interp"):
				interp_sizes[peer_id] = state.interp.size()
		if not interp_sizes.is_empty():
			lines.append("插值時鐘: %.1f   緩衝: %s" % [
				world.interp_render_tick, str(interp_sizes),
			])

	label.text = "\n".join(lines)


func _mode_name(net: NetworkManager) -> String:
	if Session.is_dedicated_server:
		return "專用伺服器"
	if net.is_server():
		return "主機（兼玩家）"
	return "客戶端"


## 從 ENet 讀 round-trip time（只有客戶端有意義）
func _ping_text() -> String:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "-"
	var enet_peer := peer.get_peer(NetworkManager.SERVER_PEER_ID)
	if enet_peer == null:
		return "-"
	return "%d ms" % int(enet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

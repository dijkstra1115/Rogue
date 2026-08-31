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
	else:
		lines.append("ping: %s   距上次伺服器狀態: %d tick" % [
			_ping_text(), world.ticks_since_server_state,
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

## 網路層（autoload 名稱：Net，程式碼一律透過 NetworkManager.instance 取用）。
##
## 職責只有「傳輸」：建立/關閉 ENet 連線、上傳輸入、轉發訊號。
## 不含任何遊戲邏輯——模擬與判定都在 game_world 的伺服器端（核心原則 2）。
##
## 為什麼是 autoload：RPC 要求兩端有相同路徑的節點，autoload 的路徑（/root/Net）
## 在換場景時也不變。程式碼不直接寫 `Net`（headless 測試模式解析不到 autoload），
## 而是用 NetworkManager.instance（class_name + static，編譯期就解析得到）。
class_name NetworkManager
extends Node

const PORT := 7777
const MAX_PLAYERS := 8   # 房間人數上限；未來要 32 就改這個數字

## ENet 慣例：伺服器的 peer_id 固定是 1
const SERVER_PEER_ID := 1

## 每位玩家的輸入緩衝最多留這麼多筆（防止伺服器卡頓時無限堆積）
const INPUT_BUFFER_CAP := 10

static var instance: NetworkManager

## 伺服器端：peer_id -> Array[InputFrame]，等著被模擬消化的輸入
var input_buffers: Dictionary = {}

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_ok        # 客戶端：成功連上伺服器
signal connect_failed      # 客戶端：連線失敗
signal server_lost         # 客戶端：連線中途斷掉


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: connected_ok.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## 開伺服器（host 兼玩家與專用伺服器都走這裡）
func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	print("[net] 伺服器啟動，port %d" % PORT)
	return OK


## 以客戶端身分連向伺服器
func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	print("[net] 連線中：%s:%d" % [ip, PORT])
	return OK


## 斷線／清掉連線狀態（回主選單時用）
func leave() -> void:
	multiplayer.multiplayer_peer = null
	input_buffers.clear()


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


## ---- 輸入上傳 ----

## 客戶端每 tick 呼叫：把本地 InputFrame 送到伺服器
func submit_local_input(frame: InputFrame) -> void:
	_submit_input.rpc_id(SERVER_PEER_ID, frame.to_dict())


## 伺服器端（host 兼玩家）：本地輸入不走網路，直接進緩衝
func push_input(peer_id: int, frame: InputFrame) -> void:
	_buffer_input(peer_id, frame)


@rpc("any_peer", "unreliable_ordered")
func _submit_input(input_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_buffer_input(sender_id, InputFrame.from_dict(input_data))


func _buffer_input(peer_id: int, frame: InputFrame) -> void:
	if not input_buffers.has(peer_id):
		input_buffers[peer_id] = []
	var buffer: Array = input_buffers[peer_id]
	buffer.append(frame)
	while buffer.size() > INPUT_BUFFER_CAP:
		buffer.pop_front()


## 伺服器每 tick 呼叫：取出某玩家「下一筆」輸入（照順序，一 tick 消化一筆）。
## 沒收到新輸入時回傳 null（呼叫端沿用上一筆——封包丟了也不停頓）。
##
## 刻意用 pop_front 而不是「拿最新的」：客戶端每 tick 產一筆、伺服器每 tick
## 吃一筆，緩衝區天然吸收網路抖動。跳著吃會讓客戶端的預測常態性猜錯。
func consume_next_input(peer_id: int) -> InputFrame:
	var buffer: Array = input_buffers.get(peer_id, [])
	if buffer.is_empty():
		return null
	return buffer.pop_front()


## 目前積壓中的輸入筆數（伺服器排水邏輯與除錯疊層用）
func buffered_input_count(peer_id: int) -> int:
	var buffer: Array = input_buffers.get(peer_id, [])
	return buffer.size()


## ---- 連線事件 ----

func _on_peer_connected(peer_id: int) -> void:
	print("[net] peer %d 連上" % peer_id)
	if multiplayer.is_server():
		input_buffers[peer_id] = []
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[net] peer %d 離開" % peer_id)
	input_buffers.erase(peer_id)
	peer_left.emit(peer_id)


func _on_connection_failed() -> void:
	leave()
	connect_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_lost.emit()

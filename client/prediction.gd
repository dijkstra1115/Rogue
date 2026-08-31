## 客戶端預測與和解（步驟 4）——只負責「自己的角色」。
##
## 原理：
##   - 每 tick 送出輸入的同時，立刻用與伺服器相同的 PlayerSim 在本地模擬
##     （這就是「本地零輸入延遲」的來源）
##   - 保留未被伺服器確認的輸入，以及逐 tick 的預測位置歷史
##   - 伺服器狀態帶著 ack（該玩家最後被消化的輸入 tick）回來：
##       預測一致 → 清掉舊資料；不一致 → 跳回伺服器位置，重放 ack 之後的輸入
##   - 修正不瞬移：視覺偏移（visual_error）讓方塊平滑滑回正確位置
##
## 純邏輯 class（不碰節點、不碰網路），可單獨 headless 測試。
class_name ClientPrediction
extends RefCounted

## 預測與伺服器位置差多少以內算「猜對」（像素）
const RECONCILE_THRESHOLD := 0.5

## 未確認輸入的上限（伺服器長時間沒回應時防爆記憶體）
const MAX_PENDING := 120

## 視覺偏移每 tick 的衰減倍率（約 10 個 tick 內收斂）
const ERROR_DECAY := 0.8

## 視覺偏移大過這個值就直接瞬移——已經嚴重脫節，平滑只會更怪
const ERROR_SNAP_LIMIT := 128.0

## 尚未被伺服器確認的輸入（照 tick 順序）
var pending_inputs: Array[InputFrame] = []

## 輸入 tick -> 當時的預測位置
var predicted_history: Dictionary = {}

## 渲染位置 = 模擬位置 + visual_error，每 tick 衰減
var visual_error: Vector2 = Vector2.ZERO

## 和解修正的累計次數（除錯疊層要看；持續飆升代表預測有 bug）
var correction_count: int = 0


## 每 tick 呼叫：記錄輸入並立刻本地模擬，回傳新的預測位置。
func predict(pos: Vector2, frame: InputFrame, move_speed: float, bounds: Rect2) -> Vector2:
	pending_inputs.append(frame)
	while pending_inputs.size() > MAX_PENDING:
		var dropped: InputFrame = pending_inputs.pop_front()
		predicted_history.erase(dropped.tick)
	var new_pos := PlayerSim.simulate_movement(pos, frame, move_speed, bounds)
	predicted_history[frame.tick] = new_pos
	return new_pos


## 收到伺服器狀態時呼叫：比對並在必要時回滾＋重放。回傳和解後的模擬位置。
func reconcile(
	current_pos: Vector2,
	server_pos: Vector2,
	ack_tick: int,
	move_speed: float,
	bounds: Rect2
) -> Vector2:
	# 丟掉已被伺服器消化的輸入
	var kept: Array[InputFrame] = []
	for frame in pending_inputs:
		if frame.tick > ack_tick:
			kept.append(frame)
	pending_inputs = kept

	var predicted: Variant = predicted_history.get(ack_tick)
	_prune_history(ack_tick)

	if predicted != null and (predicted as Vector2).distance_to(server_pos) < RECONCILE_THRESHOLD:
		return current_pos   # 猜對了，什麼都不用做

	# 猜錯了（或沒有對應歷史，例如剛出生）：回到伺服器位置，重放未確認的輸入
	if predicted != null:
		correction_count += 1
	var old_render := current_pos + visual_error
	var new_pos := server_pos
	for frame in pending_inputs:
		new_pos = PlayerSim.simulate_movement(new_pos, frame, move_speed, bounds)
		predicted_history[frame.tick] = new_pos
	# 從舊的渲染位置平滑滑向新位置，而不是瞬移
	visual_error = old_render - new_pos
	if visual_error.length() > ERROR_SNAP_LIMIT:
		visual_error = Vector2.ZERO
	return new_pos


## 每 tick 呼叫：衰減視覺偏移
func decay_visual_error() -> void:
	visual_error *= ERROR_DECAY
	if visual_error.length() < 0.5:
		visual_error = Vector2.ZERO


func _prune_history(up_to_tick: int) -> void:
	for key: int in predicted_history.keys():
		if key <= up_to_tick:
			predicted_history.erase(key)

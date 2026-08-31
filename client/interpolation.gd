## 遠端實體插值（步驟 5）——負責「別人的角色」的平滑渲染。
##
## 原理：客戶端沒有別人的輸入可預測，所以刻意渲染「約 100ms 前的過去」：
## 把收到的 (伺服器 tick, 位置) 存進緩衝，在兩筆已知狀態之間內插。
## 代價是看到的隊友慢 100ms，換來完全平滑——本專案不做幀級精確互動，
## 這個延遲沒有實質影響（見 docs/00 的技術性定位）。
##
## 純邏輯 class（不碰節點、不碰網路），可單獨 headless 測試。
class_name RemoteInterpolation
extends RefCounted

## 緩衝保留的狀態筆數上限（60Hz 下約 0.66 秒）
const BUFFER_CAP := 40

## [{t: 伺服器 tick, pos: Vector2}]，t 嚴格遞增
var states: Array[Dictionary] = []


## 收到一筆伺服器狀態。亂序或重複（t 不比最後一筆新）直接忽略——
## unreliable_ordered 通道下這代表過期封包。
func push_state(server_tick: int, pos: Vector2) -> void:
	if not states.is_empty() and server_tick <= states.back().t:
		return
	states.append({"t": server_tick, "pos": pos})
	while states.size() > BUFFER_CAP:
		states.pop_front()


## 取 render_tick（可以是小數）時刻的插值位置。
## 緩衝為空回傳 null；早於最舊就用最舊；晚於最新（緩衝乾了）就凍結在最新。
func sample(render_tick: float) -> Variant:
	if states.is_empty():
		return null
	if render_tick <= states[0].t:
		return states[0].pos
	for i in range(states.size() - 1):
		var older: Dictionary = states[i]
		var newer: Dictionary = states[i + 1]
		if render_tick <= newer.t:
			# 兩筆之間可能隔多個 tick（封包丟失），內插自然補平
			var span := float(newer.t - older.t)
			var fraction: float = (render_tick - float(older.t)) / span
			return (older.pos as Vector2).lerp(newer.pos, clampf(fraction, 0.0, 1.0))
	return states.back().pos


func size() -> int:
	return states.size()

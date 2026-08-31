## 玩家移動模擬——純函式，不碰節點、不讀輸入裝置、沒有副作用。
##
## 這份程式碼被兩個地方共用（預測/和解能收斂的前提）：
##   1. 伺服器的權威模擬
##   2. 客戶端的本地預測
## 同樣的輸入必須永遠算出同樣的結果。
##
## M2 步驟 5 起，「移動狀態」不只位置：衝刺（位移技能）必須被客戶端預測，
## 否則有網路延遲時按衝刺會慢半拍。所以衝刺的全部狀態
## （剩餘 tick、方向、冷卻、按鍵上升沿）都放進移動狀態，回滾時一起重放。
class_name PlayerSim
extends RefCounted

## 固定 tick 的時間長度（秒）。寫死的常數，不是引擎 delta（核心原則 1）。
const TICK_DELTA := 1.0 / 60.0

## 方塊的一半尺寸（player.tscn 是 32x32），夾牆時用
const PLAYER_HALF_SIZE := 16.0

## ---- 衝刺（劍士的高機動補償，docs/02）----
## 沒有無敵幀（SPEC 明定不做幀級閃避）——衝刺是純位移。
const DASH_TICKS := 9                 # 衝刺持續 9 tick（0.15 秒）
const DASH_SPEED := 1400.0            # 衝刺速度（總位移 = 1400/60*9 = 210px）
const DASH_COOLDOWN_TICKS := 120      # 冷卻 2 秒（不隨攻速縮放）

## ---- 護盾（命中生成，伺服器邏輯；常數放這裡供各處引用）----
const SHIELD_CAP := 50.0              # 護盾上限（半條血）
const SHIELD_DECAY_PER_TICK := SHIELD_CAP / 300.0   # 滿盾 5 秒衰減完


## 初始化移動狀態欄位（生成玩家時呼叫）。
## move_speed 也屬於移動狀態：道具（M3）會改寫它，必須跟著快照回滾，
## 否則撿到移速道具的瞬間，客戶端預測用的速度會和伺服器不一致。
static func init_movement(state: Dictionary, pos: Vector2, move_speed: float) -> void:
	state.pos = pos
	state.move_speed = move_speed
	state.dash_left = 0            # 衝刺剩餘 tick（>0 = 衝刺中）
	state.dash_dir = Vector2.ZERO
	state.dash_ready = 0           # 下次可衝刺的輸入 tick
	state.prev_utility = false     # 上一 frame 的 utility 鍵（上升沿偵測）


## 拍一份移動狀態快照（預測歷史、伺服器下發用）。
static func snapshot_movement(state: Dictionary) -> Dictionary:
	return {
		"pos": state.pos,
		"move_speed": state.move_speed,
		"dash_left": state.dash_left,
		"dash_dir": state.dash_dir,
		"dash_ready": state.dash_ready,
		"prev_utility": state.prev_utility,
	}


## 用快照覆蓋移動狀態（和解回滾用）。
static func restore_movement(state: Dictionary, snap: Dictionary) -> void:
	state.pos = snap.pos
	state.move_speed = snap.move_speed
	state.dash_left = snap.dash_left
	state.dash_dir = snap.dash_dir
	state.dash_ready = snap.dash_ready
	state.prev_utility = snap.prev_utility


## 推進一個 tick 的移動（就地修改 state 的移動欄位）。
## 速度直接讀 state.move_speed（單一事實來源，隨快照回滾）。
## 時間一律用 frame.tick（輸入的 tick 域）——伺服器與客戶端預測才有共同語言。
static func step(state: Dictionary, frame: InputFrame, bounds: Rect2) -> void:
	# 衝刺起手：utility「上升沿」＋冷卻好＋不在衝刺中。
	# 上升沿（而不是按住就觸發）：按住空白鍵不會冷卻一好就自動再衝。
	if frame.utility and not state.prev_utility \
			and state.dash_left == 0 and frame.tick >= state.dash_ready:
		var dir: Vector2 = frame.move
		if dir.length() < 0.01:
			dir = frame.aim   # 沒推方向就往瞄準方向衝
		state.dash_dir = dir.normalized()
		state.dash_left = DASH_TICKS
		state.dash_ready = frame.tick + DASH_COOLDOWN_TICKS
	state.prev_utility = frame.utility

	var new_pos: Vector2
	if state.dash_left > 0:
		# 衝刺中：固定方向高速位移，忽略移動輸入
		state.dash_left -= 1
		new_pos = state.pos + state.dash_dir * DASH_SPEED * TICK_DELTA
	else:
		# limit_length(1.0)：防止鍵盤斜走比直走快（或惡意客戶端送超長向量）
		new_pos = state.pos + frame.move.limit_length(1.0) * state.move_speed * TICK_DELTA

	var min_corner := bounds.position + Vector2.ONE * PLAYER_HALF_SIZE
	var max_corner := bounds.end - Vector2.ONE * PLAYER_HALF_SIZE
	state.pos = new_pos.clamp(min_corner, max_corner)

## 玩家移動模擬——純函式，不碰節點、不讀輸入裝置、沒有副作用。
##
## 這份程式碼將被兩個地方共用（步驟 4 的關鍵前提）：
##   1. 伺服器的權威模擬
##   2. 客戶端的本地預測
## 同樣的輸入必須永遠算出同樣的結果，否則和解永遠不會收斂。
class_name PlayerSim
extends RefCounted

## 固定 tick 的時間長度（秒）。這是「速度 → 每 tick 位移」的換算係數，
## 是寫死的常數，不是引擎給的 delta——模擬必須是確定性的（核心原則 1）。
const TICK_DELTA := 1.0 / 60.0

## 方塊的一半尺寸（player.tscn 是 32x32），夾牆時用
const PLAYER_HALF_SIZE := 16.0


## 算出一個 tick 之後的新位置。
## move_speed 由呼叫端從玩家狀態傳入（像素/秒）——之後 M3 的 modifier
## 會動態改寫玩家屬性，所以速度不能寫死在這裡。
## bounds 是可活動範圍（M4 換房間時由房間提供）。
static func simulate_movement(
	pos: Vector2, frame: InputFrame, move_speed: float, bounds: Rect2
) -> Vector2:
	# limit_length(1.0)：防止鍵盤斜走比直走快（或惡意客戶端送超長向量）
	var new_pos := pos + frame.move.limit_length(1.0) * move_speed * TICK_DELTA
	# 夾在房間範圍內，扣掉方塊自己的半寬
	var min_corner := bounds.position + Vector2.ONE * PLAYER_HALF_SIZE
	var max_corner := bounds.end - Vector2.ONE * PLAYER_HALF_SIZE
	return new_pos.clamp(min_corner, max_corner)

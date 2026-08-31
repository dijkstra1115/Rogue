## 敵人移動模擬（M2 步驟 3）——純函式，只在伺服器執行。
##
## 追擊規則：朝目標直線移動，進入停止距離就站定（攻擊是步驟 4 的事）。
## 敵人速度刻意比玩家慢（140 vs 320）：前期「靠走位躲」的前提是跑得掉。
class_name EnemySim
extends RefCounted

## 追擊速度（像素/秒）。之後不同敵種會有各自的值，放進敵人狀態。
const CHASE_SPEED := 140.0

## 距離目標多近就停下（貼臉距離，攻擊判定的預設起手範圍）
const STOP_RANGE := 30.0

## 敵人彼此間的最小距離（避免全部疊成一點）
const SEPARATION_DIST := 26.0


## 朝目標追一個 tick。不會衝過頭：最多走到停止距離的邊上。
static func simulate_chase(
	pos: Vector2, target: Vector2, speed: float, stop_range: float, bounds: Rect2
) -> Vector2:
	var to_target := target - pos
	var distance := to_target.length()
	if distance <= stop_range:
		return pos
	var step_length := minf(speed * PlayerSim.TICK_DELTA, distance - stop_range)
	var new_pos := pos + to_target / distance * step_length
	return _clamp_to_bounds(new_pos, bounds)


## 分離：太近的敵人互相推開（各退一半重疊量）。O(n²)，敵人數量大時再優化。
## 只在伺服器跑，Dictionary 的插入序迭代是確定性的。
static func apply_separation(states: Dictionary, min_dist: float, bounds: Rect2) -> void:
	var ids: Array = states.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: Dictionary = states[ids[i]]
			var b: Dictionary = states[ids[j]]
			var delta: Vector2 = b.pos - a.pos
			var distance := delta.length()
			if distance >= min_dist:
				continue
			# 完全重疊時給一個固定方向，避免除以零
			var push := Vector2.RIGHT if distance < 0.001 else delta / distance
			var amount := (min_dist - distance) * 0.5
			a.pos = _clamp_to_bounds(a.pos - push * amount, bounds)
			b.pos = _clamp_to_bounds(b.pos + push * amount, bounds)


static func _clamp_to_bounds(pos: Vector2, bounds: Rect2) -> Vector2:
	var half := Vector2.ONE * 14.0   # 敵人方塊 28x28 的一半
	return pos.clamp(bounds.position + half, bounds.end - half)

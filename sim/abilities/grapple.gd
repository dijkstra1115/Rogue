## 劍士的隊友向技能：抓鉤——把最近的隊友拉到身邊（M2 步驟 6）。
##
## 這是 TargetKind.ALLY 的第一個實例，驗證技能系統「可指定隊友為目標」
## 的架構要求（docs/02）。沒有隊友在範圍內時發動失敗、不消耗冷卻。
##
## 被拉的隊友在他自己的客戶端上會觸發一次和解修正（他的預測不可能料到
## 被隊友移動）——這是預期行為，位移由視覺偏移平滑或直接跳過去。
class_name Grapple
extends Ability

## 抓鉤最遠距離
const RANGE := 600.0

## 拉到施放者身邊多遠的位置（不要疊在同一點）
const ARRIVE_OFFSET := 40.0


func _init() -> void:
	target_kind = TargetKind.ALLY
	base_cooldown_ticks = 300   # 5 秒；救援技能不隨攻速縮放
	scales_with_attack_speed = false


func execute(world: Node2D, caster_id: int, _frame: InputFrame, _tick: int) -> bool:
	var ally_id := find_nearest_ally(world.player_states, caster_id, RANGE)
	if ally_id == -1:
		return false   # 沒有隊友在範圍內：不發動、不進冷卻

	var caster: Dictionary = world.player_states[caster_id]
	var ally: Dictionary = world.player_states[ally_id]
	var from_pos: Vector2 = ally.pos
	var offset: Vector2 = ally.pos - caster.pos
	var target_pos: Vector2 = caster.pos
	if offset.length() > ARRIVE_OFFSET:
		target_pos = caster.pos + offset.normalized() * ARRIVE_OFFSET
	# 夾在房間範圍內（沿用玩家的半寬）
	ally.pos = target_pos.clamp(
		world.ARENA_BOUNDS.position + Vector2.ONE * PlayerSim.PLAYER_HALF_SIZE,
		world.ARENA_BOUNDS.end - Vector2.ONE * PlayerSim.PLAYER_HALF_SIZE
	)
	world.pending_events.append({"k": "grapple", "from": from_pos, "to": ally.pos})
	return true


## 找 caster 以外、範圍內最近的玩家；沒有回傳 -1。（純函式，可測試）
static func find_nearest_ally(players: Dictionary, caster_id: int, max_range: float) -> int:
	var caster_pos: Vector2 = players[caster_id].pos
	var best_id := -1
	var best_dist := max_range
	for peer_id: int in players:
		if peer_id == caster_id:
			continue
		var dist: float = players[peer_id].pos.distance_to(caster_pos)
		if dist <= best_dist:
			best_dist = dist
			best_id = peer_id
	return best_id

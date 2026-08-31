## 劍士主攻擊：扇形揮擊（M2 步驟 1）。
##
## 「攻擊自帶範圍」是近戰的補償機制之一（docs/02）——
## 揮劍是扇形而非單體，範圍之後隨道具成長（M3 會把 RANGE 變成可修飾屬性）。
class_name SwordSweep
extends Ability

## 扇形張角（度）與半徑（像素）
const ARC_DEG := 100.0
const RANGE := 90.0

## 基礎傷害（步驟 2 接上敵人後使用）
const DAMAGE := 10.0

## 每命中一隻敵人生成的護盾量——「持續攻擊本身就是生存手段」（docs/02）。
## 一刀掃到越多隻、疊得越快，鼓勵衝進人群。
const SHIELD_PER_HIT := 5.0


func _init() -> void:
	target_kind = TargetKind.ENEMIES
	base_cooldown_ticks = 60   # 劍士基礎攻速：每秒 1 次（docs/03 的觸發係數以此為基準）
	scales_with_attack_speed = true


func execute(world: Node2D, caster_id: int, frame: InputFrame, tick: int) -> void:
	var origin: Vector2 = world.player_states[caster_id].pos
	# 揮擊事件：伺服器本地呈現＋廣播給所有客戶端畫扇形
	world.pending_events.append({
		"k": "sweep", "id": caster_id, "o": origin, "a": frame.aim,
	})
	# 對扇形內的所有敵人結算傷害（keys 快照——apply_damage 可能移除敵人）
	for enemy_id: int in world.enemy_states.keys():
		var enemy: Dictionary = world.enemy_states[enemy_id]
		if is_in_sector(origin, frame.aim, enemy.pos, RANGE, ARC_DEG):
			world.apply_damage(
				Combat.make_damage_event(caster_id, enemy_id, DAMAGE, tick)
			)
			world.grant_shield(caster_id, SHIELD_PER_HIT)


## 扇形命中判定（純幾何，可單獨測試）。
## origin 揮擊原點、aim 瞄準方向（單位向量）、point 目標位置。
static func is_in_sector(
	origin: Vector2, aim: Vector2, point: Vector2, max_range: float, arc_deg: float
) -> bool:
	var to_point := point - origin
	var distance := to_point.length()
	if distance > max_range:
		return false
	if distance < 0.001:
		return true   # 重疊在原點上必中，避免零向量算角度
	return absf(aim.angle_to(to_point)) <= deg_to_rad(arc_deg) * 0.5

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


## 劍士揮擊的觸發係數：慢速重擊 = 1.0（docs/03 的基準）
const PROC_COEFFICIENT := 1.0


func execute(world: Node2D, caster_id: int, frame: InputFrame, tick: int) -> bool:
	var state: Dictionary = world.player_states[caster_id]
	var origin: Vector2 = state.pos
	var mods: ModifierStack = state.get("mods")

	# 攻擊發動事件：道具可以增加揮擊道數（三重奏）、改散布角與傷害比例
	var attack_ctx := {
		"caster": caster_id, "tick": tick,
		"arc_count": 1,        # 揮幾道扇形
		"spread_deg": 40.0,    # 多道時彼此的夾角
		"damage_scale": 1.0,   # 每道的傷害比例（三重奏會壓低）
	}
	if mods != null:
		mods.dispatch_attack_start(attack_ctx)

	for arc_index: int in attack_ctx.arc_count:
		var aim := _arc_aim(frame.aim, arc_index, attack_ctx.arc_count, attack_ctx.spread_deg)
		world.pending_events.append({"k": "sweep", "id": caster_id, "o": origin, "a": aim})
		# 對扇形內的所有敵人結算傷害（keys 快照——apply_damage 可能移除敵人）
		for enemy_id: int in world.enemy_states.keys():
			if not world.enemy_states.has(enemy_id):
				continue   # 可能已被前一道扇形的觸發連鎖打死
			var enemy: Dictionary = world.enemy_states[enemy_id]
			if not is_in_sector(origin, aim, enemy.pos, RANGE, ARC_DEG):
				continue
			# 命中事件：道具可以改傷害、依觸發係數擲觸發（符文都掛這裡）
			var coefficient := PROC_COEFFICIENT
			if world.sandbox_proc_coefficient_override >= 0.0:
				coefficient = world.sandbox_proc_coefficient_override   # 弓手節奏模擬
			var hit_ctx := {
				"world": world,
				"attacker": caster_id,
				"target": enemy_id,
				"damage": DAMAGE * state.get("damage_mult", 1.0) * attack_ctx.damage_scale,
				"proc_coefficient": coefficient,
				"proc_depth": 0,
				"tick": tick,
			}
			if mods != null:
				mods.dispatch_hit(hit_ctx)
			world.apply_damage(Combat.make_damage_event(
				caster_id, enemy_id, hit_ctx.damage, tick,
				hit_ctx.proc_coefficient, hit_ctx.proc_depth
			))
			world.grant_shield(caster_id, SHIELD_PER_HIT)
	return true   # 揮空也算發動（進冷卻）


## 多道扇形的方向：以瞄準為中心左右展開（1 道 = 正中）。
static func _arc_aim(aim: Vector2, index: int, count: int, spread_deg: float) -> Vector2:
	if count <= 1:
		return aim
	var offset := (index - (count - 1) * 0.5) * deg_to_rad(spread_deg)
	return aim.rotated(offset)


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

## 世界模擬（arena.tscn 的根節點）——模擬層的核心。
##
## 核心原則 1（固定 tick）：邏輯只在 _physics_process（60Hz）推進，時間單位是 tick 編號。
## 核心原則 2（server-authoritative）：只有伺服器跑模擬；客戶端送輸入、收狀態。
## 核心原則 4（不假設玩家數量）：玩家一律放 Dictionary[peer_id]。
##
## 同步方式（步驟 4 起）：
##   客戶端上傳輸入並「立刻」本地預測自己的角色（零輸入延遲）；
##   伺服器權威模擬所有人，狀態帶著 ack（最後消化的輸入 tick）廣播回來；
##   客戶端比對 ack 那格的預測歷史，不一致就回滾重放（ClientPrediction）。
##   別人的角色：狀態進緩衝，渲染刻意落後 100ms 做插值（RemoteInterpolation）。
##   節點位置一律在 _process 更新（純視覺）；_physics_process 只推進模擬。
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

## 測試用敵人血量（M4 換成吃難度值的生成器）
const ENEMY_HP := 30.0

## ---- 波次生成（M2 測試場；M4 換成難度時鐘驅動的生成器）----
const WAVE_BASE_COUNT := 4        # 第一波隻數
const WAVE_COUNT_GROWTH := 1      # 每波多幾隻
const WAVE_BREAK_TICKS := 180     # 清場後多久出下一波（3 秒）
const WAVE_SPAWN_MARGIN := 70.0   # 出生點離牆的內縮距離

## 可活動範圍（地板的矩形）。M4 做房間系統時改由房間提供。
const ARENA_BOUNDS := Rect2(40, 40, 1200, 640)

## 預設移動速度（像素/秒）。放進每位玩家的狀態，M3 的 modifier 會動態改寫。
const DEFAULT_MOVE_SPEED := 320.0

## 輸入緩衝的目標水位（筆）。夠吸收抖動，又不讓伺服器落後太多。
const INPUT_BACKLOG_TARGET := 2

## 積壓太多時，一個 tick 最多補吃幾筆（防止長卡頓後瞬間跳很遠）
const MAX_INPUTS_PER_TICK := 3

## 遠端玩家渲染刻意落後的 tick 數（6 tick = 100ms @60Hz）
const INTERP_DELAY_TICKS := 6

## 插值時鐘與目標脫節超過這個 tick 數就直接跳（例如長時間卡頓後）
const INTERP_SNAP_LIMIT := 30.0

## 佔位配色：自己藍色、別人綠色。（品紅/橘紅保留給敵人危險區域，不可用）
const COLOR_SELF := Color(0.3, 0.62, 1.0)
const COLOR_OTHER := Color(0.35, 0.85, 0.45)

## 目前的 tick 編號。開場為 0，每個 physics frame +1。
var current_tick: int = 0

## peer_id -> 模擬狀態（pos、move_speed、last_input...）。模擬層只碰這個。
var player_states: Dictionary = {}

## peer_id -> 場景節點（表現層）。位置永遠是從模擬狀態抄過去的。
var player_nodes: Dictionary = {}

## 客戶端：最近一次收到的伺服器狀態是哪個 tick（除錯疊層要看）
var last_server_state_tick: int = -1

## 客戶端：收到上次狀態之後，本地又過了幾個 tick（判斷斷線/卡頓）
var ticks_since_server_state: int = 0

## 客戶端：自己角色的預測與和解（伺服器與 host 玩家不需要，維持 null）
var prediction: ClientPrediction = null

## 客戶端：插值渲染時鐘（以伺服器 tick 為座標，落後最新狀態約 100ms；-1 = 未初始化）
var interp_render_tick: float = -1.0

## 伺服器：本 tick 產生的遊戲事件（揮擊、之後的受傷/死亡…），
## tick 結尾廣播給所有客戶端做視覺呈現，然後清空
var pending_events: Array = []

## enemy_id -> 敵人模擬狀態 {pos, hp, max_hp, kind}。
## 伺服器是權威；客戶端的這份是從狀態封包同步來的鏡像（供渲染）。
var enemy_states: Dictionary = {}

## enemy_id -> 場景節點（表現層）
var enemy_nodes: Dictionary = {}

## 伺服器：敵人流水號
var next_enemy_id: int = 1

## 目前波次（0 = 尚未開始）。伺服器權威，客戶端由狀態封包同步（疊層顯示用）。
var wave_number: int = 0

## 下一波的生成 tick（0 = 波次進行中，等清場才排程）
var next_wave_tick: int = 60

## 波次出生點用的隨機數（固定種子——重現問題時每次跑都一樣）
var wave_rng := RandomNumberGenerator.new()


func _ready() -> void:
	var net := NetworkManager.instance
	if net.is_server():
		# host 兼玩家：生成自己。專用伺服器沒有本地玩家。
		if not Session.is_dedicated_server:
			_spawn_player(NetworkManager.SERVER_PEER_ID)
		# 之後才連上的玩家（換場景前就連上的理論上沒有，保險起見也補生成）
		net.peer_joined.connect(_on_peer_joined)
		net.peer_left.connect(_on_peer_left)
		for peer_id in multiplayer.get_peers():
			_spawn_player(peer_id)
		wave_rng.seed = hash("rogue-waves")   # 固定種子，重現容易
	else:
		# 客戶端：伺服器斷線就回主選單
		net.server_lost.connect(_on_server_lost)


func _physics_process(_delta: float) -> void:
	current_tick += 1
	_simulate_tick(current_tick)

	# 測試用：跑滿指定 tick 數自動結束（headless 煙霧測試）
	if Session.quit_after_ticks > 0 and current_tick >= Session.quit_after_ticks:
		print("[world] 跑滿 %d tick，結束" % current_tick)
		if prediction != null:
			print("[world] 和解修正 %d 次，未確認輸入 %d 筆" % [
				prediction.correction_count, prediction.pending_inputs.size(),
			])
		get_tree().quit()


## 每 tick 的模擬入口。
func _simulate_tick(tick: int) -> void:
	var net := NetworkManager.instance
	if net.is_server():
		_server_tick(tick, net)
	else:
		_client_tick(tick, net)



## 伺服器：權威模擬所有玩家，然後廣播狀態。
func _server_tick(tick: int, net: NetworkManager) -> void:
	# host 兼玩家：自己的輸入不走網路，直接進同一個緩衝（和遠端玩家走完全相同的路徑）
	if not Session.is_dedicated_server:
		var my_state: Dictionary = player_states[NetworkManager.SERVER_PEER_ID]
		net.push_input(
			NetworkManager.SERVER_PEER_ID, _capture_input(tick, my_state.pos)
		)

	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		# 正常一 tick 吃一筆；積壓超過目標水位就多吃幾筆「排水」。
		# 抖動造成的凍結若不排水，積壓只增不減：ack 越落後、
		# 未確認輸入越堆越多，最後頂到緩衝上限開始丟輸入。
		var applied := 0
		while applied < MAX_INPUTS_PER_TICK:
			if applied > 0 and net.buffered_input_count(peer_id) <= INPUT_BACKLOG_TARGET:
				break
			var frame: InputFrame = net.consume_next_input(peer_id)
			if frame == null:
				break
			# 千萬不要在缺輸入時「沿用上一筆再模擬」——同一筆輸入套用兩次，
			# 客戶端預測永遠對不上（實測踩過的雷）。缺就凍結一格。
			state.last_input = frame
			state.ack_tick = frame.tick   # 回報給客戶端：你的輸入我消化到這裡了
			PlayerSim.step(state, frame, state.move_speed, ARENA_BOUNDS)
			_process_abilities(peer_id, state, frame, tick)
			applied += 1

	# 護盾衰減：每 tick 一次，與輸入無關（停手就開始掉，docs/02 的機制核心）
	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		state.shield = maxf(0.0, state.shield - PlayerSim.SHIELD_DECAY_PER_TICK)

	_simulate_enemies(tick)
	_update_waves(tick)
	_broadcast_state(tick)
	_flush_events()


## 伺服器：清場 → 休息 → 出下一波（隻數隨波次成長）。
func _update_waves(tick: int) -> void:
	if player_states.is_empty():
		return   # 還沒有玩家（例如剛開的專用伺服器）就先不出怪
	if not enemy_states.is_empty():
		return
	if next_wave_tick == 0:
		# 剛清場：排程下一波
		next_wave_tick = tick + WAVE_BREAK_TICKS
	elif tick >= next_wave_tick:
		wave_number += 1
		_spawn_wave(wave_number)
		next_wave_tick = 0


## 沿房間四邊隨機出生（離牆內縮，不會卡在牆裡）。
func _spawn_wave(wave: int) -> void:
	var count := WAVE_BASE_COUNT + (wave - 1) * WAVE_COUNT_GROWTH
	var inner := ARENA_BOUNDS.grow(-WAVE_SPAWN_MARGIN)
	for i in count:
		var pos: Vector2
		match i % 4:
			0: pos = Vector2(wave_rng.randf_range(inner.position.x, inner.end.x), inner.position.y)
			1: pos = Vector2(wave_rng.randf_range(inner.position.x, inner.end.x), inner.end.y)
			2: pos = Vector2(inner.position.x, wave_rng.randf_range(inner.position.y, inner.end.y))
			3: pos = Vector2(inner.end.x, wave_rng.randf_range(inner.position.y, inner.end.y))
		_spawn_enemy("chaser", pos)
	print("[world] 第 %d 波：%d 隻" % [wave, count])


## 伺服器：敵人 AI 狀態機——追擊 →（進入距離且冷卻好）前搖 → 結算 → 冷卻追擊。
## 前搖期間敵人定住，危險區鎖定「起手瞬間的目標位置」——玩家走出去就躲掉。
func _simulate_enemies(tick: int) -> void:
	if player_states.is_empty():
		return
	var chasing: Dictionary = {}   # 只有追擊中的敵人參與分離（前搖中不能被推動）
	for enemy_id: int in enemy_states:
		var enemy: Dictionary = enemy_states[enemy_id]
		match enemy.get("phase", "chase"):
			"chase":
				var target := _nearest_player_pos(enemy.pos)
				enemy.pos = EnemySim.simulate_chase(
					enemy.pos, target, enemy.move_speed, EnemySim.STOP_RANGE, ARENA_BOUNDS
				)
				chasing[enemy_id] = enemy
				if tick >= enemy.get("attack_ready_tick", 0) \
						and enemy.pos.distance_to(target) <= EnemySim.ATTACK_RANGE:
					enemy.phase = "windup"
					enemy.windup_end_tick = tick + EnemySim.ATTACK_WINDUP_TICKS
					enemy.attack_pos = target   # 鎖定此刻的位置，之後不再追蹤
					pending_events.append({
						"k": "telegraph", "o": target, "r": EnemySim.ATTACK_RADIUS,
						"s": tick, "e": enemy.windup_end_tick,
					})
			"windup":
				if tick >= enemy.windup_end_tick:
					_resolve_enemy_attack(enemy_id, enemy, tick)
	EnemySim.apply_separation(chasing, EnemySim.SEPARATION_DIST, ARENA_BOUNDS)


## 伺服器：前搖到期——圈內玩家吃傷害，敵人進冷卻。
func _resolve_enemy_attack(enemy_id: int, enemy: Dictionary, tick: int) -> void:
	for peer_id in EnemySim.players_hit(player_states, enemy.attack_pos, EnemySim.ATTACK_RADIUS):
		apply_player_damage({
			"source_enemy": enemy_id,
			"source_kind": enemy.get("kind", "?"),   # M5 死亡回放要知道兇手是誰
			"target": peer_id,
			"amount": EnemySim.ATTACK_DAMAGE,
			"tick": tick,
		})
	enemy.phase = "chase"
	enemy.attack_ready_tick = tick + EnemySim.ATTACK_COOLDOWN_TICKS


## 伺服器：命中回饋——給攻擊者疊護盾（上限封頂）。
func grant_shield(peer_id: int, amount: float) -> void:
	var state: Dictionary = player_states.get(peer_id, {})
	if state.is_empty():
		return
	state.shield = minf(state.shield + amount, PlayerSim.SHIELD_CAP)


## 伺服器：玩家受傷結算（護盾優先吸收）。歸零暫以「滿血重生」佔位——倒地救援是 M4。
func apply_player_damage(event: Dictionary) -> void:
	var state: Dictionary = player_states.get(event.target, {})
	if state.is_empty():
		return
	var died := Combat.apply_damage_with_shield(state, event)
	pending_events.append({
		"k": "player_hurt", "t": event.target, "n": event.amount, "o": state.pos,
	})
	if died:
		print("[world] 玩家 %d 倒下（暫以重生代替，M4 做倒地救援）" % event.target)
		state.hp = state.max_hp
		state.shield = 0.0
		state.pos = ARENA_BOUNDS.get_center()


func _nearest_player_pos(from_pos: Vector2) -> Vector2:
	var best_pos := Vector2.ZERO
	var best_dist := INF
	for peer_id: int in player_states:
		var dist: float = player_states[peer_id].pos.distance_squared_to(from_pos)
		if dist < best_dist:
			best_dist = dist
			best_pos = player_states[peer_id].pos
	return best_pos


## 伺服器：依輸入觸發技能（攻擊不做客戶端預測，權威只在這裡）。
## 執行成功才進冷卻——抓鉤沒抓到人這類失敗不吃冷卻。
func _process_abilities(peer_id: int, state: Dictionary, frame: InputFrame, tick: int) -> void:
	if frame.primary:
		_try_ability(peer_id, state, "primary", frame, tick)
	if frame.special:
		_try_ability(peer_id, state, "special", frame, tick)


func _try_ability(
	peer_id: int, state: Dictionary, slot: String, frame: InputFrame, tick: int
) -> void:
	var abilities: Dictionary = state.get("abilities", {})
	if not abilities.has(slot):
		return
	var ability: Ability = abilities[slot]
	if not ability.is_ready(tick):
		return
	if ability.execute(self, peer_id, frame, tick):
		ability.mark_used(tick, state.get("attack_speed", 1.0))


## 伺服器：把本 tick 的事件廣播出去（本地也立即呈現）。
## 事件走 reliable——揮擊/受傷這種一次性事件掉了就永遠掉了，和狀態不同。
func _flush_events() -> void:
	if pending_events.is_empty():
		return
	var events: Array = pending_events.duplicate()
	pending_events.clear()
	_apply_events(events)
	NetworkManager.instance.send_or_delay(func() -> void: _receive_events.rpc(events))


@rpc("authority", "reliable")
func _receive_events(events: Array) -> void:
	NetworkManager.instance.receive_or_delay(func() -> void: _apply_events(events))


## 事件 → 視覺（純表現層）。專用伺服器不需要畫面，直接跳過。
func _apply_events(events: Array) -> void:
	if Session.is_dedicated_server:
		return
	for event: Dictionary in events:
		match event.get("k", ""):
			"sweep":
				var fx := SweepArcFx.new()
				fx.position = event.o
				fx.aim = event.a
				add_child(fx)
			"hurt", "player_hurt":
				var number := DamageNumberFx.new()
				number.position = event.o
				number.amount = event.n
				add_child(number)
			"grapple":
				var grapple_fx := GrappleFx.new()
				grapple_fx.from_pos = event.from
				grapple_fx.to_pos = event.to
				add_child(grapple_fx)
			"telegraph":
				var telegraph := TelegraphFx.new()
				telegraph.position = event.o
				telegraph.radius = event.r
				telegraph.start_tick = event.s
				telegraph.end_tick = event.e
				telegraph.world = self
				%DangerLayer.add_child(telegraph)
			"enemy_died":
				pass   # 死亡特效之後再說（M5 打磨）；節點移除由狀態同步處理


## 客戶端：上傳輸入，並「立刻」本地預測自己的角色（不等伺服器）。
func _client_tick(tick: int, net: NetworkManager) -> void:
	ticks_since_server_state += 1
	_advance_interp_clock()
	var my_id := multiplayer.get_unique_id()

	# 還沒收到自己的出生狀態：先送輸入就好
	if not player_states.has(my_id):
		net.submit_local_input(_capture_input(tick, ARENA_BOUNDS.get_center()))
		return

	var state: Dictionary = player_states[my_id]
	var frame := _capture_input(tick, state.pos)
	net.submit_local_input(frame)
	# 預測：立刻用與伺服器相同的 PlayerSim.step 模擬（本地零輸入延遲；衝刺也預測）
	prediction.predict(state, frame, state.move_speed, ARENA_BOUNDS)
	prediction.decay_visual_error()


## 產生本地輸入：正常從裝置讀（LocalInput）；--bot 模式用合成的繞圈移動
## （headless 測試沒有輸入裝置，用它來驗證預測/和解）。
func _capture_input(tick: int, aim_origin: Vector2) -> InputFrame:
	if Session.bot_mode:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.move = Vector2(sin(tick * 0.05), cos(tick * 0.05))
		frame.aim = frame.move.normalized()
		frame.primary = tick % 90 < 2    # 偶爾揮劍，讓煙霧測試走到事件管線
		frame.utility = tick % 150 < 2   # 偶爾衝刺，驗證衝刺預測在延遲下收斂
		frame.special = tick % 240 < 2   # 偶爾抓鉤（有隊友才會真的發動）
		return frame
	return LocalInput.capture(tick, self, aim_origin)


## 伺服器 → 所有客戶端：全部玩家的位置 + 各自的輸入 ack。
func _broadcast_state(tick: int) -> void:
	var positions: Dictionary = {}
	var acks: Dictionary = {}
	for peer_id: int in player_states:
		positions[peer_id] = player_states[peer_id].pos
		acks[peer_id] = player_states[peer_id].get("ack_tick", -1)
	var enemies: Dictionary = {}
	for enemy_id: int in enemy_states:
		var enemy: Dictionary = enemy_states[enemy_id]
		enemies[enemy_id] = {"p": enemy.pos, "h": enemy.hp, "m": enemy.max_hp}
	var player_hp: Dictionary = {}
	var move_snaps: Dictionary = {}
	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		player_hp[peer_id] = [state.hp, state.max_hp, state.shield]
		# 完整移動快照（含衝刺狀態）：客戶端和解回滾需要，不能只給位置
		move_snaps[peer_id] = PlayerSim.snapshot_movement(state)
	var payload := {
		"t": tick, "p": positions, "a": acks, "e": enemies,
		"hp": player_hp, "mv": move_snaps, "w": wave_number,
	}
	NetworkManager.instance.send_or_delay(func() -> void: _receive_state.rpc(payload))


@rpc("authority", "unreliable_ordered")
func _receive_state(state_data: Dictionary) -> void:
	NetworkManager.instance.receive_or_delay(
		func() -> void: _apply_server_state(state_data)
	)


func _apply_server_state(state_data: Dictionary) -> void:
	last_server_state_tick = state_data.get("t", -1)
	ticks_since_server_state = 0
	var positions: Dictionary = state_data.get("p", {})
	var acks: Dictionary = state_data.get("a", {})
	var my_id := multiplayer.get_unique_id()

	for peer_id: int in positions:
		if not player_states.has(peer_id):
			_spawn_player(peer_id)
		if peer_id == my_id and prediction != null:
			# 自己：走和解（比對預測歷史，必要時用伺服器移動快照回滾重放）
			var state: Dictionary = player_states[peer_id]
			var server_snap: Dictionary = state_data.get("mv", {}).get(peer_id, {})
			if not server_snap.is_empty():
				prediction.reconcile(
					state, server_snap, acks.get(peer_id, -1), state.move_speed, ARENA_BOUNDS
				)
		else:
			# 別人：最新位置進模擬狀態（邏輯用），同時進插值緩衝（渲染用）
			var state: Dictionary = player_states[peer_id]
			state.pos = positions[peer_id]
			if state.has("interp"):
				state.interp.push_state(last_server_state_tick, positions[peer_id])

	# 狀態裡消失的玩家＝離開了，移除
	for peer_id: int in player_states.keys():
		if not positions.has(peer_id):
			_despawn_player(peer_id)

	# 玩家血量（低頻變動，直接照抄伺服器）
	var player_hp: Dictionary = state_data.get("hp", {})
	for peer_id: int in player_hp:
		if player_states.has(peer_id):
			player_states[peer_id].hp = player_hp[peer_id][0]
			player_states[peer_id].max_hp = player_hp[peer_id][1]
			player_states[peer_id].shield = player_hp[peer_id][2]

	wave_number = state_data.get("w", 0)
	_sync_enemies(state_data.get("e", {}))


## 客戶端：用伺服器狀態對齊本地的敵人鏡像（生成缺的、更新現有、移除消失的）。
func _sync_enemies(enemy_data: Dictionary) -> void:
	for enemy_id: int in enemy_data:
		var data: Dictionary = enemy_data[enemy_id]
		if not enemy_states.has(enemy_id):
			_create_enemy_entry(enemy_id, data.p)
		var enemy: Dictionary = enemy_states[enemy_id]
		enemy.pos = data.p
		enemy.hp = data.h
		enemy.max_hp = data.m
		if enemy.has("interp"):
			enemy.interp.push_state(last_server_state_tick, data.p)
	for enemy_id: int in enemy_states.keys():
		if not enemy_data.has(enemy_id):
			_despawn_enemy(enemy_id)


## 生成一位玩家：模擬狀態 + 場景節點，都以 peer_id 為 key。
func _spawn_player(peer_id: int) -> void:
	if player_states.has(peer_id):
		return
	var node: Node2D = PLAYER_SCENE.instantiate()
	# 出生點：中心往右排開，避免疊在一起（依現有人數排）
	node.position = ARENA_BOUNDS.get_center() + Vector2(48.0 * player_states.size(), 0)
	add_child(node)
	# 自己藍色、別人綠色（headless 伺服器沒有「自己」，全部算別人）
	var is_me := not Session.is_dedicated_server \
		and peer_id == multiplayer.get_unique_id()
	node.get_node("Body").color = COLOR_SELF if is_me else COLOR_OTHER
	player_states[peer_id] = {
		"move_speed": DEFAULT_MOVE_SPEED,
		"attack_speed": 1.0,   # 玩家屬性都是可被 modifier 改寫的變數（M3）
		"hp": 100.0,
		"max_hp": 100.0,
		"shield": 0.0,
		"last_input": null,
		"ack_tick": -1,
	}
	# 移動狀態欄位（pos、衝刺）由 PlayerSim 統一初始化
	PlayerSim.init_movement(player_states[peer_id], node.position)
	# 技能只存在於伺服器（權威）。目前人人都是劍士；角色選擇是 M6 的事。
	if NetworkManager.instance.is_server():
		player_states[peer_id].abilities = {
			"primary": SwordSweep.new(),
			"special": Grapple.new(),   # 隊友向技能（TargetKind.ALLY 的第一個實例）
		}
	player_nodes[peer_id] = node
	# 客戶端為「自己」建立預測器（伺服器端與 host 玩家不需要——他們就是權威）；
	# 為「別人」建立插值緩衝（伺服器端看到的就是權威位置，不需要）
	if not NetworkManager.instance.is_server():
		if is_me:
			prediction = ClientPrediction.new()
		else:
			player_states[peer_id].interp = RemoteInterpolation.new()
	print("[world] 生成玩家 peer %d" % peer_id)


## 伺服器：生成一隻敵人，回傳 enemy_id。
func _spawn_enemy(kind: String, pos: Vector2) -> int:
	var enemy_id := next_enemy_id
	next_enemy_id += 1
	_create_enemy_entry(enemy_id, pos)
	var enemy: Dictionary = enemy_states[enemy_id]
	enemy.kind = kind
	enemy.hp = ENEMY_HP
	enemy.max_hp = ENEMY_HP
	return enemy_id


## 建立敵人的狀態與節點（伺服器生成、客戶端同步共用）。
func _create_enemy_entry(enemy_id: int, pos: Vector2) -> void:
	var node: Node2D = ENEMY_SCENE.instantiate()
	node.position = pos
	add_child(node)
	enemy_states[enemy_id] = {
		"pos": pos,
		"hp": ENEMY_HP,
		"max_hp": ENEMY_HP,
		"kind": "chaser",
		"move_speed": EnemySim.CHASE_SPEED,   # 屬性放狀態裡，之後可被難度/敵種改寫
	}
	enemy_nodes[enemy_id] = node
	# 客戶端：敵人會動了，渲染走 100ms 延遲插值（和遠端玩家同一套）
	if not NetworkManager.instance.is_server():
		enemy_states[enemy_id].interp = RemoteInterpolation.new()


func _despawn_enemy(enemy_id: int) -> void:
	if enemy_nodes.has(enemy_id):
		enemy_nodes[enemy_id].queue_free()
	enemy_nodes.erase(enemy_id)
	enemy_states.erase(enemy_id)


## 伺服器：結算一筆傷害事件（M3 的事件匯流排會掛在這裡）。
func apply_damage(event: Dictionary) -> void:
	var enemy: Dictionary = enemy_states.get(event.target, {})
	if enemy.is_empty():
		return
	var died := Combat.apply_damage_to(enemy, event)
	pending_events.append({"k": "hurt", "t": event.target, "n": event.amount, "o": enemy.pos})
	if died:
		pending_events.append({"k": "enemy_died", "t": event.target, "o": enemy.pos})
		print("[world] 敵人 %d 被 peer %d 擊殺" % [event.target, event.source_peer])
		_despawn_enemy(event.target)


func _despawn_player(peer_id: int) -> void:
	if player_nodes.has(peer_id):
		player_nodes[peer_id].queue_free()
	player_nodes.erase(peer_id)
	player_states.erase(peer_id)
	print("[world] 移除玩家 peer %d" % peer_id)


func _on_peer_joined(peer_id: int) -> void:
	_spawn_player(peer_id)


func _on_peer_left(peer_id: int) -> void:
	_despawn_player(peer_id)


func _on_server_lost() -> void:
	print("[world] 與伺服器斷線，回主選單")
	get_tree().change_scene_to_file("res://main.tscn")


## 預告特效的時間座標：伺服器＝權威 tick；客戶端＝插值渲染時鐘——
## 讓危險圓圈的進度和「延遲 100ms 渲染的敵人」對得上。
func telegraph_clock() -> float:
	if NetworkManager.instance.is_server():
		return float(current_tick)
	return interp_render_tick


## 客戶端每 tick：推進插值渲染時鐘。
## 時鐘以「伺服器 tick」為座標，目標永遠是最新狀態再往回 INTERP_DELAY_TICKS。
## 每 tick 前進 1，外加小幅追蹤目標——吸收兩端時鐘的微小漂移；
## 脫節太大（長卡頓）就直接跳過去。
func _advance_interp_clock() -> void:
	if last_server_state_tick < 0:
		return
	var target := float(last_server_state_tick - INTERP_DELAY_TICKS)
	if interp_render_tick < 0.0 or absf(target - interp_render_tick) > INTERP_SNAP_LIMIT:
		interp_render_tick = target
		return
	interp_render_tick += 1.0 + clampf((target - interp_render_tick) * 0.1, -0.5, 0.5)


## 視覺更新（_process）：把狀態抄到節點上。純表現，不碰任何邏輯。
##   自己　：模擬位置 + 和解的視覺偏移（平滑滑回，不瞬移）
##   別人　：插值緩衝取樣（落後 100ms 的平滑位置）
##   伺服器：權威位置直接抄
func _process(_delta: float) -> void:
	# physics fraction：在兩個 physics tick 之間再細分，高更新率螢幕也平滑
	var fraction := Engine.get_physics_interpolation_fraction()
	for peer_id: int in player_states:
		var state: Dictionary = player_states[peer_id]
		var node: Node2D = player_nodes[peer_id]
		if state.has("interp"):
			var sampled: Variant = state.interp.sample(interp_render_tick + fraction)
			if sampled != null:
				node.position = sampled
		else:
			var render_pos: Vector2 = state.pos
			if prediction != null and peer_id == multiplayer.get_unique_id():
				render_pos += prediction.visual_error
			node.position = render_pos
		node.update_hp(state.hp / maxf(state.max_hp, 1.0))
		node.update_shield(state.get("shield", 0.0) / PlayerSim.SHIELD_CAP)

	# 敵人：位置與血條。客戶端吃插值（同遠端玩家），伺服器直接抄權威位置。
	for enemy_id: int in enemy_states:
		var enemy: Dictionary = enemy_states[enemy_id]
		var enemy_node: Node2D = enemy_nodes[enemy_id]
		if enemy.has("interp"):
			var sampled: Variant = enemy.interp.sample(interp_render_tick + fraction)
			enemy_node.position = sampled if sampled != null else enemy.pos
		else:
			enemy_node.position = enemy.pos
		enemy_node.update_hp(enemy.hp / maxf(enemy.max_hp, 1.0))

## 戰鬥核心：傷害事件的建立與套用（M2 步驟 2）。
##
## 架構要求（docs/01「為後續里程碑預留」）：
## 所有傷害事件都攜帶額外欄位——trigger_coefficient（觸發係數）與
## recursion_depth（遞迴深度）。M3 的道具觸發系統會讀寫這兩個欄位；
## 現在就放進事件結構，之後才不用把每個呼叫點翻掉重寫。
##
## 純函式，不碰節點，可單獨 headless 測試。
class_name Combat
extends RefCounted


## 建立一筆傷害事件。時間戳一律用 tick（核心原則 1）。
static func make_damage_event(
	source_peer: int,
	target_id: int,
	amount: float,
	tick: int,
	trigger_coefficient: float = 1.0,
	recursion_depth: int = 0
) -> Dictionary:
	return {
		"source_peer": source_peer,
		"target": target_id,
		"amount": amount,
		"tick": tick,
		"trigger_coefficient": trigger_coefficient,   # M3：慢速攻擊觸發符文的機率補償
		"recursion_depth": recursion_depth,           # M3：連鎖觸發的遞迴防護
	}


## 把傷害套用到一個帶 hp 的狀態上（敵人或未來的玩家）。
## 回傳是否因此死亡。hp 不會低於 0。
static func apply_damage_to(state: Dictionary, event: Dictionary) -> bool:
	if state.get("hp", 0.0) <= 0.0:
		return false   # 已經死了，不重複結算
	state.hp = maxf(0.0, state.hp - event.amount)
	return state.hp <= 0.0


## 護盾優先吸收的傷害套用（玩家用）。護盾扣完剩餘才進血量。
## 回傳是否因此死亡。
static func apply_damage_with_shield(state: Dictionary, event: Dictionary) -> bool:
	if state.get("hp", 0.0) <= 0.0:
		return false
	var remaining: float = event.amount
	var shield: float = state.get("shield", 0.0)
	var absorbed := minf(shield, remaining)
	state.shield = shield - absorbed
	remaining -= absorbed
	if remaining <= 0.0:
		return false
	state.hp = maxf(0.0, state.hp - remaining)
	return state.hp <= 0.0

## 單一 tick 的玩家輸入快照——輸入抽象層（核心原則 3）。
##
## 角色的模擬函式只接受 InputFrame，對輸入來源一無所知。
## 來源可以是：本地鍵盤／手把（LocalInput）、網路封包（步驟 3 起）、未來的 AI。
##
## 欄位刻意用通用名稱（primary/secondary/utility/special），不用 attack/dodge
## 這種綁定特定動作的名字——三個職業的技能內容完全不同。
class_name InputFrame
extends RefCounted

## 這份輸入屬於哪個 tick（時間單位一律是 tick 編號，不用秒數）
var tick: int = 0

## 移動方向，長度 0～1（搖桿可以推一半）
var move: Vector2 = Vector2.ZERO

## 瞄準方向（單位向量），M2 的攻擊會用到
var aim: Vector2 = Vector2.RIGHT

var primary: bool = false
var secondary: bool = false
var utility: bool = false
var special: bool = false
var interact: bool = false

## 網路傳輸時，五個按鍵壓成一個 bitmask 整數，省頻寬
const BIT_PRIMARY := 1
const BIT_SECONDARY := 2
const BIT_UTILITY := 4
const BIT_SPECIAL := 8
const BIT_INTERACT := 16


## 序列化成 Dictionary（給 RPC 用）。key 刻意取短，減少封包大小。
func to_dict() -> Dictionary:
	var buttons: int = 0
	if primary:
		buttons |= BIT_PRIMARY
	if secondary:
		buttons |= BIT_SECONDARY
	if utility:
		buttons |= BIT_UTILITY
	if special:
		buttons |= BIT_SPECIAL
	if interact:
		buttons |= BIT_INTERACT
	return {"t": tick, "m": move, "a": aim, "b": buttons}


## 從 Dictionary 還原（收到 RPC 時用）。缺欄位時給安全預設值，不炸。
static func from_dict(data: Dictionary) -> InputFrame:
	var frame := InputFrame.new()
	frame.tick = data.get("t", 0)
	frame.move = data.get("m", Vector2.ZERO)
	frame.aim = data.get("a", Vector2.RIGHT)
	var buttons: int = data.get("b", 0)
	frame.primary = buttons & BIT_PRIMARY != 0
	frame.secondary = buttons & BIT_SECONDARY != 0
	frame.utility = buttons & BIT_UTILITY != 0
	frame.special = buttons & BIT_SPECIAL != 0
	frame.interact = buttons & BIT_INTERACT != 0
	return frame

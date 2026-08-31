## 兩種堆疊公式（M3）——整個道具系統的數學地基（docs/03）。
##
## 判斷規則：疊到極限會讓遊戲「更誇張」→ 線性；
## 會讓遊戲「停止運作」（無敵、無限資源、100% 機率）→ 遞減。
class_name Stacking
extends RefCounted


## 線性堆疊：給玩家失控的爽感。
## 用於：傷害、攻速、投射物數量、爆炸範圍、觸發次數。
static func linear(base: float, per_stack: float, count: int) -> float:
	return base + per_stack * count


## 遞減堆疊：永遠到不了 1.0，守住遊戲不會停止運作。
## 用於：暴擊率、傷害減免、格擋率、冷卻縮減——任何「機率」與「減免」。
static func hyperbolic(k: float, count: int) -> float:
	return 1.0 - 1.0 / (1.0 + k * count)

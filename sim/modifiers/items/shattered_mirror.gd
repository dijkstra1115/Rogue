## 碎裂之鏡（紫・詛咒）：傷害 ×2，最大生命 −50%。每層再乘一次。
## 詛咒原型——高風險高回報，唯一會讓玩家猶豫要不要撿的類別（docs/03 原型 6）。
##
## priority 100：乘法要在所有加法（磨刀石等）之後套用，
## 否則「先乘後加」會讓加法道具吃不到詛咒的倍率。
class_name ShatteredMirror
extends Modifier


func _init() -> void:
	id = "shattered_mirror"
	display_name = "碎裂之鏡"
	rarity = "purple"
	priority = 100


func modify_stats(stats: Dictionary) -> void:
	stats.damage_mult *= pow(2.0, stack_count)
	stats.max_hp = maxf(1.0, stats.max_hp * pow(0.5, stack_count))

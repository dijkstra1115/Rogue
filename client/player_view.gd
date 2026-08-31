## 玩家的佔位視覺（player.tscn 根節點）：方塊＋頭上血條。純表現層。
extends Node2D


## 依血量比例縮放血條（0.0～1.0）
func update_hp(fraction: float) -> void:
	$HpBar.scale.x = clampf(fraction, 0.0, 1.0)


## 依護盾比例（相對護盾上限）縮放護盾條
func update_shield(fraction: float) -> void:
	$ShieldBar.scale.x = clampf(fraction, 0.0, 1.0)

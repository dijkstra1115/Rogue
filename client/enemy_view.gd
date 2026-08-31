## 敵人的佔位視覺（enemy.tscn 根節點）：方塊＋頭上血條。純表現層。
extends Node2D

const HP_BAR_WIDTH := 32.0


## 依血量比例縮放血條（0.0～1.0）
func update_hp(fraction: float) -> void:
	$HpBar.scale.x = clampf(fraction, 0.0, 1.0)

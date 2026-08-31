## 本地輸入來源：整個專案「唯一」允許讀鍵盤／滑鼠／手把的地方（核心原則 3）。
##
## 每 tick 呼叫一次 capture()，把當下的裝置狀態拍成一張 InputFrame。
## 模擬層拿到的永遠是 InputFrame，不知道它來自哪裡。
class_name LocalInput
extends RefCounted

## 右搖桿要推超過這個量才算在瞄準（否則用滑鼠方向）
const AIM_STICK_DEADZONE := 0.3


## world：用來取得滑鼠的世界座標；player_pos：算滑鼠瞄準方向的原點。
static func capture(tick: int, world: Node2D, player_pos: Vector2) -> InputFrame:
	var frame := InputFrame.new()
	frame.tick = tick
	frame.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 瞄準：右搖桿優先；沒推的話用「玩家 → 滑鼠」的方向
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if stick.length() > AIM_STICK_DEADZONE:
		frame.aim = stick.normalized()
	else:
		var to_mouse := world.get_global_mouse_position() - player_pos
		if to_mouse.length() > 1.0:
			frame.aim = to_mouse.normalized()

	frame.primary = Input.is_action_pressed("primary")
	frame.secondary = Input.is_action_pressed("secondary")
	frame.utility = Input.is_action_pressed("utility")
	frame.special = Input.is_action_pressed("special")
	frame.interact = Input.is_action_pressed("interact")
	return frame

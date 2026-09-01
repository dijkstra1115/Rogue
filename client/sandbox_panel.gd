## 測試模式面板（M3 步驟 2）——docs/03 第七節：「早點做，你會用它幾百次」。
##
## 右側面板：給道具（任意堆疊）、清除道具、弓手節奏模擬、
## 即時 DPS／每秒觸發／特效數量。只在 Session.sandbox_mode 時由 game_world 掛上。
## 純表現層＋直接呼叫伺服器 API（測試模式一定是本機 host，自己就是伺服器）。
extends CanvasLayer

var world: Node2D = null

var _stats_label: Label
var _stack_labels: Dictionary = {}   # item_id -> Label
var _archer_button: Button


func _ready() -> void:
	layer = 20
	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_TOP_RIGHT
	panel.position = Vector2(1020, 40)
	panel.custom_minimum_size = Vector2(240, 0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "測試模式"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	# 每個註冊道具一列：名稱×層數 [+1] [+5]
	for item_id: String in ItemRegistry.all_ids():
		var sample := ItemRegistry.create(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_label := Label.new()
		name_label.text = sample.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var stack_label := Label.new()
		stack_label.text = "×0"
		_stack_labels[item_id] = stack_label
		row.add_child(stack_label)
		row.add_child(_make_grant_button(item_id, 1))
		row.add_child(_make_grant_button(item_id, 5))
		box.add_child(row)

	var clear_button := Button.new()
	clear_button.text = "清除道具"
	clear_button.pressed.connect(_on_clear_pressed)
	box.add_child(clear_button)

	_archer_button = Button.new()
	_archer_button.toggle_mode = true
	_archer_button.text = "弓手節奏模擬：關"
	_archer_button.toggled.connect(_on_archer_toggled)
	box.add_child(_archer_button)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_stats_label)


func _make_grant_button(item_id: String, count: int) -> Button:
	var button := Button.new()
	button.text = "+%d" % count
	button.pressed.connect(
		func() -> void:
			world.grant_item(multiplayer.get_unique_id(), ItemRegistry.create(item_id, count))
	)
	return button


func _on_clear_pressed() -> void:
	var state: Dictionary = world.player_states[multiplayer.get_unique_id()]
	state.mods = ModifierStack.new()
	world.recompute_stats(multiplayer.get_unique_id())


## 弓手節奏模擬：攻速 ×10、觸發係數 0.25（docs/03 驗收第 2 條的替身，弓手 M6 才做）
func _on_archer_toggled(pressed: bool) -> void:
	world.sandbox_attack_speed_override = 10.0 if pressed else 0.0
	world.sandbox_proc_coefficient_override = 0.25 if pressed else -1.0
	world.recompute_stats(multiplayer.get_unique_id())
	_archer_button.text = "弓手節奏模擬：開" if pressed else "弓手節奏模擬：關"


func _process(_delta: float) -> void:
	var my_id := multiplayer.get_unique_id()
	var state: Dictionary = world.player_states.get(my_id, {})
	if not state.is_empty() and state.has("mods"):
		for item_id: String in _stack_labels:
			_stack_labels[item_id].text = "×%d" % state.mods.stack_count_of(item_id)
	_stats_label.text = "DPS: %.0f\n觸發/秒: %.1f\n特效數: %d\n傷害倍率: %.2f  攻速: %.1f" % [
		world.sandbox_dps(),
		world.sandbox_procs_per_sec(),
		get_tree().get_node_count_in_group("fx"),
		state.get("damage_mult", 1.0),
		state.get("attack_speed", 1.0),
	]

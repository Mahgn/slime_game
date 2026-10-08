extends CanvasLayer
class_name SlimeKeepersRunHUD

const TITLE_FONT: Font = preload("res://assets/ash-vault/CormorantGaramond.ttf")
const INK := Color("111c20")
const PAPER := Color("eee4d0")
const MUTED := Color("a6b8b5")
const GOLD := Color("e8c48a")
const GEL := Color("64d9c6")
const ABILITIES: Array[AbilityDefinition] = [SlimeController.ABILITY, SlimeController.SHELL, SlimeController.SPIKES]

var loadout_open := false

var _route: Node
var _player: SlimeController
var _combat: SlimeCombatRuntime
var _root: Control
var _chrome: Control
var _title: Label
var _objective: Label
var _navigation: Label
var _time: Label
var _encounter: Label
var _health: Label
var _health_bar: ProgressBar
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_bars: Array[ProgressBar] = []
var _hint: Label
var _notice: Label
var _notice_left := 0.0
var _absorb_progress := 0.0
var _loadout: ColorRect
var _loadout_items: VBoxContainer
var _loadout_hint: Label
var _slot_buttons: Array[Button] = []
var _selected_slot := 1
var _ending: ColorRect
var _ending_title: Label
var _ending_body: Label
var _ending_stats: Label
var _retry: Button
var _ending_open := false


func setup(route: Node) -> void:
	assert(_route == null, "Run HUD must be set up once")
	_route = route
	_player = route.get("player") as SlimeController
	_combat = route.get("combat") as SlimeCombatRuntime
	assert(is_instance_valid(_player) and is_instance_valid(_combat))
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_loadout()
	_build_ending()
	_connect_player_signals()
	_refresh()


func _process(delta: float) -> void:
	if not is_instance_valid(_route):
		return
	_sync_actors()
	if not is_instance_valid(_player) or not is_instance_valid(_combat):
		return
	# The base pause/settings menu lives on layer 0 and must keep mouse access.
	var base_pause := _base_pause_open()
	if base_pause and loadout_open:
		close_loadout()
	_root.visible = not base_pause
	if not get_tree().paused:
		_notice_left = maxf(0.0, _notice_left - delta)
	_notice.visible = _notice_left > 0.0 and not loadout_open and not _ending_open
	_notice.modulate.a = minf(1.0, _notice_left * 2.0)
	_refresh()


func _refresh() -> void:
	var room: Dictionary = _route.call("current_room")
	var room_id := String(_route.get("room_id"))
	var cleared: Dictionary = _route.get("cleared")
	var enemies: Array = _route.call("alive_enemies")
	_title.text = String(room.get("title", "Путь через котельные"))
	_objective.text = String(room.get("subtitle", "Найди путь наверх, к своим"))
	if (String(room.get("reward", "")) == "core" and _player.unlocked_slots >= 2) or (String(room.get("reward", "")) == "shell" and _player.has_learned(&"elastic_shell")):
		_objective.text = String(room.get("lore", "Здесь больше ничего не осталось. Пора идти дальше."))
	_time.text = "%s   ·   Комнаты %d/%d" % [_format_time(float(_route.get("elapsed_seconds"))), _visited_main_rooms(), _main_room_count()]
	if not enemies.is_empty():
		_encounter.text = "Группа %d   ·   Врагов: %d" % [maxi(1, int(_route.get("wave_index"))), enemies.size()]
		_encounter.add_theme_color_override("font_color", GOLD)
	elif bool(cleared.get(room_id, false)) or bool(room.get("secret", false)):
		_encounter.text = "Можно осмотреться"
		_encounter.add_theme_color_override("font_color", GEL)
	else:
		_encounter.text = "Осмотрись перед следующим боем"
		_encounter.add_theme_color_override("font_color", MUTED)
	_navigation.text = _navigation_text(room)
	_health.text = "ЗДОРОВЬЕ   %d / %d" % [_player.health, SlimeController.MAX_HEALTH]
	_health_bar.value = _player.health
	for index in range(2):
		var slot := index + 1
		_slot_panels[index].visible = slot <= _player.unlocked_slots
		var ability_id := _player.get_slot_ability(slot)
		var key := "ПКМ" if slot == 1 else "Q"
		var definition := _definition(ability_id)
		if definition == null:
			_slot_labels[index].text = "%s   ·   Пустой слот\nУдерживай E у останков" % key
			_slot_bars[index].value = 0.0
			continue
		var remaining := _player.cooldown_remaining(ability_id)
		var state := "Готов" if remaining <= 0.0 else "Перезарядка %.1f с" % remaining
		_slot_labels[index].text = "%s   ·   %s\n%s" % [key, definition.display_name, state]
		_slot_bars[index].value = 1.0 - clampf(remaining / maxf(0.01, definition.player_cooldown), 0.0, 1.0)
	_hint.text = String(_route.get("interaction_hint"))
	if _absorb_progress > 0.0:
		_hint.text = "Поглощение %d%% · удерживай E" % roundi(_absorb_progress * 100.0)
	elif _hint.text.is_empty():
		_hint.text = "Побеждай врагов и поглощай их приёмы"


func _build_hud() -> void:
	_root = Control.new()
	_root.name = "RunHUDRoot"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome = Control.new()
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chrome)
	_add_shade(false)
	_add_shade(true)
	_title = _label(_chrome, "", 32, GOLD)
	_place(_title, Vector2(22, 13), Vector2(690, 43))
	_title.add_theme_font_override("font", TITLE_FONT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective = _label(_chrome, "", 16, PAPER)
	_place(_objective, Vector2(24, 56), Vector2(680, 44))
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_navigation = _label(_chrome, "", 14, MUTED)
	_place(_navigation, Vector2(24, 101), Vector2(780, 23))
	_navigation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var status := VBoxContainer.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -340
	status.offset_right = -24
	status.offset_top = 23
	status.offset_bottom = 82
	status.add_theme_constant_override("separation", 9)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(status)
	_time = _label(status, "", 16, PAPER)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_encounter = _label(status, "", 15, MUTED)
	_encounter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cards := HBoxContainer.new()
	cards.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cards.offset_left = 24
	cards.offset_right = 790
	cards.offset_top = -137
	cards.offset_bottom = -64
	cards.add_theme_constant_override("separation", 10)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(cards)
	var health_box := _card(cards, 205)
	_health = _label(health_box, "", 15, PAPER)
	_health_bar = _bar(health_box, SlimeController.MAX_HEALTH, GEL)
	_health_bar.custom_minimum_size.y = 9
	var health_note := _label(health_box, "ЛКМ  ·  Слизевой хлыст", 13, MUTED)
	health_note.name = "PrimaryAttackLabel"
	for index in range(2):
		var box := _card(cards, 245)
		_slot_panels.append(box.get_parent().get_parent() as PanelContainer)
		_slot_labels.append(_label(box, "", 15, PAPER))
		_slot_bars.append(_bar(box, 1.0, GOLD))
	_hint = _label(_chrome, "", 16, GOLD)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 24
	_hint.offset_right = -24
	_hint.offset_top = -54
	_hint.offset_bottom = -31
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var controls := _label(_chrome, "WASD — движение   ·   Пробел: удержать и отпустить — прыжок   ·   ЛКМ — хлыст   ·   E — действие   ·   Tab — навыки   ·   Esc — пауза", 14, MUTED)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 24
	controls.offset_right = -24
	controls.offset_top = -28
	controls.offset_bottom = -7
	controls.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_notice = _label(_chrome, "", 16, GOLD)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_notice.offset_left = -485
	_notice.offset_right = -25
	_notice.offset_top = -145
	_notice.offset_bottom = -68
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.025, 0.95))
	_notice.add_theme_constant_override("shadow_offset_x", 1)
	_notice.add_theme_constant_override("shadow_offset_y", 2)
	_notice.hide()


func _build_loadout() -> void:
	_loadout = _overlay("LoadoutOverlay")
	var box := _modal_box(_loadout, 590, 500)
	var heading := _label(box, "Поглощённые приёмы", 32, GOLD)
	heading.add_theme_font_override("font", TITLE_FONT)
	_label(box, "Выбери слот, затем изученный приём. Игра на паузе.", 16, MUTED)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	box.add_child(slots)
	for index in range(2):
		var slot := index + 1
		var button := _button(slots, "Слот 1 · ПКМ" if slot == 1 else "Слот 2 · Q", _select_slot.bind(slot))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot_buttons.append(button)
	_loadout_items = VBoxContainer.new()
	_loadout_items.add_theme_constant_override("separation", 8)
	box.add_child(_loadout_items)
	_loadout_hint = _label(box, "", 15, MUTED)
	_loadout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := _button(box, "Вернуться в игру   ·   Tab / Esc", close_loadout)
	close.name = "CloseLoadoutButton"
	_loadout.hide()


func toggle_loadout() -> void:
	if loadout_open:
		close_loadout()
		return
	if _ending_open or bool(_route.get("finished")) or _base_pause_open() or get_tree().paused:
		return
	if not bool(_route.call("room_is_safe")):
		show_notice("Выбирать приёмы можно после зачистки комнаты")
		return
	_player.cancel_absorb_for_pause()
	_player.clear_action_buffer()
	_selected_slot = mini(_selected_slot, _player.unlocked_slots)
	loadout_open = true
	_refresh_loadout()
	_loadout.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_slot_buttons[_selected_slot - 1].grab_focus()


func close_loadout() -> void:
	if not loadout_open:
		return
	loadout_open = false
	_loadout.hide()
	_player.cancel_absorb_for_pause()
	_player.clear_action_buffer()
	if not _ending_open and not _base_pause_open() and not bool(_route.get("finished")):
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_refresh_loadout()


func _refresh_loadout() -> void:
	for index in range(_slot_buttons.size()):
		_slot_buttons[index].visible = index < _player.unlocked_slots
		_slot_buttons[index].text = ("Слот 1 · ПКМ" if index == 0 else "Слот 2 · Q") + ("  — выбран" if _selected_slot == index + 1 else "")
	for child in _loadout_items.get_children():
		_loadout_items.remove_child(child)
		child.queue_free()
	var known_count := 0
	for definition in ABILITIES:
		if not _player.has_learned(definition.ability_id):
			continue
		known_count += 1
		var equipped := _player.get_slot_ability(_selected_slot) == definition.ability_id
		var other_slot := _player.get_slot_ability(3 - _selected_slot) == definition.ability_id
		var suffix := "  ·  Выбран" if equipped else ("  ·  В другом слоте" if other_slot else "")
		var button := _button(_loadout_items, "%s%s\n%s" % [definition.display_name, suffix, definition.description], _equip.bind(definition.ability_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 64
		button.disabled = equipped or other_slot
	_loadout_hint.text = "Победи врага и удерживай E у его останков, чтобы изучить приём." if known_count == 0 else "Перезарядка сохраняется при смене слота. Один приём занимает один слот."
	var current := _player.get_slot_ability(_selected_slot)
	if current != &"":
		_button(_loadout_items, "Освободить выбранный слот", _equip.bind(&""))


func _equip(ability_id: StringName) -> void:
	if not loadout_open or not bool(_route.call("room_is_safe")):
		return
	if _combat.equip_ability(_selected_slot, ability_id):
		_refresh_loadout()
		_refresh()
		_slot_buttons[_selected_slot - 1].grab_focus()


func show_notice(message: String) -> void:
	if not is_instance_valid(_notice):
		return
	if _ending_open:
		_ending_body.text = message
	_notice.text = message
	_notice_left = 4.5
	_notice.modulate.a = 1.0
	_notice.visible = not loadout_open and not _ending_open


func _build_ending() -> void:
	_ending = _overlay("RunEndingOverlay")
	var box := _modal_box(_ending, 550, 450)
	_ending_title = _label(box, "", 38, GOLD)
	_ending_title.add_theme_font_override("font", TITLE_FONT)
	_ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_body = _label(box, "", 18, PAPER)
	_ending_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ending_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_stats = _label(box, "", 18, MUTED)
	_ending_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_stats.custom_minimum_size.y = 65
	_retry = _button(box, "Повторить комнату", _run_action.bind(&"retry_room"))
	_retry.name = "RetryRoomButton"
	var restart := _button(box, "Новый заход", _run_action.bind(&"restart_run"))
	restart.name = "RestartRunButton"
	var menu := _button(box, "В меню", _run_action.bind(&"return_to_menu"))
	menu.name = "RunMenuButton"
	_ending.hide()


func show_ending(victory: bool) -> void:
	_ending_open = true
	close_loadout()
	_player.cancel_absorb_for_pause()
	_player.clear_action_buffer()
	_ending_title.text = "Ещё ближе к своим" if victory else "Попробуем ещё раз"
	_ending_body.text = "Над котельными пахнет свежим воздухом.\nПуть наверх продолжается." if victory else "Комната начнётся с её входной точки.\nВернутся здоровье и приёмы на момент входа."
	var found: Dictionary = _route.get("secrets_found")
	var cleared: Dictionary = _route.get("cleared")
	var main_cleared := 0
	var rooms: Dictionary = _route.get("rooms")
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		if not bool(room.get("secret", false)) and bool(cleared.get(room_id, false)):
			main_cleared += 1
	_ending_stats.text = "Время захода  %s\nПройдено комнат  %d/%d   ·   Секретов найдено  %d" % [_format_time(float(_route.get("elapsed_seconds"))), main_cleared, _main_room_count(), found.size()]
	_retry.visible = not victory
	_chrome.hide()
	_ending.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not victory:
		_retry.grab_focus()
	else:
		(_ending.find_child("RestartRunButton", true, false) as Button).grab_focus()


func hide_ending() -> void:
	_ending_open = false
	_ending.hide()
	_chrome.show()
	_notice_left = 0.0
	_absorb_progress = 0.0
	_sync_actors()
	_refresh()


func rebind_runtime() -> void:
	_sync_actors()
	_absorb_progress = 0.0
	_refresh()


func _run_action(method: StringName) -> void:
	_notice_left = 0.0
	_absorb_progress = 0.0
	_player.clear_action_buffer()
	_route.call(method)
	# Successful scene changes detach the route. Deferred room retries keep
	# the result visible until the route restores its snapshot and calls us.
	if is_instance_valid(_route) and _route.is_inside_tree():
		get_tree().paused = true


func _sync_actors() -> void:
	var current_player := _route.get("player") as SlimeController
	_combat = _route.get("combat") as SlimeCombatRuntime
	if is_instance_valid(_player) and current_player == _player:
		return
	if is_instance_valid(_player):
		if _player.ability_unlocked.is_connected(_on_ability_unlocked):
			_player.ability_unlocked.disconnect(_on_ability_unlocked)
		if _player.absorb_progress_changed.is_connected(_on_absorb_progress):
			_player.absorb_progress_changed.disconnect(_on_absorb_progress)
	_player = current_player
	_absorb_progress = 0.0
	if is_instance_valid(_player):
		_connect_player_signals()


func _connect_player_signals() -> void:
	if not _player.ability_unlocked.is_connected(_on_ability_unlocked):
		_player.ability_unlocked.connect(_on_ability_unlocked)
	if not _player.absorb_progress_changed.is_connected(_on_absorb_progress):
		_player.absorb_progress_changed.connect(_on_absorb_progress)


func _on_ability_unlocked(ability_id: StringName) -> void:
	var definition := _definition(ability_id)
	if definition != null:
		show_notice("Изучен приём: %s\nTab — выбрать вне боя" % definition.display_name)


func _on_absorb_progress(progress: float, _source: Node3D) -> void:
	_absorb_progress = progress


func _navigation_text(room: Dictionary) -> String:
	if bool(room.get("secret", false)):
		return "Назад — через нижний проход"
	if String(room.get("theme", "")) == "summit":
		return "Светлая арка — путь наверх"
	var titles: PackedStringArray = []
	var rooms: Dictionary = _route.get("rooms")
	var exits: Array = room.get("exits", [])
	for destination in exits:
		var target: Dictionary = rooms.get(String(destination), {})
		if not target.is_empty() and not bool(target.get("secret", false)):
			titles.append(String(target.get("title", "Проход")))
	if titles.size() > 1:
		return "Два пути: %s   /   %s" % [titles[0], titles[1]]
	if titles.size() == 1:
		return "Дальше: %s" % titles[0]
	return "Осмотрись у арок — рядом появится подсказка действия"


func _main_room_count() -> int:
	var count := 0
	var rooms: Dictionary = _route.get("rooms")
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		if not bool(room.get("secret", false)):
			count += 1
	return count


func _visited_main_rooms() -> int:
	var count := 0
	var rooms: Dictionary = _route.get("rooms")
	var visited: Dictionary = _route.get("visited")
	for room_id in visited:
		var room: Dictionary = rooms.get(room_id, {})
		if not room.is_empty() and not bool(room.get("secret", false)) and bool(visited[room_id]):
			count += 1
	return count


func _base_pause_open() -> bool:
	var pause_menu := _route.get_node_or_null("HUD/PauseMenu") as Control
	return is_instance_valid(pause_menu) and pause_menu.is_visible_in_tree()


func _format_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%d:%02d" % [floori(float(total) / 60.0), total % 60]


func _definition(ability_id: StringName) -> AbilityDefinition:
	for definition in ABILITIES:
		if definition.ability_id == ability_id:
			return definition
	return null


func _label(parent: Node, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _place(control: Control, at: Vector2, dimensions: Vector2) -> void:
	control.position = at
	control.size = dimensions


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _card(parent: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.085, 0.095, 0.94), Color("3c5656")))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	return box


func _bar(parent: Node, maximum: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maximum
	bar.step = 0.01
	bar.custom_minimum_size.y = 5
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("23383b")
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 43
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(Color("223536"), Color("496160")))
	button.add_theme_stylebox_override("hover", _style(Color("314949"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("1a2d2e"), GEL))
	button.add_theme_stylebox_override("disabled", _style(INK, Color("314647")))
	var focus := _style(Color(0, 0, 0, 0), GOLD)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _overlay(node_name: String) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = node_name
	overlay.color = Color(0.015, 0.035, 0.045, 0.88)
	_root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	return overlay


func _modal_box(parent: Control, width: float, height: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	var style := _style(Color("14282d"), Color("6d7770"))
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	panel.add_child(box)
	return box


func _add_shade(bottom: bool) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.015, 0.025, 0.03, 0.94), Color(0.015, 0.025, 0.03, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 1) if bottom else Vector2.ZERO
	texture.fill_to = Vector2.ZERO if bottom else Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	shade.offset_top = -166 if bottom else 0
	shade.offset_bottom = 0 if bottom else 142

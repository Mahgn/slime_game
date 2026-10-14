extends "res://scripts/keepers/keepers_world_hud.gd"

var map_open: bool = false
var _map: ColorRect
var _map_copy: Label


func _build_hud() -> void:
	super._build_hud()
	_map = _overlay("DungeonMap")
	var box: VBoxContainer = _modal_box(_map, 660, 440)
	var title: Label = _label(box, "Путь к своим", 32, GOLD)
	title.add_theme_font_override("font", TITLE_FONT)
	_map_copy = _label(box, "", 20, PAPER)
	_map_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_copy.text = "Выводные залы\n    ↙                         ↘\nГрибные сады   ↔   Водосбор\n    ↘                         ↙\nСлужебные галереи\n                ↓\nВерхний рубеж → Поверхность"
	_button(box, "Вернуться в игру · M / Esc", close_map)
	_map.hide()


func _refresh() -> void:
	super._refresh()
	var room: Dictionary = _route.call("current_room")
	_title.text = "%s · %s" % [room.get("region_title", ""), room.get("title", "")]
	_time.text = "Попытка %d   ·   %s   ·   M — карта" % [int(_route.get("attempt_index"))+1,_format_time(float(_route.get("elapsed_seconds")))]
	var hero: SlimeDungeonPlayer = _player as SlimeDungeonPlayer
	if hero == null:
		return
	for index: int in range(2):
		var ability_id: StringName = hero.get_slot_ability(index+1)
		if ability_id != &"":
			var definition: AbilityDefinition = _definition(ability_id)
			var state: String = "Готов" if hero.cooldown_remaining(ability_id)<=0 else "Перезарядка %.1f с" % hero.cooldown_remaining(ability_id)
			_slot_labels[index].text = "%s · %s · ур. %d\n%s" % ["ПКМ" if index==0 else "Q",definition.display_name,hero.get_ability_level(ability_id),state]


func _definition(ability_id: StringName) -> AbilityDefinition:
	return _player.get_ability_definition(ability_id) if is_instance_valid(_player) else null


func _refresh_loadout() -> void:
	for index: int in _slot_buttons.size():
		_slot_buttons[index].visible = index < _player.unlocked_slots
		_slot_buttons[index].text = ("Слот 1 · ПКМ" if index==0 else "Слот 2 · Q") + (" — выбран" if _selected_slot==index+1 else "")
	for child: Node in _loadout_items.get_children():
		_loadout_items.remove_child(child)
		child.queue_free()
	var hero: SlimeDungeonPlayer = _player as SlimeDungeonPlayer
	var count: int = 0
	for ability_id: StringName in hero.get_known_abilities():
		if not hero.has_learned(ability_id):
			continue
		count += 1
		var definition: AbilityDefinition = hero.get_ability_definition(ability_id)
		var selected: bool = hero.get_slot_ability(_selected_slot) == ability_id
		var other: bool = hero.get_slot_ability(3-_selected_slot) == ability_id
		var button: Button = _button(_loadout_items, "%s · ур. %d\n%s" % [definition.display_name,hero.get_ability_level(ability_id),definition.description],_equip.bind(ability_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 68
		button.disabled = selected or other
	_loadout_hint.text = "Поглотить останки — удерживать E. Можно пройти мимо." if count==0 else "Повторное поглощение усиливает приём в этой попытке."
	if hero.get_slot_ability(_selected_slot) != &"":
		_button(_loadout_items,"Освободить выбранный слот",_equip.bind(&""))


func _on_ability_unlocked(ability_id: StringName) -> void:
	var hero: SlimeDungeonPlayer = _player as SlimeDungeonPlayer
	var definition: AbilityDefinition = hero.get_ability_definition(ability_id)
	show_notice("%s · уровень %d\nTab — выбрать приём вне боя" % [definition.display_name,hero.get_ability_level(ability_id)])


func show_ending(won: bool) -> void:
	close_map()
	super.show_ending(won)
	_ending_title.text = "Путь домой открыт" if won else "Мастер готовит новую попытку"
	_ending_body.text = "Испытание пройдено. Привязка снята.\nТеперь можно вернуться к своей семье." if won else "Ты вернёшься в распределительный зал.\nПриёмы придётся собрать заново.\nЗнания о подземелье остаются с тобой."
	_retry.text = "Вернуться в начало"
	var restart: Button = _ending.find_child("RestartRunButton",true,false) as Button
	restart.visible = won
	restart.text = "Начать новое прохождение"


func toggle_map() -> void:
	if map_open:
		close_map()
		return
	if _ending_open or _base_pause_open() or get_tree().paused:
		return
	_player.cancel_absorb_for_pause()
	_player.clear_action_buffer()
	map_open = true
	_map.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_map() -> void:
	if not map_open:
		return
	map_open = false
	_map.hide()
	_player.clear_action_buffer()
	if not _ending_open and not bool(_route.get("finished")):
		get_tree().paused = false

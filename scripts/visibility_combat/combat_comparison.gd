extends "res://scripts/dungeon/dungeon_route.gd"

const COMPARISON_GEOMETRY = preload("res://scripts/visibility_combat/combat_geometry.gd")
const FEEDBACK = preload("res://scripts/visibility_combat/barrier_feedback.gd")
const COMPARISON_SCENE := "res://scenes/visibility_combat/visibility_combat.tscn"
const PAIR: Array[String] = ["furnace", "cistern"]
const START := Vector3(-5.5, 0.05, -18.0)
const ENEMY_POSITIONS: Array[Vector3] = [Vector3(-7.5,0.04,-21),Vector3(-6,0.04,-15),Vector3(7,0.04,-21),Vector3(8,0.04,-15)]
var ready_for_comparison := false
var compare_mode := 0
var camera_mode := 1
var reveal: SlimeRoomCutaway
var ai_paused := false
var enemy_shots: Dictionary = {}
var _mode_buttons: Array[Button] = []
var _start_panel: PanelContainer
var _comparison_chrome: CanvasLayer
var _mode_row: HBoxContainer
var _camera_row: HBoxContainer
var _camera_buttons: Array[Button] = []
var barrier_feedback: Control

func _enter_tree() -> void:
	seed(63027)
	super._enter_tree()
	compare_mode = int(get_tree().get_meta(&"visibility_combat_mode",0))
	camera_mode = int(get_tree().get_meta(&"visibility_camera_mode",1))
	set_meta(&"camera_free_rotation", camera_mode == 1)

func _geometry_for_route() -> Script:
	return COMPARISON_GEOMETRY

func _ready() -> void:
	await super._ready()
	_transitioning = true
	reveal = geometry.cutaway
	var count := 0
	for id: String in room_roots:
		for actor: Node in room_roots[id].get_children():
			if not actor is Spitter and not actor is ExitGuardian: continue
			if not PAIR.has(id):
				# Gate damage queries the enemy group even for sleeping actors.
				# Isolate this fight completely, including offscreen collisions.
				actor.queue_free()
				continue
			actor.global_position = ENEMY_POSITIONS[count]
			actor.velocity = Vector3.ZERO
			actor.set_meta(&"comparison_actor",count)
			enemy_shots[count] = 0
			(actor as Spitter).projectile_requested.connect(_record_enemy_shot.bind(count))
			count += 1
	player.grant_ability(&"acid_spit")
	_reset_position(START)
	_visit_room("furnace")
	_build_comparison_ui()
	set_compare_mode(compare_mode)
	set_camera_mode(camera_mode)
	ink_style.style_label.hide()
	hud.show_notice("Подбери обзор колёсиком. Перепонку открывает кислота.")
	_transitioning = false
	ready_for_comparison = true
	get_tree().paused = true
	_start_panel.show()
	print("VISIBILITY_COMBAT_READY enemies=%d mode=%d" % [comparison_enemies().size(),compare_mode])

func _record_enemy_shot(_enemy: Spitter, _origin: Vector3, _direction: Vector3, _damage: int, _speed: float, _range: float, _key: String, index: int) -> void:
	enemy_shots[index] = int(enemy_shots.get(index,0))+1

func comparison_enemies() -> Array:
	var result: Array = []
	for id: String in PAIR:
		if not room_roots.has(id): continue
		for actor in room_roots[id].get_children():
			if actor is Spitter and actor.is_alive(): result.append(actor)
	return result

func alive_enemies(id: String = "") -> Array:
	if id.is_empty(): return comparison_enemies()
	if not PAIR.has(id): return []
	return super.alive_enemies(id)

func set_compare_mode(value: int) -> void:
	compare_mode = clampi(value,0,1)
	get_tree().set_meta(&"visibility_combat_mode",compare_mode)
	if is_instance_valid(reveal): reveal.set_enabled(compare_mode==1)
	for index: int in _mode_buttons.size():
		_mode_buttons[index].set_pressed_no_signal(index==compare_mode)

func start_comparison() -> void:
	if not ready_for_comparison: return
	_start_panel.hide()
	_pause_panel.hide()
	player.clear_action_buffer()
	get_tree().paused = false


func set_camera_mode(value: int) -> void:
	camera_mode = clampi(value, 0, 1)
	get_tree().set_meta(&"visibility_camera_mode", camera_mode)
	player.controls._cancel_camera_drag()
	player.presentation.set_free_rotation(camera_mode == 1)
	for index: int in _camera_buttons.size():
		_camera_buttons[index].set_pressed_no_signal(index == camera_mode)

func reset_comparison(mode: int = -1) -> void:
	if mode >= 0: set_compare_mode(mode)
	get_tree().paused = false
	get_tree().change_scene_to_file(COMPARISON_SCENE)

func restart_run() -> void:
	reset_comparison()

func retry_room() -> void:
	reset_comparison()

func set_test_ai_paused(value: bool) -> void:
	ai_paused = value
	for actor: Node in comparison_enemies():
		actor.process_mode = Node.PROCESS_MODE_PAUSABLE
		actor.set_physics_process(not value)
		actor.set_process(not value)

func _process(_delta: float) -> void:
	if is_instance_valid(_mode_row):
		_mode_row.visible = not get_tree().paused or _start_panel.visible
		_camera_row.visible = _mode_row.visible

func _input(event: InputEvent) -> void:
	if is_instance_valid(_start_panel) and _start_panel.visible and event.is_action_pressed(&"pause"):
		start_comparison()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_start_panel) and _start_panel.visible: return
	super._notification(what)

func _build_comparison_ui() -> void:
	_comparison_chrome = CanvasLayer.new()
	_comparison_chrome.layer = 5
	add_child(_comparison_chrome)
	var row := HBoxContainer.new()
	_mode_row = row
	row.position = Vector2(24,116)
	_comparison_chrome.add_child(row)
	for index: int in 2:
		var button := _comparison_button(row,["A · Полные стены","B · Цельное раскрытие"][index],func() -> void: set_compare_mode(index))
		button.toggle_mode = true
		_mode_buttons.append(button)
	_comparison_button(row,"Повторить бой",reset_comparison)
	_camera_row = HBoxContainer.new()
	_camera_row.position = Vector2(24, 148)
	_comparison_chrome.add_child(_camera_row)
	for index: int in 2:
		var button := _comparison_button(_camera_row, ["Камера · шаг 90°", "Камера · свободно"][index], func() -> void: set_camera_mode(index))
		button.toggle_mode = true
		_camera_buttons.append(button)
	_start_panel = PanelContainer.new()
	_start_panel.position = Vector2(340,245)
	_start_panel.custom_minimum_size = Vector2(600,220)
	_comparison_chrome.add_child(_start_panel)
	var rows := VBoxContainer.new()
	_start_panel.add_child(rows)
	var title := Label.new()
	title.text = "Каменные гряды ↔ Резервуар"
	title.add_theme_font_size_override("font_size",25)
	rows.add_child(title)
	var help := Label.new()
	help.text = "Зажми колёсико и двигай мышь — подбери любой угол.\nОтпусти — камера остановится. Наклон остаётся прежним.\nСверху можно сравнить свободный поворот и шаг 90°.\n\nA / B меняют стены. Через прозрачную кладку нельзя\nпройти, перепрыгнуть или выстрелить. Перепонку открывает кислота.\n«Повторить бой» возвращает четырёх врагов на исходные места."
	rows.add_child(help)
	_comparison_button(rows,"Начать · Esc",start_comparison)
	barrier_feedback = FEEDBACK.new()
	barrier_feedback.route = self
	_comparison_chrome.add_child(barrier_feedback)

func _comparison_button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

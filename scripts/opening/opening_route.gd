extends SlimeLevelWorkspace
class_name SlimeOpeningRoute

const GEOMETRY = preload("res://scripts/opening/opening_geometry.gd")
const LAYOUT := "res://resources/opening/layout.json"
var rooms: Array = []
var room_index := 0
var geometry: Node3D
var _room_label: Label
var _hint: Label
var _ending: ColorRect
var finished := false
var horizontal_scale := 1.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_meta(&"isometric_dressing_owned", true)
	set_meta(&"isometric_exploration", true)
	rooms = (JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)) as Dictionary).rooms
	combat = SlimeCombatRuntime.new()
	combat.name = "CombatRuntime"
	add_child(combat)
	combat.bind_player(player)
	_build_ui()
	_room_label = get_node("HUD").get_child(0) as Label
	_hint = get_node("HUD").get_child(1) as Label
	_hint.add_theme_font_size_override("font_size",17)
	_build_ending()
	_enter_room(0)


func spawn_position() -> Vector3:
	var raw: Array = rooms[room_index].points[0].pos
	return world_point(Vector3(float(raw[0]),float(raw[1])+0.045,float(raw[2])))


func exit_position() -> Vector3:
	var raw: Array = rooms[room_index].points[1].pos
	return world_point(Vector3(float(raw[0]),float(raw[1]),float(raw[2])))


func world_point(point: Vector3) -> Vector3:
	return Vector3(point.x*horizontal_scale,point.y,point.z*horizontal_scale)


func _enter_room(index: int) -> void:
	player.presentation._update_occlusion()
	for mesh in player.presentation.hidden:
		if is_instance_valid(mesh): mesh.show()
	player.presentation.hidden.clear()
	player.presentation.occluders.clear()
	player.presentation.room_cutaway = null
	if is_instance_valid(geometry):
		remove_child(geometry)
		geometry.queue_free()
	for child in combat.get_children():
		child.queue_free()
	room_index = index
	geometry = GEOMETRY.new()
	geometry.name = "RoomGeometry"
	geometry.horizontal_scale = horizontal_scale
	geometry.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(geometry)
	geometry.build(rooms[index],index)
	player.presentation.room_cutaway = geometry.cutaway
	var raw: Array = rooms[index].cameraCenter
	set_meta(&"isometric_camera_center",world_point(Vector3(float(raw[0]),float(raw[1]),float(raw[2]))))
	player.global_position = spawn_position()
	player.velocity = Vector3.ZERO
	player.clear_action_buffer()
	player._ground_trail.clear_for_room_change()
	player._whip_visual._clear_contact()
	player.presentation.zoom_target = [13.0,13.5,15.0][index]
	player.presentation.camera.size = player.presentation.zoom_target
	player.presentation._update_camera(0.0)
	player.presentation._update_occlusion()
	_room_label.text = String(rooms[index].title)


func _physics_process(_delta: float) -> void:
	if get_tree().paused: return
	if player.global_position.y < -3.8:
		player.global_position = spawn_position()
		player.velocity = Vector3.ZERO
		player.clear_action_buffer()
	var near_exit := _can_exit()
	var next := "Продолжить путь" if room_index < 2 else "Дальше наверх"
	_hint.text = ("E — " + next) if near_exit else "WASD — движение · Пробел: удержать и отпустить — прыжок · ЛКМ — хлыст · Esc — пауза"
	if room_index == 0 and player.global_position.distance_to(spawn_position()) < 0.9:
		_hint.text = "Мне надо наверх. К своим."
	if Input.is_action_just_pressed(&"interact") and near_exit:
		if room_index < 2:
			_enter_room(room_index+1)
		else:
			_finish_opening()


func _can_exit() -> bool:
	var offset := player.global_position-exit_position()
	return player.is_on_floor() and Vector2(offset.x,offset.z).length() < 1.05 and absf(offset.y) < 0.22 and player._action == &""


func _input(event: InputEvent) -> void:
	if finished: return
	super._input(event)


func _notification(what: int) -> void:
	if not finished:
		super._notification(what)


func _build_ending() -> void:
	_ending = ColorRect.new()
	_ending.name = "OpeningEnd"
	_ending.color = Color(0.025,0.035,0.04,0.86)
	_ending.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ending.visible = false
	get_node("HUD").add_child(_ending)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(-240,-100)
	box.size = Vector2(480,200)
	box.add_theme_constant_override("separation",20)
	_ending.add_child(box)
	var text := Label.new()
	text.text = "Ты поднялся.\nДальше — путь к своим."
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size",28)
	box.add_child(text)
	var replay := Button.new()
	replay.text = "Пройти ещё раз"
	replay.custom_minimum_size.y = 45
	replay.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/opening/opening_route.tscn"))
	box.add_child(replay)
	var menu := Button.new()
	menu.text = "В меню"
	menu.custom_minimum_size.y = 45
	menu.pressed.connect(func() -> void: _pause_panel._go_to_menu())
	box.add_child(menu)


func _finish_opening() -> void:
	finished = true
	player.clear_action_buffer()
	_ending.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

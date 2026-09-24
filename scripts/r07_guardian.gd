extends "res://scripts/s4_trial.gd"

const GUARDIAN_SCRIPT = preload("res://scripts/enemies/exit_guardian.gd")

var guardian: ExitGuardian
var _gate: StaticBody3D
var _exit_mark: MeshInstance3D
var _boss_bar: ProgressBar
var _boss_label: Label
var _restart_button: Button
var _replay_button: Button
var _menu_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_create_hud()
	_add_final_buttons()
	var saved_entry := _saved_entry()
	if get_tree().get_meta(&"checkpoint_active", false) and saved_entry.is_empty():
		_show_end("Не удалось восстановить входной снимок")
		return
	_build_room()
	stage = &"r07_fight"
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.projectile_requested.connect(_on_player_projectile)
	player.spikes_requested.connect(_on_player_spikes)
	player.info_requested.connect(_show_info)
	player.whip_hit.connect(func(at: Vector3) -> void: _play_audio(HIT_SOUND, at))
	player.action_started.connect(_on_action_started)
	player.loadout_changed.connect(_refresh_collection)
	player.grant_ability(&"sticky_spit")
	player.grant_ability(&"elastic_shell")
	player.grant_ability(&"slime_spikes")
	player.unlock_second_slot()
	_restore_r05_entry(saved_entry)
	_on_health_changed(player.health, player.MAX_HEALTH)
	guardian = GUARDIAN_SCRIPT.new() as ExitGuardian
	guardian.name = "ExitGuardian"
	guardian.position = Vector3(0.0, 0.05, -3.8)
	guardian.player_target = player
	guardian.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(guardian)
	guardian.health_changed.connect(_on_boss_health_changed)
	guardian.phase_changed.connect(_on_enemy_phase_changed)
	guardian.line_requested.connect(_on_boss_line)
	guardian.died.connect(_on_boss_died)
	_on_boss_health_changed(guardian.health, guardian.MAX_HEALTH)
	_show_info("Страж выхода: изучи три повторяющихся приема")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if stage == &"complete":
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
			_replay_from_start()
			get_viewport().set_input_as_handled()
		return
	super._input(event)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if get_tree().paused or stage != &"r07_exit":
		return
	if player.is_on_floor() and player.global_position.distance_to(Vector3(0.0, 0.05, -10.4)) <= 1.7 and Input.is_action_just_pressed(&"interact"):
		_complete_run()


func _process(delta: float) -> void:
	super._process(delta)
	if get_tree().paused or _info_left > 0.0:
		return
	if stage == &"r07_fight":
		_hint_label.text = "Страж: линия и круг низкие — прыгай; сектор — уходи в сторону"
	elif stage == &"r07_exit":
		_hint_label.text = "Выход открыт. Иди к свету и нажми E у стада"


func _on_boss_health_changed(current: int, maximum: int) -> void:
	if is_instance_valid(_boss_bar):
		_boss_bar.max_value = maximum
		_boss_bar.value = current


func _on_boss_line(source: ExitGuardian, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	if stage != &"r07_fight" or not is_instance_valid(source):
		return
	_add_spikes(source, &"enemy", origin, direction, cast_key, 14)
	_play_audio(CAST_SOUND, origin)


func _on_boss_died() -> void:
	if stage != &"r07_fight":
		return
	stage = &"r07_exit"
	for group in [&"enemy_attacks", &"enemy_projectiles"]:
		for threat: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(threat):
				threat.set_physics_process(false)
				threat.queue_free()
	_gate.collision_layer = 0
	_gate.get_node("CollisionShape3D").set_deferred("disabled", true)
	_gate.visible = false
	_exit_mark.visible = true
	_boss_bar.visible = false
	_boss_label.visible = false
	_show_info("Страж повержен. Выход к стаду открыт")


func _complete_run() -> void:
	if get_tree().get_meta(&"checkpoint_active", false):
		var store: CheckpointStore = STORE_SCRIPT.new()
		var result := store.complete_slice(player)
		if not result["ok"]:
			_show_info("Не удалось сохранить завершение: %s" % result["error"])
			return
	stage = &"complete"
	_show_end("Ты вернулся к своему стаду")
	_restart_button.visible = false
	_replay_button.visible = true
	_menu_button.visible = true


func _replay_from_start() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new()
	var result := store.write_checkpoint(store.initial_snapshot(), true)
	if not result["ok"]:
		_end_title.text = "Не удалось начать заново: %s" % result["error"]
		return
	get_tree().paused = false
	get_tree().set_meta(&"checkpoint_active", true)
	var changed := get_tree().change_scene_to_file("res://scenes/r01_entrance.tscn")
	if changed != OK:
		_end_title.text = "Не удалось открыть первый зал"
		_show_end(_end_title.text)


func _go_to_menu() -> void:
	get_tree().paused = false
	get_tree().remove_meta(&"checkpoint_active")
	var changed := get_tree().change_scene_to_file("res://scenes/launch.tscn")
	if changed != OK:
		_show_end("Не удалось открыть меню")


func _add_final_buttons() -> void:
	var box := _end_panel.get_child(0) as VBoxContainer
	_restart_button = box.get_child(1) as Button
	_replay_button = Button.new()
	_replay_button.text = "Повторить с начала (R)"
	_replay_button.custom_minimum_size.y = 48
	_replay_button.pressed.connect(_replay_from_start)
	_replay_button.visible = false
	box.add_child(_replay_button)
	_menu_button = Button.new()
	_menu_button.text = "В меню"
	_menu_button.custom_minimum_size.y = 48
	_menu_button.pressed.connect(_go_to_menu)
	_menu_button.visible = false
	box.add_child(_menu_button)
	var hud_root := _hud.get_child(0) as Control
	_boss_label = Label.new()
	_boss_label.text = "СТРАЖ ВЫХОДА"
	_boss_label.add_theme_font_size_override("font_size", 19)
	_boss_label.anchor_left = 0.5
	_boss_label.anchor_right = 0.5
	_boss_label.offset_left = -150
	_boss_label.offset_right = 150
	_boss_label.offset_top = 17
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.anchor_left = 0.5
	_boss_bar.anchor_right = 0.5
	_boss_bar.offset_left = -155
	_boss_bar.offset_right = 155
	_boss_bar.offset_top = 49
	_boss_bar.offset_bottom = 69
	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color(0.07, 0.10, 0.11, 0.9)
	_boss_bar.add_theme_stylebox_override("background", bar_back)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.95, 0.45, 0.20)
	_boss_bar.add_theme_stylebox_override("fill", bar_fill)
	hud_root.add_child(_boss_bar)


func _build_room() -> void:
	_block("ArenaFloor", Vector3(0.0, -0.2, 0.0), Vector3(18.0, 0.4, 18.0), Color(0.16, 0.18, 0.22))
	_block("WestWall", Vector3(-9.2, 1.6, 0.0), Vector3(0.4, 3.2, 18.4), Color(0.27, 0.29, 0.33))
	_block("EastWall", Vector3(9.2, 1.6, 0.0), Vector3(0.4, 3.2, 18.4), Color(0.27, 0.29, 0.33))
	_block("EntryWall", Vector3(0.0, 1.6, 9.2), Vector3(18.4, 3.2, 0.4), Color(0.27, 0.29, 0.33))
	_block("ExitWallLeft", Vector3(-5.3, 1.6, -9.2), Vector3(7.8, 3.2, 0.4), Color(0.27, 0.29, 0.33))
	_block("ExitWallRight", Vector3(5.3, 1.6, -9.2), Vector3(7.8, 3.2, 0.4), Color(0.27, 0.29, 0.33))
	_add_floor_tiles()
	_add_wall_courses()
	_add_wall_buttresses()
	_block("HerdFloor", Vector3(0.0, -0.2, -10.9), Vector3(6.2, 0.4, 4.2), Color(0.43, 0.48, 0.47))
	_block("HerdEnd", Vector3(0.0, 1.6, -13.2), Vector3(6.4, 3.2, 0.3), Color(0.43, 0.48, 0.47))
	_gate = _block("ExitGate", Vector3(0.0, 1.4, -9.2), Vector3(2.8, 2.8, 0.35), Color(0.20, 0.24, 0.28))
	_add_gate_trim()
	_exit_mark = _visual_box("ExitMark", Vector3(0.0, 0.04, -10.4), Vector3(2.7, 0.08, 0.32), Color(1.0, 0.88, 0.50), true)
	_exit_mark.visible = false
	_visual_box("GateLight", Vector3(0.0, 3.02, -8.81), Vector3(2.85, 0.12, 0.08), Color(1.0, 0.72, 0.38), true)
	for x in [-1.2, 0.0, 1.2]:
		_add_herd_slime(Vector3(x, 0.0, -11.55))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.11, 0.15, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.66, 0.70)
	environment.ambient_light_energy = 0.56
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -20.0, 0.0)
	sun.light_energy = 0.82
	sun.light_color = Color(0.94, 0.93, 0.91)
	sun.shadow_enabled = true
	add_child(sun)
	var exit_light := OmniLight3D.new()
	exit_light.position = Vector3(0.0, 2.8, -9.4)
	exit_light.light_color = Color(1.0, 0.77, 0.46)
	exit_light.light_energy = 3.0
	exit_light.omni_range = 11.0
	add_child(exit_light)



func _add_floor_tiles() -> void:
	var dark: Array[Vector3] = []
	var middle: Array[Vector3] = []
	var light: Array[Vector3] = []
	for row in 12:
		for column in 8:
			var stagger := 0.16 if row % 2 == 0 else -0.16
			var at := Vector3(-7.28 + float(column) * 2.08 + stagger, 0.019, -8.25 + float(row) * 1.50)
			match (row * 5 + column * 7) % 5:
				0, 3:
					dark.append(at)
				1, 4:
					middle.append(at)
				_:
					light.append(at)
	_add_instanced_slab("FloorSlabsDark", dark, Color(0.25, 0.28, 0.32))
	_add_instanced_slab("FloorSlabsMid", middle, Color(0.28, 0.31, 0.35))
	_add_instanced_slab("FloorSlabsLight", light, Color(0.31, 0.34, 0.38))


func _add_instanced_slab(label: String, positions: Array[Vector3], tint: Color) -> void:
	var mesh := _slab_mesh()
	var material := _stone(tint)
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = positions.size()
	for index in positions.size():
		instances.set_instance_transform(index, Transform3D(Basis(), positions[index]))
	var visuals := MultiMeshInstance3D.new()
	visuals.name = label
	visuals.multimesh = instances
	add_child(visuals)


func _slab_mesh() -> ArrayMesh:
	var outer := [Vector3(-0.96, -0.019, -0.66), Vector3(0.96, -0.019, -0.66), Vector3(0.96, -0.019, 0.66), Vector3(-0.96, -0.019, 0.66)]
	var top := [Vector3(-0.90, 0.019, -0.59), Vector3(0.90, 0.019, -0.59), Vector3(0.90, 0.019, 0.59), Vector3(-0.90, 0.019, 0.59)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_slab_triangle(surface, top[0], top[3], top[2], Color.WHITE)
	_add_slab_triangle(surface, top[0], top[2], top[1], Color.WHITE)
	for side in 4:
		var next := (side + 1) % 4
		_add_slab_triangle(surface, outer[side], top[side], top[next], Color(0.67, 0.70, 0.75))
		_add_slab_triangle(surface, outer[side], top[next], outer[next], Color(0.67, 0.70, 0.75))
	return surface.commit()


func _add_slab_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.set_uv(Vector2((point.x + 0.96) / 1.92, (point.z + 0.66) / 1.32))
		surface.add_vertex(point)


func _add_wall_courses() -> void:
	var back: Array[Vector3] = []
	var sides: Array[Vector3] = []
	for row in 4:
		var height := 0.40 + float(row) * 0.80
		var shift := 0.36 if row % 2 == 0 else -0.36
		for column in 8:
			var along := -7.875 + float(column) * 2.25 + shift
			sides.append(Vector3(-8.96, height, along))
			sides.append(Vector3(8.96, height, along))
		for along in [-7.875, -5.625, -3.375, 3.375, 5.625, 7.875]:
			back.append(Vector3(along + shift * 0.25, height, -8.96))
	_add_instanced_stone("BackWallCourses", Vector3(2.17, 0.73, 0.075), back, Color(0.30, 0.33, 0.38))
	_add_instanced_stone("SideWallCourses", Vector3(0.075, 0.73, 2.12), sides, Color(0.29, 0.32, 0.37))


func _add_wall_buttresses() -> void:
	var stone := Color(0.25, 0.28, 0.33)
	var edge := Color(0.38, 0.40, 0.43)
	for side in [-1.0, 1.0]:
		_visual_box("WallCoping", Vector3(side * 8.92, 3.26, 0.0), Vector3(0.67, 0.23, 18.0), edge)
		for along in [-6.5, -2.25, 2.0, 6.25]:
			_visual_box("Buttress", Vector3(side * 8.79, 1.85, along), Vector3(0.55, 3.70, 0.65), stone)
			_visual_box("ButtressFoot", Vector3(side * 8.72, 0.27, along), Vector3(0.76, 0.54, 0.91), edge)
			_visual_box("ButtressCap", Vector3(side * 8.76, 3.71, along), Vector3(0.79, 0.22, 0.90), edge)
	for across in [-7.0, -3.6, 3.6, 7.0]:
		_visual_box("BackPier", Vector3(across, 1.69, -8.76), Vector3(0.53, 3.38, 0.58), stone)
		_visual_box("BackPierCap", Vector3(across, 3.38, -8.76), Vector3(0.73, 0.22, 0.73), edge)


func _add_instanced_stone(label: String, size: Vector3, positions: Array[Vector3], tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _stone(tint)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = positions.size()
	for index in positions.size():
		instances.set_instance_transform(index, Transform3D(Basis(), positions[index]))
	var visuals := MultiMeshInstance3D.new()
	visuals.name = label
	visuals.multimesh = instances
	add_child(visuals)


func _add_gate_trim() -> void:
	var pillar_color := Color(0.44, 0.43, 0.43)
	var edge_color := Color(0.58, 0.54, 0.48)
	for side in [-1.0, 1.0]:
		_visual_box("PortalPillar", Vector3(side * 1.87, 1.91, -8.71), Vector3(0.64, 3.82, 0.72), pillar_color)
		_visual_box("PortalFoot", Vector3(side * 1.87, 0.36, -8.65), Vector3(0.94, 0.72, 0.91), edge_color)
		_visual_box("PortalCapital", Vector3(side * 1.87, 3.74, -8.71), Vector3(0.92, 0.33, 0.84), edge_color)
		var arch := _visual_box("PortalArch", Vector3(side * 1.02, 4.11, -8.72), Vector3(2.06, 0.48, 0.77), pillar_color)
		arch.rotation.z = -side * 0.45
		_visual_box("GateInnerGlow", Vector3(side * 1.43, 1.42, -8.27), Vector3(0.045, 2.55, 0.05), Color(0.98, 0.61, 0.28), true)
	var keystone := _visual_box("PortalKeystone", Vector3(0.0, 4.56, -8.68), Vector3(0.68, 0.68, 0.86), edge_color)
	keystone.rotation.z = PI * 0.25
	_visual_box("PortalCrest", Vector3(0.0, 5.07, -8.79), Vector3(0.30, 0.48, 0.42), Color(0.69, 0.60, 0.46))
	_add_surface_backdrop()


func _add_surface_backdrop() -> void:
	var backdrop := MeshInstance3D.new()
	backdrop.name = "SurfaceLight"
	var quad := QuadMesh.new()
	quad.size = Vector2(3.12, 2.58)
	backdrop.mesh = quad
	backdrop.position = Vector3(0.0, 1.45, -13.01)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 low = vec3(0.86, 0.61, 0.34);
	vec3 high = vec3(0.53, 0.66, 0.73);
	vec3 daylight = mix(high, low, smoothstep(0.10, 0.98, UV.y));
	float sun = 1.0 - smoothstep(0.07, 0.22, distance(UV, vec2(0.53, 0.57)));
	daylight = mix(daylight, vec3(1.0, 0.91, 0.65), sun * 0.86);
	ALBEDO = daylight;
	EMISSION = daylight * 1.35;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	backdrop.material_override = material
	add_child(backdrop)


func _add_herd_slime(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "HerdSlime"
	root.position = at
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.68, 0.60, 0.65)
	body.mesh = box
	body.position.y = 0.31
	body.material_override = _stone(Color(0.32, 0.89, 0.70), true)
	root.add_child(body)
	for x in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		eye.mesh = sphere
		eye.position = Vector3(x, 0.37, 0.34)
		eye.material_override = _stone(Color(0.96, 0.99, 0.94))
		root.add_child(eye)
	add_child(root)


func _block(label: String, at: Vector3, size: Vector3, tint: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _stone(tint)
	body.add_child(mesh)
	add_child(body)
	return body


func _visual_box(label: String, at: Vector3, size: Vector3, tint: Color, glow: bool = false) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.position = at
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	piece.material_override = _stone(tint, glow)
	add_child(piece)
	return piece


func _stone(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.78
	if glow:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 1.0
	return material

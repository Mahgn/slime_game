extends Node3D

const ENEMY_SCENE = preload("res://scenes/enemies/spitter.tscn")
const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")
const NAMES := ["Дыхание и взгляд", "Походка", "Плевок", "Получение удара", "Смерть"]
const LENGTHS := [2.7, 2.5, 2.6, 1.2, 3.4]
var enemy: Spitter
var camera: Camera3D
var automatic := true
var mode := 0
var elapsed := 0.0
var yaw := -0.46
var pitch := 0.19
var _fired := false
var _label: Label
var _mode_buttons: Array[Button] = []
var _auto_button: Button
var _aim_target: Node3D


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_create_studio()
	_create_ui()
	_aim_target = Node3D.new()
	_aim_target.position = Vector3(0.0, 0.0, -8.0)
	add_child(_aim_target)
	automatic = not OS.get_cmdline_user_args().has("--death")
	select_mode(0 if automatic else 4)


func _create_studio() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.10, 0.135)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.66, 0.75, 0.88)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.73)
	key.light_energy = 1.25
	key.shadow_enabled = true
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.5, 2.6, 1.6)
	rim.light_color = Color(0.56, 0.75, 1.0)
	rim.light_energy = 3.5
	rim.omni_range = 6.0
	add_child(rim)
	var platform := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.6
	cylinder.bottom_radius = 1.68
	cylinder.height = 0.16
	cylinder.radial_segments = 64
	platform.mesh = cylinder
	platform.position.y = -0.08
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.16, 0.21, 0.25)
	stone.roughness = 0.84
	platform.material_override = stone
	add_child(platform)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.18
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.045, 0.062, 0.082)
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 36.0
	add_child(camera)
	camera.current = true
	_update_camera()


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ПЛЕВУН"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.80, 0.52))
	column.add_child(title)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var help := Label.new()
	help.text = "Потяните мышью — повернуть обзор     •     Пробел — автопросмотр     •     Enter — в бой"
	help.add_theme_font_size_override("font_size", 16)
	column.add_child(help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for index in NAMES.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, NAMES[index]]
		button.custom_minimum_size.y = 44
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			automatic = false
			select_mode(index)
		)
		row.add_child(button)
		_mode_buttons.append(button)
	_auto_button = Button.new()
	_auto_button.text = "Авто"
	_auto_button.toggle_mode = true
	_auto_button.button_pressed = automatic
	_auto_button.focus_mode = Control.FOCUS_NONE
	_auto_button.pressed.connect(func() -> void: automatic = _auto_button.button_pressed)
	row.add_child(_auto_button)
	var battle := Button.new()
	battle.text = "В бой →"
	battle.focus_mode = Control.FOCUS_NONE
	battle.pressed.connect(_open_combat)
	row.add_child(battle)


func select_mode(index: int) -> void:
	mode = index
	elapsed = 0.0
	_fired = false
	if is_instance_valid(enemy):
		enemy.queue_free()
	for remains in get_tree().get_nodes_in_group(&"spitter_remains"):
		remains.queue_free()
	for projectile in get_tree().get_nodes_in_group(&"projectiles"):
		projectile.queue_free()
	enemy = ENEMY_SCENE.instantiate() as Spitter
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.player_target = _aim_target
	enemy.projectile_requested.connect(_on_shot)
	if mode == 2:
		enemy._set_phase(Spitter.Phase.WINDUP, enemy.PROFILE.enemy_windup)
	_label.text = NAMES[mode]
	for button_index in _mode_buttons.size():
		_mode_buttons[button_index].button_pressed = button_index == mode
	_auto_button.button_pressed = automatic


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LENGTHS[mode]:
		select_mode((mode + 1) % NAMES.size() if automatic else mode)
		return
	if not is_instance_valid(enemy):
		return
	match mode:
		1:
			var walk_phase := elapsed / LENGTHS[1] * TAU
			enemy.position.z = -0.30 * (1.0 - cos(walk_phase))
			enemy.velocity = Vector3(0.0, 0.0, -0.30 * TAU / LENGTHS[1] * sin(walk_phase))
		2:
			if elapsed < enemy.PROFILE.enemy_windup:
				enemy._phase_left = enemy.PROFILE.enemy_windup - elapsed
			elif not _fired:
				_fired = true
				enemy._locked_direction = Vector3.FORWARD
				enemy._fire()
				enemy._set_phase(Spitter.Phase.RECOVERY, enemy.PROFILE.enemy_recovery)
			else:
				enemy._phase_left = maxf(0.0, enemy.PROFILE.enemy_recovery - (elapsed - enemy.PROFILE.enemy_windup))
		3:
			if elapsed > 0.3 and not _fired:
				_fired = true
				enemy.receive_hit(10, "preview_hurt", &"player")
		4:
			if elapsed > 0.25 and not _fired:
				_fired = true
				enemy.receive_hit(30, "preview_death", &"player")


func _on_shot(source: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	var shot := PROJECTILE_SCENE.instantiate() as SpitProjectile
	shot.configure(source, &"enemy", direction, speed, damage, max_range, cast_key)
	add_child(shot)
	shot.global_position = origin


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.004, -0.05, 0.72)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			automatic = false
			select_mode(event.physical_keycode - KEY_1)
		elif event.physical_keycode == KEY_SPACE:
			automatic = not automatic
			_auto_button.button_pressed = automatic
		elif event.physical_keycode == KEY_R:
			select_mode(mode)
		elif event.physical_keycode == KEY_ENTER:
			_open_combat()


func _update_camera() -> void:
	var target := Vector3(0.0, 0.66, 0.0)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * 4.8
	camera.look_at(target)


func _open_combat() -> void:
	get_tree().set_meta(&"checkpoint_active", false)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

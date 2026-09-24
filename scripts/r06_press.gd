extends "res://scripts/s4_trial.gd"

const PRESS_TARGET_SCRIPT = preload("res://scripts/interactables/press_target.gd")
const PHASE_SECONDS := {&"warning": 1.0, &"lowering": 0.2, &"hold": 0.4, &"open": 2.4}

var press_phase: StringName = &"warning"
var phase_left := 1.0
var sticky_open_left := 0.0
var trap_protection_left := 0.0
var _beam: MeshInstance3D
var _warning_strip: MeshInstance3D
var _safe_marker := Vector3(0.0, 0.05, 2.6)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_create_hud()
	var saved_entry := _saved_entry()
	if get_tree().get_meta(&"checkpoint_active", false) and saved_entry.is_empty():
		_show_end("Не удалось восстановить входной снимок")
		return
	_build_room()
	stage = &"r06"
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
	_show_info("Пробел — прыгни на низкий уступ; дальше следи за прессом")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if get_tree().paused or stage != &"r06":
		return
	trap_protection_left = maxf(0.0, trap_protection_left - delta)
	if sticky_open_left > 0.0:
		sticky_open_left = maxf(0.0, sticky_open_left - delta)
		if sticky_open_left == 0.0:
			press_phase = &"warning"
			phase_left = PHASE_SECONDS[press_phase]
	else:
		phase_left -= delta
		if phase_left <= 0.0:
			match press_phase:
				&"warning": press_phase = &"lowering"
				&"lowering": press_phase = &"hold"
				&"hold": press_phase = &"open"
				&"open": press_phase = &"warning"
			phase_left = PHASE_SECONDS[press_phase]
	_update_press_visual()
	if player.global_position.z < -2.2 and player.is_on_floor():
		_safe_marker = Vector3(0.0, 0.05, -2.3)
	if player.global_position.y < -2.5:
		player.apply_environment_damage(10)
		if player.health > 0:
			_return_to_safe_marker()
		return
	var in_press := absf(player.global_position.x) < 1.42 and player.global_position.z > -0.12 and player.global_position.z < 1.08
	if in_press and sticky_open_left <= 0.0 and (press_phase == &"lowering" or press_phase == &"hold") and trap_protection_left <= 0.0:
		player.apply_environment_damage(15)
		trap_protection_left = 1.0
		if player.health > 0:
			_safe_marker = Vector3(0.0, 0.05, 2.6)
			_return_to_safe_marker()
			_show_info("Пресс ударил: 15 HP. Следи за предупреждением")
		return
	if player.global_position.z < -7.2 and Input.is_action_just_pressed(&"interact") and player.is_on_floor():
		stage = &"complete"
		_show_end("R06 пройден")


func _process(delta: float) -> void:
	super._process(delta)
	if stage == &"r06" and _info_left <= 0.0 and not get_tree().paused:
		if player.global_position.z > 4.3:
			_hint_label.text = "Пробел — прыжок на низкий уступ"
		elif player.global_position.z > 1.5:
			_hint_label.text = "Tab — навыки · Пресс: 1 с предупреждения, затем откроется"
		elif player.global_position.z > -4.3:
			_hint_label.text = "Пробел — прыжок через разрыв 1,6 м"
		else:
			_hint_label.text = "У светлого выхода нажми E"


func _on_sticky_applied() -> void:
	sticky_open_left = 3.0
	press_phase = &"open"
	phase_left = 3.0
	_update_press_visual()
	_show_info("Липкость удерживает пресс открытым 3 с")


func _return_to_safe_marker() -> void:
	player.global_position = _safe_marker
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _update_press_visual() -> void:
	if not is_instance_valid(_beam):
		return
	var height := 2.75
	if sticky_open_left <= 0.0:
		if press_phase == &"lowering":
			height = lerpf(2.75, 0.82, 1.0 - phase_left / 0.2)
		elif press_phase == &"hold":
			height = 0.82
	_beam.position.y = height
	_warning_strip.visible = sticky_open_left <= 0.0 and press_phase == &"warning"


func _build_room() -> void:
	_block("NearFloor", Vector3(0.0, -0.2, 2.45), Vector3(8.0, 0.4, 11.1), Color(0.31, 0.39, 0.43))
	_block("FarFloor", Vector3(0.0, -0.2, -6.85), Vector3(8.0, 0.4, 4.3), Color(0.36, 0.44, 0.43))
	_block("WestWall", Vector3(-4.15, 1.25, 0.0), Vector3(0.3, 2.5, 16.8), Color(0.37, 0.45, 0.47))
	_block("EastWall", Vector3(4.15, 1.25, 0.0), Vector3(0.3, 2.5, 16.8), Color(0.37, 0.45, 0.47))
	_block("EntryWall", Vector3(0.0, 1.25, 8.2), Vector3(8.4, 2.5, 0.3), Color(0.37, 0.45, 0.47))
	_block("FarWall", Vector3(0.0, 1.25, -9.2), Vector3(8.4, 2.5, 0.3), Color(0.37, 0.45, 0.47))
	for x in [-2.4, 2.4]:
		_block("PressRail", Vector3(x, 0.85, 0.5), Vector3(0.8, 1.7, 3.5), Color(0.42, 0.47, 0.47))
	_block("JumpPractice", Vector3(0.0, 0.20, 5.0), Vector3(1.8, 0.4, 1.0), Color(0.57, 0.58, 0.48))
	_visual_box("JumpCue", Vector3(0.0, 0.02, 5.9), Vector3(2.3, 0.04, 0.15), Color(0.9, 0.72, 0.4), true)
	_visual_box("GapEdgeNear", Vector3(0.0, 0.025, -3.02), Vector3(7.6, 0.05, 0.16), Color(0.95, 0.74, 0.34), true)
	_visual_box("GapEdgeFar", Vector3(0.0, 0.025, -4.76), Vector3(7.6, 0.05, 0.16), Color(0.95, 0.74, 0.34), true)
	_visual_box("ExitMark", Vector3(0.0, 0.03, -7.55), Vector3(2.8, 0.06, 0.28), Color(1.0, 0.80, 0.45), true)
	_visual_box("SafeMark", Vector3(0.0, 0.025, 2.6), Vector3(2.0, 0.05, 0.2), Color(0.3, 0.95, 0.75), true)
	_beam = _visual_box("PressBeam", Vector3(0.0, 2.75, 0.5), Vector3(3.8, 0.55, 1.1), Color(0.51, 0.57, 0.58))
	_warning_strip = _visual_box("Warning", Vector3(0.0, 0.03, 0.5), Vector3(3.7, 0.06, 1.4), Color(1.0, 0.4, 0.18), true)
	var target := StaticBody3D.new()
	target.set_script(PRESS_TARGET_SCRIPT)
	target.name = "StickyMechanism"
	target.position = Vector3(-1.78, 1.15, 1.35)
	target.sticky_applied.connect(_on_sticky_applied)
	add_child(target)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.15, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.69, 0.67)
	environment.ambient_light_energy = 0.88
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 4.2, -8.2)
	light.light_color = Color(1.0, 0.82, 0.50)
	light.light_energy = 1.5
	light.omni_range = 12.0
	add_child(light)
	_visual_box("UpperLight", Vector3(0.0, 3.0, -9.02), Vector3(3.2, 0.48, 0.09), Color(1.0, 0.88, 0.52), true)


func _block(label: String, center: Vector3, size: Vector3, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _stone(tint)
	body.add_child(mesh)
	add_child(body)


func _visual_box(label: String, center: Vector3, size: Vector3, tint: Color, glow: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.position = center
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _stone(tint, glow)
	add_child(mesh)
	return mesh


func _stone(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.82
	if glow:
		material.emission_enabled = true
		material.emission = tint
	return material

extends "res://scripts/main.gd"

const FRAGILE_WALL_SCRIPT = preload("res://scripts/interactables/fragile_wall.gd")
const PRESS_TARGET_SCRIPT = preload("res://scripts/interactables/press_target.gd")
const SPIKE_SCRIPT = preload("res://scripts/combat/spike_line.gd")
const TUNNEL_Z := 9.65
const TUNNEL_LENGTH := 3.6
const TUNNEL_ZONE_LENGTH := 6.0
const TUNNEL_CLEARANCE := 0.60
const PIT_RESET_Y := -1.15
const TRAP_Z := -15.0
const PRESS_PERIOD := 2.2
const PRESS_SAFE_HEIGHT := 2.3

var _low_passage_area: Area3D
var _fragile_wall: FragileWall
var _press_beam: AnimatableBody3D

var _press_frozen_left := 0.0
var _frozen_height := 0.0
var _press_motion_time := 0.0
var _trap_hit_cooldown := 0.0
var _course_enemy: Spitter
var _pit_checkpoint := Vector3(0.0, 0.05, 6.0)
var _trap_checkpoint := Vector3(0.0, 0.05, -13.15)


func _ready() -> void:
	super._ready()
	_build_course()
	player.grant_ability(&"sticky_spit")
	player.unlock_second_slot()
	player.grant_ability(&"slime_spikes")
	player.spikes_requested.connect(_on_player_spikes)
	_card_left = 0.0
	_card_back.visible = false
	_configure_two_slot_hud()
	stage = &"platform_course"
	_show_info("Стена → лаз → прыжки → останови пресс наверху → Плевун")


func _configure_two_slot_hud() -> void:
	var hud_root := _hud_layer.get_child(0) as Control
	(hud_root.get_child(0) as ColorRect).size.y = 143.0
	(hud_root.get_child(1) as ColorRect).size.y = 143.0

func _spawn_first_enemy() -> void:
	pass


func _physics_process(delta: float) -> void:
	if get_tree().paused or stage != &"platform_course" or not is_instance_valid(player):
		return
	_update_tunnel_request()
	if _press_frozen_left > 0.0:
		_press_frozen_left = maxf(0.0, _press_frozen_left - delta)
	else:
		_press_motion_time += delta
	_trap_hit_cooldown = maxf(0.0, _trap_hit_cooldown - delta)
	_update_press_visual()
	if player.global_position.y < PIT_RESET_Y:
		player.apply_environment_damage(10)
		if player.health > 0:
			_return_to(_pit_checkpoint)
			_show_info("Колья: минус 10 HP. Повтори прыжки")
		return
	if player.global_position.z < -10.3 and player.is_on_floor():
		_pit_checkpoint = _trap_checkpoint
	var player_bottom := player.global_position.y
	var player_top := player_bottom + (0.50 if player.is_compressed() else 0.80)
	var beam_bottom := _press_beam.position.y - 1.45
	var beam_top := _press_beam.position.y + 1.25
	var touches_beam := beam_bottom < player_top and beam_top > player_bottom
	if absf(player.global_position.x) < 1.45 and absf(player.global_position.z - TRAP_Z) < 0.93 and touches_beam and _trap_hit_cooldown <= 0.0:
		player.apply_environment_damage(15)
		_trap_hit_cooldown = 0.2
		if player.health > 0:
			_return_to(_trap_checkpoint)
			_show_info("Пресс ударил. Плюнь в крестик, когда балка наверху")
		return
	if player.global_position.z < -17.1 and not is_instance_valid(_course_enemy):
		_course_enemy = _add_enemy(Vector3(0.0, 0.05, -20.5))
		_show_info("Плевун впереди. Q — слизевые шипы")

func _process(delta: float) -> void:
	super._process(delta)
	var spit_status := "ГОТОВ" if player.cooldown_remaining(&"sticky_spit") <= 0.05 else "%.1f с" % player.cooldown_remaining(&"sticky_spit")
	var spike_status := "ГОТОВ" if player.cooldown_remaining(&"slime_spikes") <= 0.05 else "%.1f с" % player.cooldown_remaining(&"slime_spikes")
	_slot_label.text = "ПКМ · ПЛЕВОК %s\nQ · ШИПЫ %s" % [spit_status, spike_status]
	if stage != &"platform_course" or get_tree().paused or _info_left > 0.0:
		return
	var z := player.global_position.z
	if is_instance_valid(_fragile_wall):
		_hint_label.text = "ЛКМ — три удара по хрупкой стене"
	elif z > 6.0:
		_hint_label.text = "Стена с лазом: слайм сожмётся у отверстия снизу"
	elif z > -10.2:
		_hint_label.text = "Низкие площадки — обычный прыжок; высокие — заряд"
	elif z > TRAP_Z - 1.5:
		_hint_label.text = "Плюнь ПКМ в крестик, когда пресс наверху"
	else:
		_hint_label.text = "Плевун: Q — шипы, ПКМ — плевок, ЛКМ — хлыст"

func _on_enemy_died(enemy: Spitter, _ability_id: StringName, _at: Vector3) -> void:
	if enemy != _course_enemy or stage != &"platform_course":
		return
	stage = &"complete"
	_show_end("Испытание пройдено")


func _on_player_spikes(origin: Vector3, direction: Vector3, cast_key: String) -> void:
	var line := SPIKE_SCRIPT.new() as SpikeLine
	line.process_mode = Node.PROCESS_MODE_PAUSABLE
	line.configure(player, &"player", origin, direction, cast_key, 22)
	add_child(line)
	line.hit_target.connect(func(at: Vector3, _empowered: bool) -> void: _play_audio(_hit_audio, at))
	_play_audio(_cast_audio, origin)


func _on_wall_broken() -> void:
	_show_info("Стена разрушена. Пролезь в лаз у пола")


func _on_sticky_applied() -> void:
	_frozen_height = _press_beam.position.y
	_press_frozen_left = 4.0
	_update_press_visual()
	if _frozen_height >= PRESS_SAFE_HEIGHT:
		_show_info("Пресс застыл наверху на 4 с — проходи")
	else:
		_show_info("Пресс застыл низко: проход закрыт. Дождись нового подъёма")

func _update_tunnel_request() -> void:
	var local_position := _low_passage_area.to_local(player.global_position)
	var within_corridor := absf(local_position.x) <= 0.96
	var within_length := absf(local_position.z) <= TUNNEL_ZONE_LENGTH * 0.5
	var below_roof := player.global_position.y < TUNNEL_CLEARANCE - 0.02
	var supported := player.is_on_floor() or player.is_compressed()
	player.set_low_passage_active(_low_passage_area, within_corridor and within_length and below_roof and supported)


func _update_press_visual() -> void:
	_press_beam.position.y = _frozen_height if _press_frozen_left > 0.0 else 1.60 + 0.90 * sin(_press_motion_time * TAU / PRESS_PERIOD)

func _return_to(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _build_course() -> void:
	var stone := Color(0.33, 0.42, 0.46)
	var platform := Color(0.52, 0.62, 0.59)
	var marker := Color(0.98, 0.78, 0.36)
	_block("StartFloor", Vector3(0.0, -0.2, 13.35), Vector3(6.2, 0.4, 16.3), stone)
	_block("FinishFloor", Vector3(0.0, -0.2, -18.5), Vector3(6.2, 0.4, 16.6), stone)
	_block("WestBoundary", Vector3(-3.25, 2.75, -2.65), Vector3(0.3, 5.5, 48.3), stone)
	_block("EastBoundary", Vector3(3.25, 2.75, -2.65), Vector3(0.3, 5.5, 48.3), stone)
	_block("StartBoundary", Vector3(0.0, 2.75, 21.5), Vector3(6.8, 5.5, 0.3), stone)
	_block("FinishBoundary", Vector3(0.0, 2.75, -26.8), Vector3(6.8, 5.5, 0.3), stone)
	for x in [-2.1, 2.1]:
		_block("TunnelSide", Vector3(x, 2.75, 9.6), Vector3(2.0, 5.5, 6.8), stone)
	# A full-height wall has only one 1.5 x 0.6 m opening at floor level.
	_block("LowWallLeft", Vector3(-1.925, 2.75, 11.55), Vector3(2.35, 5.5, 0.6), platform)
	_block("LowWallRight", Vector3(1.925, 2.75, 11.55), Vector3(2.35, 5.5, 0.6), platform)
	_block("LowWallLintel", Vector3(0.0, 3.05, 11.55), Vector3(1.5, 4.9, 0.6), platform)
	_block("TunnelRoof", Vector3(0.0, 0.75, TUNNEL_Z), Vector3(2.2, 0.3, TUNNEL_LENGTH), platform)
	_visual_box("TunnelEntry", Vector3(0.0, 0.028, 11.95), Vector3(1.5, 0.055, 0.14), marker)
	_low_passage_area = Area3D.new()
	_low_passage_area.name = "LowPassageArea"
	_low_passage_area.collision_layer = 0
	_low_passage_area.collision_mask = 2
	_low_passage_area.monitoring = false
	_low_passage_area.position = Vector3(0.0, 0.275, TUNNEL_Z)
	var zone_collider := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(2.2, 0.55, TUNNEL_ZONE_LENGTH)
	zone_collider.shape = zone_shape
	_low_passage_area.add_child(zone_collider)
	add_child(_low_passage_area)
	_fragile_wall = FRAGILE_WALL_SCRIPT.new() as FragileWall
	_fragile_wall.name = "FragileWall"
	_fragile_wall.position = Vector3(0.0, 0.0, 12.6)
	_fragile_wall.broken.connect(_on_wall_broken)
	add_child(_fragile_wall)
	_visual_box("WallMarker", Vector3(0.0, 2.35, 12.6), Vector3(2.2, 0.12, 0.5), marker)
	_visual_box("PitNearEdge", Vector3(0.0, 0.025, 5.2), Vector3(5.8, 0.05, 0.16), marker)
	_visual_box("PitFarEdge", Vector3(0.0, 0.025, -10.2), Vector3(5.8, 0.05, 0.16), marker)
	var centers := [3.6, 0.5, -4.05, -6.75, -9.3]
	var heights := [0.35, 1.70, 1.70, 0.45, 1.80]
	var lengths := [1.7, 1.6, 1.4, 1.7, 1.6]
	for i in centers.size():
		var center := Vector3(0.0, heights[i] - 0.15, centers[i])
		_block("Platform%02d" % (i + 1), center, Vector3(2.1, 0.3, lengths[i]), platform)
		_visual_box("PlatformMarker%02d" % (i + 1), center + Vector3(0.0, 0.17, lengths[i] * 0.37), Vector3(1.7, 0.035, 0.12), marker)
	for row in 15:
		for column in 4:
			_spike(Vector3(-2.25 + column * 1.5, -1.55, 4.35 - row * 1.0))
	var mechanism := PRESS_TARGET_SCRIPT.new() as PressTarget
	mechanism.marker_style = &"cross"
	mechanism.name = "StickyMechanism"
	mechanism.position = Vector3(-1.72, 1.05, -14.05)
	mechanism.sticky_applied.connect(_on_sticky_applied)
	add_child(mechanism)
	_block("PressRailWest", Vector3(-2.2, 2.1, TRAP_Z), Vector3(0.75, 4.2, 2.5), stone)
	_block("PressRailEast", Vector3(2.2, 2.1, TRAP_Z), Vector3(0.75, 4.2, 2.5), stone)
	_press_beam = _press_body(Vector3(0.0, 1.60, TRAP_Z))
	_visual_box("SafeCheckpoint", Vector3(0.0, 0.03, -13.15), Vector3(1.7, 0.06, 0.16), Color(0.35, 0.94, 0.73), true)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.09, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.68, 0.70)
	environment.ambient_light_energy = 0.82
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 4.0, -15.0)
	light.light_color = Color(1.0, 0.74, 0.49)
	light.light_energy = 1.45
	light.omni_range = 12.0
	add_child(light)

func _block(label: String, center: Vector3, size: Vector3, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	body.add_child(mesh)
	add_child(body)


func _press_body(center: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "PressBeam"
	body.collision_layer = 1
	body.collision_mask = 0
	body.sync_to_physics = true
	body.position = center
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.7, 2.5, 1.0)
	collider.shape = shape
	body.add_child(collider)
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	slab.mesh = box
	slab.material_override = _material(Color(0.66, 0.34, 0.33))
	body.add_child(slab)
	var spike_material := _material(Color(0.78, 0.42, 0.31))
	for x_index in 7:
		for z_side in [-0.28, 0.28]:
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.16
			cone.bottom_radius = 0.0
			cone.height = 0.20
			spike.mesh = cone
			spike.position = Vector3(-1.5 + x_index * 0.5, -1.35, z_side)
			spike.material_override = spike_material
			body.add_child(spike)
	for x_index in 7:
		for y_row in [-0.45, 0.55]:
			var front_spike := MeshInstance3D.new()
			var front_cone := CylinderMesh.new()
			front_cone.top_radius = 0.16
			front_cone.bottom_radius = 0.0
			front_cone.height = 0.22
			front_spike.mesh = front_cone
			front_spike.rotation.x = -PI * 0.5
			front_spike.position = Vector3(-1.5 + x_index * 0.5, y_row, 0.61)
			front_spike.material_override = spike_material
			body.add_child(front_spike)
	add_child(body)
	return body

func _visual_box(label: String, center: Vector3, size: Vector3, tint: Color, glow: bool = false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = center
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(tint, glow)
	add_child(visual)
	return visual


func _spike(at: Vector3) -> void:
	var visual := MeshInstance3D.new()
	visual.position = at
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.22
	spike_mesh.height = 0.82
	visual.mesh = spike_mesh
	visual.material_override = _material(Color(0.72, 0.29, 0.27))
	add_child(visual)


func _material(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.88
	if glow:
		material.emission_enabled = true
		material.emission = tint
	return material





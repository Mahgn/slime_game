extends CharacterBody3D
class_name ExitGuardian

signal died
signal health_changed(current: int, maximum: int)
signal phase_changed(source: Node, phase: StringName)
signal line_requested(source: ExitGuardian, origin: Vector3, direction: Vector3, cast_key: String)

const MAX_HEALTH := 180
const GRAVITY := 20.0
const MOVE_SPEED := 1.9
const RECOVERY_SECONDS := 1.3
const WINDUP_SECONDS := [1.0, 0.8, 1.1]
const ENGAGE_DISTANCE := [5.2, 2.55, 2.85]
const ATTACK_IDS: Array[StringName] = [&"line", &"arc", &"radial"]

var player_target: SlimeController
var health := MAX_HEALTH
var _phase: StringName = &"approach"
var _phase_left := 0.0
var _attack_index := 0
var _locked_direction := Vector3.FORWARD
var _aim_locked := false
var _cast_sequence := 0
var _received_casts: Dictionary = {}
var _sticky_left := 0.0
var _sticky_factor := 1.0
var _hit_flash_left := 0.0
var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _sticky_mark: MeshInstance3D
var _warning_line: MeshInstance3D
var _warning_arc: Node3D
var _warning_radial: MeshInstance3D


func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.2
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.82
	shape.height = 2.25
	collider.shape = shape
	collider.position.y = 1.13
	add_child(collider)
	_build_visual()
	health_changed.emit(health, MAX_HEALTH)


func _physics_process(delta: float) -> void:
	if _phase == &"dead":
		return
	_sticky_left = maxf(0.0, _sticky_left - delta)
	if _sticky_left <= 0.0:
		_sticky_factor = 1.0
	_sticky_mark.visible = _sticky_left > 0.0
	if not is_instance_valid(player_target) or not player_target.is_alive():
		_move(Vector3.ZERO, delta)
		return
	var to_player := player_target.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var toward := to_player.normalized() if distance > 0.01 else Vector3.FORWARD
	if _phase == &"approach":
		if distance > ENGAGE_DISTANCE[_attack_index] or not _has_line_of_sight():
			_move(toward, delta)
		else:
			_move(Vector3.ZERO, delta)
			_start_windup()
	elif _phase == &"windup":
		if not _aim_locked:
			_face(toward, delta)
		_move(Vector3.ZERO, delta)
		_phase_left -= delta
		if not _aim_locked and _phase_left <= 0.20:
			_aim_locked = true
			_locked_direction = -global_basis.z
			_locked_direction.y = 0.0
			_locked_direction = _locked_direction.normalized()
		if _phase_left <= 0.0:
			_strike()
			_attack_index = (_attack_index + 1) % ATTACK_IDS.size()
			_set_phase(&"recovery", RECOVERY_SECONDS)
	else:
		_move(Vector3.ZERO, delta)
		_phase_left -= delta
		if _phase_left <= 0.0:
			_set_phase(&"approach", 0.0)


func _process(delta: float) -> void:
	_hit_flash_left = maxf(0.0, _hit_flash_left - delta)
	_body_material.albedo_color = Color(0.96, 0.82, 0.59) if _hit_flash_left > 0.0 else Color(0.58, 0.61, 0.67)


func _move(wish: Vector3, delta: float) -> void:
	var speed := MOVE_SPEED * _sticky_factor
	velocity.x = move_toward(velocity.x, wish.x * speed, delta * 12.0)
	velocity.z = move_toward(velocity.z, wish.z * speed, delta * 12.0)
	velocity.y = minf(velocity.y, 0.0) if is_on_floor() else velocity.y - GRAVITY * delta
	if wish.length_squared() > 0.5:
		_face(wish, delta)
	move_and_slide()


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, delta * 5.5))


func _has_line_of_sight() -> bool:
	if not is_instance_valid(player_target):
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, player_target.global_position + Vector3.UP * 0.45, 3)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player_target


func _start_windup() -> void:
	_aim_locked = false
	_set_phase(&"windup", WINDUP_SECONDS[_attack_index])


func _set_phase(next_phase: StringName, seconds: float) -> void:
	_phase = next_phase
	_phase_left = seconds
	_warning_line.visible = next_phase == &"windup" and _attack_index == 0
	_warning_arc.visible = next_phase == &"windup" and _attack_index == 1
	_warning_radial.visible = next_phase == &"windup" and _attack_index == 2
	phase_changed.emit(self, next_phase)


func _strike() -> void:
	if not is_instance_valid(player_target) or not player_target.is_alive():
		return
	_cast_sequence += 1
	var cast_key := "guardian_%d_%d" % [get_instance_id(), _cast_sequence]
	if _attack_index == 0:
		line_requested.emit(self, global_position, _locked_direction, cast_key)
		return
	var delta := player_target.global_position - global_position
	delta.y = 0.0
	var distance := delta.length()
	if _attack_index == 1:
		if distance <= 2.65 and distance > 0.01 and _locked_direction.dot(delta.normalized()) >= 0.50 and _has_line_of_sight():
			player_target.receive_hit(16, cast_key, &"enemy")
	elif distance <= 3.0 and player_target.global_position.y - global_position.y <= 0.45 and _has_line_of_sight():
		player_target.receive_hit(20, cast_key, &"enemy")


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _phase == &"dead" or source_team != &"player" or amount <= 0 or cast_key.is_empty() or _received_casts.has(cast_key):
		return false
	_received_casts[cast_key] = true
	health = maxi(0, health - amount)
	_hit_flash_left = 0.14
	health_changed.emit(health, MAX_HEALTH)
	if health == 0:
		_die()
	return true


func apply_sticky(factor: float, seconds: float) -> void:
	if _phase == &"dead" or seconds <= 0.0:
		return
	_sticky_factor = maxf(0.75, clampf(factor, 0.1, 1.0))
	_sticky_left = seconds
	_sticky_mark.visible = true


func get_sticky_time_left() -> float:
	return _sticky_left


func clear_sticky() -> void:
	_sticky_left = 0.0
	_sticky_factor = 1.0
	_sticky_mark.visible = false


func is_alive() -> bool:
	return _phase != &"dead"


func get_attack_phase() -> StringName:
	return _phase


func _die() -> void:
	_phase = &"dead"
	collision_layer = 0
	set_physics_process(false)
	set_process(false)
	_warning_line.visible = false
	_warning_arc.visible = false
	_warning_radial.visible = false
	phase_changed.emit(self, &"dead")
	died.emit()
	queue_free()


func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "VisualRoot"
	root.position.y = 1.04
	add_child(root)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.58, 0.61, 0.67)
	_body_material.vertex_color_use_as_albedo = true
	_body_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body_material.roughness = 0.90
	_body = MeshInstance3D.new()
	_body.name = "FacetedStoneBody"
	_body.mesh = _boulder_mesh()
	_body.material_override = _body_material
	root.add_child(_body)
	var foot := MeshInstance3D.new()
	foot.name = "StoneFoot"
	var foot_shape := CylinderMesh.new()
	foot_shape.top_radius = 0.65
	foot_shape.bottom_radius = 0.76
	foot_shape.height = 0.22
	foot_shape.radial_segments = 9
	foot.mesh = foot_shape
	foot.position.y = -0.86
	foot.material_override = _material(Color(0.25, 0.28, 0.34))
	root.add_child(foot)
	var shard_material := _material(Color(0.55, 0.58, 0.64))
	shard_material.vertex_color_use_as_albedo = true
	shard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var shoulder := MeshInstance3D.new()
		shoulder.name = "StoneShoulder"
		shoulder.mesh = _rock_shard_mesh(0.48, 0.88, 0.48, side * 0.19)
		shoulder.position = Vector3(side * 0.59, -0.67, -0.04)
		shoulder.material_override = shard_material
		root.add_child(shoulder)
		var crown_side := MeshInstance3D.new()
		crown_side.name = "CrownSide"
		crown_side.mesh = _rock_shard_mesh(0.47, 0.78, 0.46, side * 0.21)
		crown_side.position = Vector3(side * 0.53, 0.65, 0.06)
		crown_side.material_override = shard_material
		root.add_child(crown_side)
	var crown_center := MeshInstance3D.new()
	crown_center.name = "CrownCenter"
	crown_center.mesh = _rock_shard_mesh(0.55, 1.02, 0.53, -0.08)
	crown_center.position = Vector3(0.0, 0.70, 0.11)
	crown_center.material_override = shard_material
	root.add_child(crown_center)
	var socket := MeshInstance3D.new()
	socket.name = "CoreSocket"
	var socket_shape := SphereMesh.new()
	socket_shape.radius = 0.46
	socket_shape.height = 0.76
	socket_shape.radial_segments = 8
	socket_shape.rings = 4
	socket.mesh = socket_shape
	socket.scale = Vector3(0.92, 1.0, 0.40)
	socket.position = Vector3(0.0, 0.09, -0.79)
	socket.material_override = _material(Color(0.13, 0.15, 0.19))
	root.add_child(socket)
	var core := MeshInstance3D.new()
	core.name = "AmberCore"
	var crystal := SphereMesh.new()
	crystal.radius = 0.29
	crystal.height = 0.61
	crystal.radial_segments = 6
	crystal.rings = 3
	core.mesh = crystal
	core.scale = Vector3(0.82, 1.0, 0.48)
	core.position = Vector3(0.0, 0.09, -0.93)
	core.material_override = _material(Color(1.0, 0.54, 0.14), true)
	root.add_child(core)
	var core_light := OmniLight3D.new()
	core_light.light_color = Color(1.0, 0.43, 0.13)
	core_light.light_energy = 0.48
	core_light.omni_range = 2.4
	core_light.position = Vector3(0.0, 0.09, -1.02)
	root.add_child(core_light)
	var fissure_material := _material(Color(1.0, 0.42, 0.13), true)
	for side in [-1.0, 1.0]:
		_add_fissure(root, Vector3(side * 0.21, 0.10, -0.91), Vector3(side * 0.42, 0.32, -0.80), fissure_material)
		_add_fissure(root, Vector3(side * 0.42, 0.32, -0.80), Vector3(side * 0.58, 0.45, -0.67), fissure_material)
		_add_fissure(root, Vector3(side * 0.40, -0.13, -0.81), Vector3(side * 0.55, -0.37, -0.70), fissure_material)
	_sticky_mark = MeshInstance3D.new()
	var sticky := TorusMesh.new()
	sticky.inner_radius = 0.91
	sticky.outer_radius = 1.03
	_sticky_mark.mesh = sticky
	_sticky_mark.position.y = -0.87
	_sticky_mark.material_override = _material(Color(0.18, 0.94, 0.75), true)
	_sticky_mark.visible = false
	root.add_child(_sticky_mark)
	_warning_line = _flat_box("LineWarning", Vector3(0.0, 0.04, -3.0), Vector3(1.84, 0.025, 5.84), Color(0.85, 0.27, 0.16))
	for side in [-0.88, 0.88]:
		var border := _flat_box("LineBorder", Vector3(side, 0.064, -3.0), Vector3(0.06, 0.022, 5.84), Color(1.0, 0.47, 0.22), _warning_line)
		border.position -= _warning_line.position
	_warning_arc = Node3D.new()
	_warning_arc.name = "ArcWarning"
	_warning_arc.position.y = 0.045
	add_child(_warning_arc)
	var wedge := MeshInstance3D.new()
	wedge.name = "ArcFill"
	wedge.mesh = _sector_mesh(2.65, 60.0)
	wedge.material_override = _warning_material(Color(0.86, 0.26, 0.16), 0.46)
	_warning_arc.add_child(wedge)
	_warning_radial = MeshInstance3D.new()
	_warning_radial.name = "RadialWarning"
	var ring := TorusMesh.new()
	ring.inner_radius = 2.78
	ring.outer_radius = 3.0
	_warning_radial.mesh = ring
	_warning_radial.position.y = 0.045
	_warning_radial.material_override = _material(Color(0.98, 0.39, 0.17), true)
	add_child(_warning_radial)
	var radial_fill := MeshInstance3D.new()
	radial_fill.name = "RadialFill"
	var disk := CylinderMesh.new()
	disk.bottom_radius = 3.0
	disk.top_radius = 3.0
	disk.height = 0.015
	radial_fill.mesh = disk
	radial_fill.position.y = -0.014
	radial_fill.material_override = _warning_material(Color(0.87, 0.28, 0.16), 0.32)
	_warning_radial.add_child(radial_fill)
	_warning_line.visible = false
	_warning_arc.visible = false
	_warning_radial.visible = false



func _boulder_mesh() -> ArrayMesh:
	var profile: Array[Vector2] = [Vector2(-0.81, 0.42), Vector2(-0.66, 0.68), Vector2(-0.27, 0.82), Vector2(0.25, 0.79), Vector2(0.70, 0.58), Vector2(0.98, 0.27)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in profile.size() - 1:
		for sector in 12:
			var a := _boulder_point(profile, ring, sector)
			var b := _boulder_point(profile, ring, sector + 1)
			var c := _boulder_point(profile, ring + 1, sector)
			var d := _boulder_point(profile, ring + 1, sector + 1)
			var shade := 0.81 + 0.04 * float((sector * 7 + ring * 3) % 5)
			var tint := Color(shade * 0.90, shade * 0.94, shade)
			_rock_facet(surface, a, c, b, tint)
			_rock_facet(surface, b, c, d, tint.darkened(0.055))
	return surface.commit()


func _boulder_point(profile: Array[Vector2], ring: int, sector: int) -> Vector3:
	var side := sector % 12
	var angle := TAU * float(side) / 12.0
	var radius := profile[ring].y * (1.0 + 0.055 * sin(float(side) * 2.21 + float(ring) * 0.72) + 0.035 * cos(float(side) * 3.82 - float(ring)))
	var height := profile[ring].x + 0.028 * sin(float(side) * 1.69 + float(ring))
	return Vector3(sin(angle) * radius, height, -cos(angle) * radius)


func _rock_shard_mesh(width: float, height: float, depth: float, lean: float) -> ArrayMesh:
	var low := width * 0.5
	var back := depth * 0.5
	var high := width * 0.16
	var tip_depth := depth * 0.14
	var points := [
		Vector3(-low, 0.0, -back), Vector3(low, 0.0, -back), Vector3(low, 0.0, back), Vector3(-low, 0.0, back),
		Vector3(-high + lean, height, -tip_depth), Vector3(high + lean, height, -tip_depth), Vector3(high + lean, height, tip_depth), Vector3(-high + lean, height, tip_depth)
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [[0, 4, 1], [1, 4, 5], [1, 5, 2], [2, 5, 6], [2, 6, 3], [3, 6, 7], [3, 7, 0], [0, 7, 4], [4, 7, 5], [5, 7, 6]]
	for face in faces:
		_rock_facet(surface, points[face[0]], points[face[1]], points[face[2]], Color(0.80 + float(face[0] % 3) * 0.07, 0.85, 0.92))
	return surface.commit()


func _rock_facet(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(point)


func _add_fissure(parent: Node3D, start: Vector3, finish: Vector3, tint: Material) -> void:
	var line := MeshInstance3D.new()
	line.name = "AmberFissure"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.022
	mesh.bottom_radius = 0.028
	mesh.height = start.distance_to(finish)
	mesh.radial_segments = 5
	line.mesh = mesh
	line.material_override = tint
	line.position = (start + finish) * 0.5
	line.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	parent.add_child(line)


func _sector_mesh(radius: float, half_angle_degrees: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 16:
		var first_angle := deg_to_rad(-half_angle_degrees + float(step) * half_angle_degrees * 2.0 / 16.0)
		var next_angle := deg_to_rad(-half_angle_degrees + float(step + 1) * half_angle_degrees * 2.0 / 16.0)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(Vector3(sin(first_angle) * radius, 0.0, -cos(first_angle) * radius))
		surface.add_vertex(Vector3(sin(next_angle) * radius, 0.0, -cos(next_angle) * radius))
	return surface.commit()


func _warning_material(tint: Color, opacity: float) -> StandardMaterial3D:
	var material := _material(tint, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = opacity
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_energy_multiplier = 0.35
	return material


func _flat_box(label: String, at: Vector3, size: Vector3, tint: Color, parent: Node3D = null) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.position = at
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	var material := _material(tint, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.64
	piece.material_override = material
	(parent if parent != null else self).add_child(piece)
	return piece


func _material(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.78
	if glow:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 0.95
	return material

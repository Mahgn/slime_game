extends Node3D
class_name SlimeIsometricPresentation

const OFFSET := Vector3(12.0, 13.9, 12.0)
const SILHOUETTE_SHADER := preload("res://shaders/isometric/occluded_silhouette.gdshader")
const POSE_PARAMETERS := ["gel_time", "gel_energy", "gel_motion", "crawl_phase", "crawl_amount"]
const COMBAT_IMPACT_SECONDS := 0.16
const COMBAT_IMPACT_DISTANCE := 0.055
const QUARTER_TURN_SECONDS := 0.30
const FREE_ROTATION_RADIANS_PER_PIXEL := 0.006

@onready var player: SlimeController = get_parent()
@onready var camera: Camera3D = $Camera3D

var zoom_target := 13.0
var center := Vector3.ZERO
var occluders: Array[MeshInstance3D] = []
var hidden: Array[MeshInstance3D] = []
var hidden_actors: Array[Node3D] = []
var reticle: MeshInstance3D
var follow_ring: MeshInstance3D
var occlusion_clock := 0.0
var floor_height := 0.0
var room_cutaway: SlimeRoomCutaway
var silhouette: MeshInstance3D
var _hero_visual: MeshInstance3D
var _silhouette_material: ShaderMaterial
var _combat_impact_remaining := 0.0
var _combat_impact_direction := Vector3.ZERO
var _combat_impact_strength := 0.0
var _combat_camera_offset := Vector3.ZERO
var _last_player_position := Vector3.ZERO
var quarter_turns_enabled := false
var free_rotation_enabled := false
var camera_yaw := 0.0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_elapsed := QUARTER_TURN_SECONDS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	quarter_turns_enabled = bool(player.get_parent().get_meta(&"camera_quarter_turns", false))
	free_rotation_enabled = quarter_turns_enabled and bool(player.get_parent().get_meta(&"camera_free_rotation", false))
	center = player.global_position + Vector3.UP * 0.45
	floor_height = player.global_position.y
	_last_player_position = player.global_position
	SlimeGameSettings.current().changed.connect(_on_camera_settings_changed)
	_update_camera(0.0)
	call_deferred("_collect_occluders")
	call_deferred("_build_silhouette")
	reticle = _ring(0.16, 0.20, Color("e8c68c"))
	reticle.name = "CursorTarget"
	reticle.set_as_top_level(true)
	add_child(reticle)
	follow_ring = _ring(0.49, 0.54, Color("91d2ad"))
	follow_ring.name = "SlimeGroundRing"
	follow_ring.set_as_top_level(true)
	add_child(follow_ring)


func _process(delta: float) -> void:
	floor_height = _ground_height(player.global_position)
	_update_camera(delta)
	if is_instance_valid(room_cutaway):
		room_cutaway.update_view(player, camera, delta)
	var trail_material := player._ground_trail.material_override as ShaderMaterial
	trail_material.set_shader_parameter("upper_floor_fade", room_cutaway.get_reveal_amount() if is_instance_valid(room_cutaway) else 0.0)
	_update_silhouette()
	reticle.visible = player.health > 0
	if player.get_parent().has_meta(&"isometric_exploration"):
		reticle.visible = false
		follow_ring.visible = false
	reticle.global_position = player.controls.get_aim_point()
	reticle.global_position.y = _ground_height(reticle.global_position) + 0.03
	follow_ring.global_position = Vector3(player.global_position.x, floor_height + 0.025, player.global_position.z)
	occlusion_clock -= delta
	if occlusion_clock <= 0.0:
		occlusion_clock = 0.12
		_update_occlusion()


func _update_camera(delta: float) -> void:
	_advance_camera_turn(delta)
	var wanted := player.global_position + Vector3.UP * 0.45
	if player.get_parent().has_meta(&"isometric_camera_center"):
		wanted = player.get_parent().get_meta(&"isometric_camera_center")
	# Teleports and checkpoint restores snap immediately; ordinary movement
	# follows with exponential smoothing, including changes in floor height.
	if delta == 0.0 or center.distance_to(wanted) > 8.0 or _last_player_position.distance_to(player.global_position) > 4.0:
		center = wanted
		_reset_combat_impact()
	else:
		center = center.lerp(wanted, 1.0 - exp(-delta * 9.0))
	_last_player_position = player.global_position
	_update_combat_impact(delta)
	camera.global_position = center + _view_offset()
	camera.look_at(center)
	# Translate the finished camera without changing its orthographic basis.
	camera.global_position += _combat_camera_offset
	camera.size = lerpf(camera.size, zoom_target, 1.0 - exp(-delta * 12.0))


func is_camera_turning() -> bool:
	return _turn_elapsed < QUARTER_TURN_SECONDS


func request_quarter_turn(direction: int) -> bool:
	if not quarter_turns_enabled or free_rotation_enabled or get_tree().paused or not player.is_alive() or is_camera_turning() or direction == 0:
		return false
	_turn_from = camera_yaw
	_turn_to = camera_yaw + signi(direction) * PI * 0.5
	_turn_elapsed = 0.0
	return true


func set_free_rotation(value: bool) -> void:
	free_rotation_enabled = quarter_turns_enabled and value
	# Switching modes preserves the exact view and cancels unfinished motion.
	_turn_elapsed = QUARTER_TURN_SECONDS
	_turn_from = camera_yaw
	_turn_to = camera_yaw


func rotate_free(pixels: float) -> void:
	if not free_rotation_enabled or get_tree().paused or not player.is_alive():
		return
	camera_yaw = wrapf(camera_yaw - pixels * FREE_ROTATION_RADIANS_PER_PIXEL, -PI, PI)
	_turn_from = camera_yaw
	_turn_to = camera_yaw


func _advance_camera_turn(delta: float) -> void:
	if not is_camera_turning() or get_tree().paused:
		return
	_turn_elapsed = minf(_turn_elapsed + maxf(delta, 0.0), QUARTER_TURN_SECONDS)
	var progress := _turn_elapsed / QUARTER_TURN_SECONDS
	camera_yaw = lerpf(_turn_from, _turn_to, smoothstep(0.0, 1.0, progress))
	if not is_camera_turning():
		# A quarter step can start at an arbitrary angle chosen in free mode.
		camera_yaw = wrapf(_turn_to, -PI, PI)


func _view_offset() -> Vector3:
	return OFFSET.rotated(Vector3.UP, camera_yaw)


func movement_basis() -> Basis:
	var right := camera.global_basis.x
	var back := camera.global_basis.z
	right.y = 0.0
	back.y = 0.0
	return Basis(right.normalized(), Vector3.UP, back.normalized())


func play_combat_impact(direction: Vector3, strength: float = 1.0) -> void:
	if get_tree().paused or SlimeGameSettings.current().camera_shake <= 0.0 or strength <= 0.0:
		return
	# Keep the kick in the image plane, independent of the hero's rotation.
	var view_axis := _view_offset().normalized()
	var screen_direction := direction - view_axis * direction.dot(view_axis)
	if screen_direction.length_squared() < 0.0001:
		screen_direction = camera.global_basis.x
	_combat_impact_direction = screen_direction.normalized()
	# Repeated contacts refresh one bounded pulse; they never accumulate drift.
	_combat_impact_strength = clampf(strength, 0.0, 1.0)
	_combat_impact_remaining = COMBAT_IMPACT_SECONDS


func get_combat_camera_offset() -> Vector3:
	# This is the currently rendered translation, also used by pointer aiming.
	return _combat_camera_offset


func _update_combat_impact(delta: float) -> void:
	var amount := SlimeGameSettings.current().camera_shake
	if amount <= 0.0 or _combat_impact_remaining <= 0.0:
		_combat_camera_offset = Vector3.ZERO
		return
	_combat_impact_remaining = maxf(0.0, _combat_impact_remaining - delta)
	var progress := 1.0 - _combat_impact_remaining / COMBAT_IMPACT_SECONDS
	var wave := cos(progress * TAU * 1.5) * pow(1.0 - progress, 2.0)
	var view_axis := _view_offset().normalized()
	var screen_direction := _combat_impact_direction - view_axis * _combat_impact_direction.dot(view_axis)
	_combat_camera_offset = screen_direction * COMBAT_IMPACT_DISTANCE * _combat_impact_strength * clampf(amount, 0.0, 1.0) * wave


func _reset_combat_impact() -> void:
	if is_instance_valid(camera):
		camera.global_position -= _combat_camera_offset
	_combat_camera_offset = Vector3.ZERO
	_combat_impact_remaining = 0.0
	_combat_impact_direction = Vector3.ZERO
	_combat_impact_strength = 0.0


func _on_camera_settings_changed() -> void:
	if SlimeGameSettings.current().camera_shake <= 0.0:
		_reset_combat_impact()


func _build_silhouette() -> void:
	_hero_visual = player.get_node("VisualRoot/SlimeHeroModelV5") as MeshInstance3D
	# Only the body surface: eyes and highlights should not show through stone.
	var body := ArrayMesh.new()
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _hero_visual.mesh.surface_get_arrays(0))
	silhouette = MeshInstance3D.new()
	silhouette.name = "OccludedSilhouette"
	silhouette.mesh = body
	silhouette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_silhouette_material = ShaderMaterial.new()
	_silhouette_material.shader = SILHOUETTE_SHADER
	_silhouette_material.render_priority = 10
	silhouette.material_override = _silhouette_material
	_hero_visual.add_child(silhouette)
	_update_silhouette()


func _update_silhouette() -> void:
	if not is_instance_valid(silhouette):
		return
	var source := _hero_visual.get_surface_override_material(0) as ShaderMaterial
	for parameter in POSE_PARAMETERS:
		_silhouette_material.set_shader_parameter(parameter, source.get_shader_parameter(parameter))
	_silhouette_material.set_shader_parameter("silhouette_opacity", 0.72 if player.health > 0 else 0.0)


func _belongs_to_actor(node: Node) -> bool:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is CharacterBody3D or ancestor is Area3D:
			return true
		ancestor = ancestor.get_parent()
	return false


func _update_occlusion() -> void:
	if is_instance_valid(room_cutaway):
		room_cutaway.update_view(player, camera)
		return
	for mesh in hidden:
		if is_instance_valid(mesh) and mesh.is_inside_tree():
			mesh.show()
	hidden.clear()
	for actor in hidden_actors:
		if is_instance_valid(actor) and actor.is_inside_tree():
			actor.show()
	hidden_actors.clear()
	# Protect feet and the lower body too, especially on the lower return path.
	var targets: Array[Vector3] = [player.global_position + Vector3.UP * 0.03,
		player.global_position + Vector3.UP * 0.45, player.global_position + Vector3.UP * 0.72]
	for actor in get_tree().get_nodes_in_group(&"enemies"):
		if not actor is Node3D or not actor.is_inside_tree():
			continue
		# Enemies on an upper floor disappear with that floor's visual slice.
		# Protect nearby combat targets, even while capture automation freezes AI.
		if not player.get_parent().has_meta(&"isometric_dressing_owned") and actor.global_position.y > floor_height + 1.35:
			if actor.visible:
				actor.hide()
				hidden_actors.append(actor)
		elif absf(actor.global_position.y - floor_height) < 1.35 and actor.global_position.distance_to(player.global_position) < 12.0:
			targets.append(actor.global_position + Vector3.UP * 0.6)
	for mesh in occluders:
		if not is_instance_valid(mesh) or not mesh.is_visible_in_tree():
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if not player.get_parent().has_meta(&"isometric_dressing_owned") and bounds.position.y > floor_height + 1.35:
			mesh.hide()
			hidden.append(mesh)
			continue
		var blocked := false
		for target in targets:
			for offset in [Vector3.ZERO, Vector3(0.55, 0, 0), Vector3(-0.55, 0, 0), Vector3(0, 0, 0.55), Vector3(0.55, 0.35, 0), Vector3(-0.55, 0.35, 0), Vector3(0, 0.35, 0.55)]:
				var point: Vector3 = target + offset
				var from := mesh.to_local(point + camera.global_basis.z * camera.far)
				var to := mesh.to_local(point)
				if mesh.get_aabb().intersects_segment(from, to) != null:
					blocked = true
					break
			if blocked:
				break
		if blocked:
			mesh.hide()
			hidden.append(mesh)


func _ground_height(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.15, at + Vector3.DOWN * 12.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit["position"].y) if not hit.is_empty() else floor_height


func _ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 8
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _collect_occluders() -> void:
	# Camera visibility only. New levels own their geometry, materials and light.
	if player.get_parent().has_meta(&"isometric_dressing_owned"):
		return
	for node in player.get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not _belongs_to_actor(mesh) and mesh.mesh != null:
			occluders.append(mesh)
	_update_occlusion()

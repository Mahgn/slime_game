extends Node3D

const OFFSET := Vector3(12.0, 13.9, 12.0)

var player: SlimeController
var zoom_target := 13.0
var center := Vector3.ZERO
var occluders: Array[MeshInstance3D] = []
var hidden: Array[MeshInstance3D] = []
var hidden_actors: Array[Node3D] = []
var reticle: MeshInstance3D
var follow_ring: MeshInstance3D
var occlusion_clock := 0.0
var floor_height := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	center = player.global_position + Vector3.UP * 0.45
	floor_height = player.global_position.y
	_update_camera(0.0)
	call_deferred("_collect_occluders")
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
	reticle.visible = player.health > 0
	if player.get_parent().has_meta(&"isometric_exploration"):
		reticle.visible = false
		follow_ring.visible = false
	reticle.global_position = player._get_camera_aim_point()
	reticle.global_position.y = _ground_height(reticle.global_position) + 0.03
	follow_ring.global_position = Vector3(player.global_position.x, floor_height + 0.025, player.global_position.z)
	occlusion_clock -= delta
	if occlusion_clock <= 0.0:
		occlusion_clock = 0.12
		_update_occlusion()


func _update_camera(delta: float) -> void:
	var wanted := player.global_position + Vector3.UP * 0.45
	if player.get_parent().has_meta(&"isometric_camera_center"):
		wanted = player.get_parent().get_meta(&"isometric_camera_center")
	# Teleports and checkpoint restores snap immediately; ordinary movement
	# follows with exponential smoothing, including changes in floor height.
	if delta == 0.0 or center.distance_to(wanted) > 8.0:
		center = wanted
	else:
		center = center.lerp(wanted, 1.0 - exp(-delta * 9.0))
	player.camera.global_position = center + OFFSET
	player.camera.look_at(center)
	player.camera.size = lerpf(player.camera.size, zoom_target, 1.0 - exp(-delta * 12.0))


func _belongs_to_actor(node: Node) -> bool:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is CharacterBody3D or ancestor is Area3D:
			return true
		ancestor = ancestor.get_parent()
	return false


func _update_occlusion() -> void:
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
		var from := mesh.to_local(player.camera.global_position)
		var blocked := false
		for target in targets:
			for offset in [Vector3.ZERO, Vector3(0.55, 0, 0), Vector3(-0.55, 0, 0), Vector3(0, 0, 0.55), Vector3(0.55, 0.35, 0), Vector3(-0.55, 0.35, 0), Vector3(0, 0.35, 0.55)]:
				var to := mesh.to_local(target + offset)
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

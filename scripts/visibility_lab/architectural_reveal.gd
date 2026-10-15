extends SlimeRoomCutaway

const ARCHITECTURE = preload("res://shaders/visibility_lab/architecture.gdshader")
const OPEN_SECONDS := 0.28
const CLOSE_SECONDS := 0.48
const RELEASE_SECONDS := 0.45
const VIEW_RADIUS := 2.35
const RETAIN_RADIUS := 3.0
const COMBAT_VIEW_RADIUS := Spitter.ENGAGE_DISTANCE + 1.0
var geometry: Node3D
var support_y := 0.0
var protected_points: Array[Vector3] = []
var elapsed_update_time := 0.0
var _last_basis := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
var _last_density := -1.0

func setup(source: Node3D, theme: int) -> void:
	geometry = source
	sections.clear()
	_bodies.clear()
	materials.clear()
	for entry: Dictionary in source.sections:
		var section: Dictionary = entry.duplicate()
		section.bounds = source.global_transform * entry.bounds
		section.floor_y = float(entry.floor_y) + source.global_position.y
		section.top_y = float(entry.top_y) + source.global_position.y
		section.occlusion_bounds = []
		section.amount = 0.0
		section.wanted = false
		section.hold = 0.0
		section.support_reserved = false
		section.materials = []
		var copies: Dictionary = {}
		for mesh: MeshInstance3D in section.meshes:
			section.occlusion_bounds.append(mesh.global_transform * mesh.get_aabb())
			var original := mesh.material_override as StandardMaterial3D
			var key := original.get_instance_id()
			if not copies.has(key):
				var material := ShaderMaterial.new()
				material.shader = ARCHITECTURE
				material.set_shader_parameter("cutaway_amount",0.0)
				material.set_shader_parameter("base_color",original.albedo_color)
				material.set_shader_parameter("roughness",original.roughness)
				material.set_shader_parameter("emission_color",original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
				material.set_shader_parameter("patterned",original.roughness > 0.65)
				material.set_shader_parameter("style",theme)
				copies[key] = material
				section.materials.append(material)
				materials.append(material)
			mesh.material_override = copies[key]
		sections[section.id] = section
		_bodies[section.body.get_rid()] = section.id

func update_view(player: SlimeController, camera: Camera3D, delta: float = 0.0) -> void:
	if delta <= 0.0 or not is_instance_valid(geometry) or not is_instance_valid(player) or get_tree().paused:
		return
	elapsed_update_time += delta
	var density := float(camera.get_viewport().get_visible_rect().size.y)/camera.size
	var projection_changed := not camera.global_basis.is_equal_approx(_last_basis) or not is_equal_approx(density,_last_density)
	if projection_changed:
		for material: ShaderMaterial in materials:
			material.set_shader_parameter("camera_right",camera.global_basis.x)
			material.set_shader_parameter("camera_up",camera.global_basis.y)
			material.set_shader_parameter("pixels_per_meter",density)
		_last_basis = camera.global_basis
		_last_density = density
	# Changes of supported floor are physical; jumping under a bridge cannot select it.
	if player.is_on_floor():
		support_y = player.global_position.y
	var center := Vector3(player.global_position.x,support_y+0.06,player.global_position.z)
	protected_points = _points(center,VIEW_RADIUS)
	var retained := _points(center,RETAIN_RADIUS)
	var directions: Array[Vector3] = [camera.global_basis.z]
	if player.presentation.is_camera_turning():
		directions.append(player.presentation.back_at_yaw(player.presentation._turn_to))
	for id: String in sections:
		var section: Dictionary = sections[id]
		var above_support: bool = float(section.top_y) > support_y+0.3
		if section.role == "overhead":
			# Reserve an upcoming landing before the hero steps onto it. The ramp's
			# actual grounded rise predicts arrival; an airborne jump never does.
			var anticipated_support := support_y
			if player.is_on_floor():
				anticipated_support += maxf(0.0,player.get_real_velocity().y)*(CLOSE_SECONDS+0.2)
			if anticipated_support >= float(section.floor_y)-0.12:
				section.support_reserved = true
			elif support_y < float(section.floor_y)-1.6:
				section.support_reserved = false
			if bool(section.support_reserved):
				above_support = false
				section.wanted = false
				section.hold = 0.0
		var points: Array[Vector3] = retained if section.wanted else protected_points
		var blocked := false
		if enabled and above_support:
			for point: Vector3 in points:
				for direction: Vector3 in directions:
					if _blocks(section,point,direction):
						blocked = true
			# Enemy bodies and their warning floor are part of the local combat space.
			for actor in get_tree().get_nodes_in_group(&"enemies"):
				if not actor is Node3D or actor.global_position.distance_to(center) > COMBAT_VIEW_RADIUS or absf(actor.global_position.y-support_y)>0.5:
					continue
				for height: float in [0.06,0.65]:
					var point: Vector3 = actor.global_position+Vector3.UP*height
					for direction: Vector3 in directions:
						if _blocks(section,point,direction): blocked = true
		if blocked:
			section.hold = RELEASE_SECONDS
			section.wanted = true
		elif delta > 0.0:
			section.hold = maxf(0.0,float(section.hold)-delta)
			if float(section.hold) == 0.0: section.wanted = false
		var target := 1.0 if bool(section.wanted) else 0.0
		var before: float = section.amount
		section.amount = move_toward(float(section.amount),target,maxf(delta,0.0)/(OPEN_SECONDS if target>section.amount else CLOSE_SECONDS))
		if not is_equal_approx(before,float(section.amount)):
			for material: ShaderMaterial in section.materials:
				material.set_shader_parameter("cutaway_amount",smoothstep(0.0,1.0,float(section.amount)))

func _points(center: Vector3, radius: float) -> Array[Vector3]:
	var result: Array[Vector3] = [center,center+Vector3.UP*0.65]
	for x: int in range(-2,3):
		for z: int in range(-2,3):
			var offset := Vector3(float(x),0.0,float(z))*radius*0.5
			if offset.length()>radius+0.01: continue
			var point := center+offset
			var local_point: Vector3 = geometry.to_local(point)
			for region: Dictionary in geometry.floor_regions:
				if not region.rect.has_point(Vector2(local_point.x,local_point.z)): continue
				var floor_y: float = geometry.floor_height_at(local_point) if geometry.has_method("floor_height_at") else float(region.y)
				if absf(floor_y-local_point.y)<1.6:
					result.append(geometry.to_global(Vector3(local_point.x,floor_y+0.06,local_point.z)))
					break
	return result

func _blocks(section: Dictionary, point: Vector3, direction: Vector3) -> bool:
	var origin := point+direction*40.0
	if section.bounds.intersects_segment(origin,point) == null: return false
	# A doorway's bounding box contains empty air. Test its actual authored solids
	# before dissolving the whole assembly, so an open doorway stays recognisable.
	for bounds: AABB in section.occlusion_bounds:
		if bounds.intersects_segment(origin,point) != null: return true
	return false

func is_point_cut(collider: CollisionObject3D, point: Vector3) -> bool:
	if not _bodies.has(collider.get_rid()): return false
	var section: Dictionary = sections[_bodies[collider.get_rid()]]
	return float(section.amount)>0.98 and (section.role=="overhead" or point.y>float(section.floor_y)+0.24)

func get_reveal_amount() -> float:
	# The hero trail belongs to the floor and must not vanish with a wall or bridge.
	return 0.0

func set_enabled(value: bool) -> void:
	enabled = value
	# Mode comparisons restore by the same continuous transition, never an instant reset.
	if not value:
		for section: Dictionary in sections.values():
			section.wanted = false
			section.hold = 0.0

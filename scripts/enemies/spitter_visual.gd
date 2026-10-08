extends Node3D
class_name SpitterVisual

# Model-space contact points are immutable. Read mesh arrays during model
# preparation, never synchronously for every first hit/death in combat.
static var _death_points_by_mesh: Dictionary = {}

## Art only: feet compensate the visual torso; the combat root stays unchanged.
const DEATH_SECONDS := 0.92
const HURT_SECONDS := 0.23
const STANCE_FRACTION := 0.64
const STEP_OFFSETS := [0.0, 0.5, 0.62, 0.12]
const HEAD_PIVOT := Vector3(0.0, -0.035, -0.17)
@onready var rig: Node3D = $Rig
@onready var body: MeshInstance3D = $Rig/Body
@onready var face: Node3D = $Rig/Face
@onready var ground_contact: MeshInstance3D = $GroundContact
@onready var mouth: Node3D = $Rig/Face/Mouth
@onready var left_lid: Node3D = $Rig/Face/LeftEye/Lid
@onready var right_lid: Node3D = $Rig/Face/RightEye/Lid
@onready var dead_eyes: Array[Node3D] = [$Rig/Face/LeftEye/DeadEye, $Rig/Face/RightEye/DeadEye]
@onready var legs: Array[Node3D] = [$Rig/LeftFrontLeg, $Rig/RightFrontLeg, $Rig/LeftBackLeg, $Rig/RightBackLeg]

var animation_state: StringName = &"idle"
var _time := 0.0
var _step := 0.0
var _movement := 0.0
var _walk_direction := Vector3.FORWARD
var _head_rotation := Vector3.ZERO
var _hurt_left := 0.0
var _death_time := -1.0
var _death_start: Transform3D
var _death_floor_y := -0.68
var _death_surfaces: Array[Dictionary] = []
var _death_leg_bases: Array[Basis] = []
var _death_foot_bases: Array[Basis] = []
var _death_foot_positions: Array[Vector3] = []
var _death_face: Transform3D
var _leg_origins: Array[Vector3] = []
var _ankles: Array[Vector3] = []
var _feet: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _body_material: ShaderMaterial
var _eye_materials: Array[ShaderMaterial] = []
var _limb_materials: Array[ShaderMaterial] = []
var _mouth_materials: Array[ShaderMaterial] = []
var _initial_rig_position := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_initial_rig_position = rig.position
	for leg in legs:
		_leg_origins.append(leg.position)
		var foot := leg.get_node("Foot") as Node3D
		_feet.append(foot)
		_ankles.append(foot.position)
	# Duplicate once per distinct material per creature, keeping intra-rig sharing.
	var unique: Dictionary = {}
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var original := mesh_node.material_override as ShaderMaterial
		if original == null:
			continue
		var key := original.get_instance_id()
		if not unique.has(key):
			unique[key] = original.duplicate() as ShaderMaterial
			if original.shader == (body.material_override as ShaderMaterial).shader:
				_materials.append(unique[key])
		mesh_node.material_override = unique[key]
	_body_material = body.material_override as ShaderMaterial
	_body_material.set_shader_parameter("head_pose", face.transform)
	for lid in [left_lid, right_lid]:
		_eye_materials.append(lid.get_node("Iris").material_override as ShaderMaterial)
	for leg in legs:
		_limb_materials.append(leg.get_node("Shin").material_override as ShaderMaterial)
	for part in mouth.get_children():
		_mouth_materials.append(part.material_override as ShaderMaterial)
	for mesh_node in _contact_meshes():
		if not _death_points_by_mesh.has(mesh_node.mesh):
			var points := PackedVector3Array()
			var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for index in range(0,vertices.size(),8): points.append(vertices[index])
			_death_points_by_mesh[mesh_node.mesh] = points
	set_process(false)


func _contact_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = [body]
	for leg in legs:
		result.append(leg.get_node("Shin") as MeshInstance3D)
		result.append(leg.get_node("Foot/WebbedFoot") as MeshInstance3D)
	return result


func animate(delta: float, local_velocity: Vector3, phase: StringName, progress: float) -> void:
	if _death_time >= 0.0:
		return
	_time += delta
	_hurt_left = maxf(0.0, _hurt_left - delta)
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	_movement = move_toward(_movement, clampf(speed / 0.38, 0.0, 1.0), delta * 4.5)
	if speed > 0.02:
		_walk_direction = Vector3(local_velocity.x, 0.0, local_velocity.z).normalized()
	_step += delta * speed * 1.4
	var breath := sin(_time * 2.25) * 0.72 + sin(_time * 3.71 + 0.7) * 0.28
	var windup := smoothstep(0.10, 1.0, progress) if phase == &"windup" else 0.0
	var release := 1.0 - smoothstep(0.0, 0.085, progress) if phase == &"recovery" else 0.0
	var recoil := smoothstep(0.0, 0.035, progress) * (1.0 - smoothstep(0.035, 0.30, progress)) if phase == &"recovery" else 0.0
	var charge := maxf(windup, release)
	var hurt := sin((_hurt_left / HURT_SECONDS) * PI)
	var weight_shift := sin(_step * TAU) * _movement
	animation_state = phase if phase != &"idle" else (&"walk" if _movement > 0.08 else &"idle")
	if _hurt_left > 0.0:
		animation_state = &"hurt"
	rig.position = _initial_rig_position + Vector3(weight_shift * 0.020, -absf(weight_shift) * 0.015 - charge * 0.027, charge * 0.024 + recoil * 0.032 + hurt * 0.025)
	rig.rotation = Vector3(-charge * 0.045 + recoil * 0.065 + hurt * 0.04, sin(_step * TAU - 0.4) * _movement * 0.024, weight_shift * 0.044 + hurt * 0.02)
	# No whole-body inflation: breathing and cheek volume are local deformations.
	body.scale = Vector3.ONE
	for material in _mouth_materials:
		material.set_shader_parameter("open_amount", charge + recoil * 0.60)
	var idle_look := Vector3(sin(_time * 0.83) * 0.028, sin(_time * 0.51) * 0.085, sin(_time * 0.67) * 0.018)
	var head_target := idle_look * (1.0 - charge) * (1.0 - _movement * 0.6)
	head_target += Vector3(charge * 0.055 - recoil * 0.10 + hurt * 0.085, hurt * 0.045, -weight_shift * 0.035)
	_head_rotation = _head_rotation.lerp(head_target, 1.0 - exp(-delta * 13.0))
	face.rotation = _head_rotation
	face.position = HEAD_PIVOT + Vector3(0.0, -recoil * 0.008, -recoil * 0.026 + charge * 0.008)
	var blink_phase := fmod(_time, 4.7)
	var blink := 1.0 - sin((blink_phase - 4.10) / 0.18 * PI) * 0.94 if blink_phase > 4.10 and blink_phase < 4.28 and phase == &"idle" else 1.0
	for index in _eye_materials.size():
		_eye_materials[index].set_shader_parameter("blink_amount", clampf(1.0 - blink + charge * 0.10 + hurt * (0.4 if index == 0 else 0.48), 0.0, 1.0))
		_eye_materials[index].set_shader_parameter("gaze", Vector2(-_head_rotation.y * 0.8, charge * 0.045 - hurt * 0.06))
	for index in legs.size():
		var cycle := fposmod(_step + STEP_OFFSETS[index], 1.0)
		var travel: float
		var lift := 0.0
		if cycle < STANCE_FRACTION:
			# Constant backward travel in stance, a short eased return through the air.
			travel = lerpf(0.229, -0.229, cycle / STANCE_FRACTION)
		else:
			var swing := (cycle - STANCE_FRACTION) / (1.0 - STANCE_FRACTION)
			travel = lerpf(-0.229, 0.229, smoothstep(0.0, 1.0, swing))
			lift = pow(sin(swing * PI), 1.35) * 0.070
		var planted := _leg_origins[index] + _ankles[index]
		var target := planted + (_walk_direction * travel + Vector3.UP * lift) * _movement
		_place_foot(index, rig.transform.affine_inverse() * target)
	for material in _materials:
		material.set_shader_parameter("hit_amount", hurt)
	_body_material.set_shader_parameter("charge_amount", charge)
	_body_material.set_shader_parameter("mouth_open", charge + recoil * 0.45)
	_body_material.set_shader_parameter("breath_amount", breath)
	var swallow := sin(clampf(progress / 0.65, 0.0, 1.0) * PI) if phase == &"windup" else 0.0
	_body_material.set_shader_parameter("throat_amount", swallow * 0.65 + charge * 0.25)
	_body_material.set_shader_parameter("head_pose", face.transform)


func _place_foot(index: int, target: Vector3) -> void:
	var offset := target - _leg_origins[index]
	# The shin bends around an elbow/hock; its thickness and the foot stay intact.
	legs[index].basis = Basis.IDENTITY
	_feet[index].position = offset
	_feet[index].basis = rig.basis.inverse()
	_limb_materials[index].set_shader_parameter("limb_target", offset)


func play_hurt() -> void:
	if _death_time < 0.0:
		_hurt_left = HURT_SECONDS


func play_death(ground_position: Vector3) -> void:
	if _death_time >= 0.0:
		return
	animation_state = &"death"
	_death_time = 0.0
	_death_start = rig.transform
	_death_face = face.transform
	_death_floor_y = to_local(ground_position).y
	add_to_group(&"spitter_remains")
	left_lid.hide()
	right_lid.hide()
	for eye in dead_eyes:
		eye.show()
	for leg in legs:
		_death_leg_bases.append(leg.basis)
	for foot in _feet:
		_death_foot_bases.append(foot.basis)
		_death_foot_positions.append(foot.position)
	for material in _materials:
		material.set_shader_parameter("hit_amount", 0.0)
		material.set_shader_parameter("charge_amount", 0.0)
		material.set_shader_parameter("mouth_open", 0.0)
		material.set_shader_parameter("breath_amount", 0.0)
		material.set_shader_parameter("throat_amount", 0.0)
	# Sample the visible surface once. Contact follows the body and folding feet,
	# without adding a physics corpse or scaling the model to make it fit the floor.
	for mesh_node in _contact_meshes():
		_death_surfaces.append({"node": mesh_node, "points": _death_points_by_mesh[mesh_node.mesh]})
	set_process(true)


static func finish_on_result(room: Node) -> void:
	# Only dead room-owned art may finish under the result screen's combat pause.
	for remains in room.get_tree().get_nodes_in_group(&"spitter_remains"):
		if room.is_ancestor_of(remains):
			remains.process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _death_time < 0.0 or animation_state == &"dead":
		return
	_death_time = minf(_death_time + delta, DEATH_SECONDS)
	# A brief loss of balance, an accelerating fall, then one small contact settle.
	var fall := smoothstep(0.0, 0.16, _death_time) * 0.12
	fall += pow(clampf((_death_time - 0.16) / 0.39, 0.0, 1.0), 2.0) * 0.88
	var contact := clampf((_death_time - 0.55) / 0.30, 0.0, 1.0)
	var settle := sin(contact * PI) * (1.0 - contact) * 0.065
	rig.rotation = _death_start.basis.get_euler().lerp(Vector3(1.45, 0.0, -0.15), fall) + Vector3(settle * 0.35, 0.0, -settle)
	rig.scale = Vector3.ONE
	var slack := smoothstep(0.05, 0.35, _death_time)
	var relaxed_head := Transform3D(Basis.from_euler(Vector3(-0.60, 0.0, 0.0)), HEAD_PIVOT)
	face.transform = _death_face.interpolate_with(relaxed_head, smoothstep(0.10, 0.68, _death_time))
	_body_material.set_shader_parameter("head_pose", face.transform)
	for index in legs.size():
		var side := -1.0 if index == 0 or index == 2 else 1.0
		var relaxed := Basis.from_euler(Vector3(0.18 if index < 2 else -0.25, 0.0, -side * 0.62))
		var start := _death_leg_bases[index]
		legs[index].basis = Basis(start.x.lerp(relaxed.x, slack), start.y.lerp(relaxed.y, slack), start.z.lerp(relaxed.z, slack))
		var foot_start := _death_foot_bases[index]
		_feet[index].basis = Basis(foot_start.x.lerp(Vector3.RIGHT, slack), foot_start.y.lerp(Vector3.UP, slack), foot_start.z.lerp(Vector3.BACK, slack))
		_feet[index].position = _death_foot_positions[index].lerp(_ankles[index], slack)
		_limb_materials[index].set_shader_parameter("limb_target", _feet[index].position)
	for material in _mouth_materials:
		material.set_shader_parameter("open_amount", 0.16)
	var grounded_y := _death_floor_y - _lowest_surface_y() + 0.006
	rig.position = Vector3(_death_start.origin.x + fall * 0.20,
		lerpf(_death_start.origin.y, grounded_y, smoothstep(0.0, 0.10, _death_time)),
		_death_start.origin.z + fall * 0.035)
	ground_contact.position = Vector3(rig.position.x, _death_floor_y + 0.008, rig.position.z)
	if _death_time >= DEATH_SECONDS:
		animation_state = &"dead"
		_death_surfaces.clear()
		set_process(false)


func _lowest_surface_y() -> float:
	var lowest := INF
	var inverse_rig := rig.global_transform.affine_inverse()
	for surface in _death_surfaces:
		var mesh_node: MeshInstance3D = surface["node"]
		var oriented := Transform3D(rig.basis, Vector3.ZERO) * inverse_rig * mesh_node.global_transform
		for point: Vector3 in surface["points"]:
			if mesh_node == body:
				var weight := smoothstep(-0.35, -0.15, point.y) * (1.0 - smoothstep(-0.22, 0.22, point.z))
				point = point.lerp(face.transform * (point - HEAD_PIVOT), weight)
			elif mesh_node.name == &"Shin":
				var material := mesh_node.material_override as ShaderMaterial
				var rest: Vector3 = material.get_shader_parameter("limb_rest")
				var target: Vector3 = material.get_shader_parameter("limb_target")
				point += (target - rest) * clampf(point.y / rest.y, 0.0, 1.0)
			lowest = minf(lowest, (oriented * point).y)
	return lowest

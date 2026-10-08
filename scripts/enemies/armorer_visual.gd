extends Node3D
class_name ArmorerVisual

# Immutable geometry is shared; materials and animation remain per enemy.
# Rendering preparation populates this small, bounded set before the first wave.
static var _plate_meshes: Dictionary = {}
static var _rim_meshes: Dictionary = {}
static var _sphere_meshes: Dictionary = {}
static var _limb_meshes: Dictionary = {}
static var _warning_mesh: TorusMesh

## Visual only. The BorrowableEnemy body and its combat phases remain authoritative.
const SHELL_COLOR := Color(0.35, 0.55, 0.61)
const SHELL_DARK := Color(0.19, 0.34, 0.40)
const RIM_COLOR := Color(0.60, 0.83, 0.81)

var _rig: Node3D
var _head: Node3D
var _plates: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _leg_sides: Array[float] = []
var _leg_rows: Array[int] = []
var _shell_material: StandardMaterial3D
var _rim_material: StandardMaterial3D
var _warning: MeshInstance3D
var _phase: StringName = &"approach"
var _guard_enabled := false
var _guard_pose := 0.0
var _windup_pose := 0.0
var _walk := 0.0
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	set_process(false)


func set_phase(phase: StringName) -> void:
	_phase = phase
	_guard_enabled = phase == &"shell"


func consume_guard() -> void:
	_guard_enabled = false


func animate(delta: float, local_velocity: Vector3, hit_flash: bool) -> void:
	_clock += delta
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	_walk = move_toward(_walk, clampf(speed / 2.8, 0.0, 1.0), delta * 4.0)
	_guard_pose = move_toward(_guard_pose, 1.0 if _guard_enabled else 0.0, delta * 4.5)
	_windup_pose = move_toward(_windup_pose, 1.0 if _phase == &"windup" else 0.0, delta * 4.0)
	var stride := sin(_clock * 11.0) * _walk
	_rig.position.y = -0.085 * _guard_pose + 0.018 * absf(stride)
	_rig.rotation.x = -0.11 * _windup_pose + 0.055 * _guard_pose
	_rig.rotation.z = 0.025 * stride
	_head.position = Vector3(0.0, 0.58 - 0.065 * _guard_pose, -0.24 + 0.09 * _guard_pose - 0.035 * _windup_pose)
	_head.rotation.x = 0.12 * _guard_pose - 0.14 * _windup_pose
	for index in _plates.size():
		var plate := _plates[index]
		plate.rotation.x = -(0.36 - float(index) * 0.055) * _guard_pose - 0.05 * _windup_pose
		plate.position.y = 0.66 - 0.035 * _guard_pose
	for index in _legs.size():
		var leg := _legs[index]
		var opposite := -1.0 if (index + _leg_rows[index]) % 2 == 0 else 1.0
		leg.rotation.x = 0.13 * stride * opposite + 0.11 * _windup_pose * (1.0 if _leg_rows[index] == 0 else -0.4)
		leg.rotation.z = _leg_sides[index] * (0.19 * _guard_pose + 0.045 * stride * opposite)
	_shell_material.albedo_color = Color(1.0, 0.75, 0.66) if hit_flash else Color.WHITE
	_warning.visible = _phase == &"shell" or _phase == &"windup"
	if _warning.visible:
		var pulse := 1.0 + 0.07 * sin(_clock * 14.0)
		_warning.scale = Vector3(pulse, 1.0, pulse)
	_rim_material.emission_energy_multiplier = 0.32 + 0.42 * maxf(_guard_pose, _windup_pose)


func _build() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var underbody_material := _material(Color(0.13, 0.23, 0.28), 0.89)
	var limb_material := _material(Color(0.17, 0.29, 0.33), 0.83)
	var face_material := _material(Color(0.22, 0.37, 0.42), 0.84)
	var eye_material := _material(Color(0.92, 0.73, 0.39), 0.68)
	var pupil_material := _material(Color(0.07, 0.11, 0.13), 0.93)
	_shell_material = _material(Color.WHITE, 0.79)
	_shell_material.vertex_color_use_as_albedo = true
	_shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_material = _material(RIM_COLOR, 0.69)
	_rim_material.emission_enabled = true
	_rim_material.emission = RIM_COLOR * 0.58
	_rim_material.emission_energy_multiplier = 0.32
	var belly := SphereMesh.new()
	belly.radius = 0.5
	belly.height = 1.0
	_ellipsoid("Underbody", _rig, belly, Vector3(0.0, 0.56, 0.02), Vector3(0.91, 0.65, 1.10), underbody_material)
	for index in 4:
		var center_z := -0.37 + float(index) * 0.25
		var plate := Node3D.new()
		plate.name = "ShellPlate%d" % (index + 1)
		plate.position = Vector3(0.0, 0.66, center_z)
		_rig.add_child(plate)
		var width := 0.49 * (1.0 - 0.085 * float(index))
		var color := SHELL_COLOR.lerp(SHELL_DARK, float(index) * 0.14)
		_mesh("Carapace", plate, _plate_mesh(width, 0.19, color), _shell_material)
		_mesh("FrontRim", plate, _rim_mesh(width), _rim_material)
		_plates.append(plate)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.58, -0.24)
	_rig.add_child(_head)
	var head_mesh := SphereMesh.new()
	_ellipsoid("Face", _head, head_mesh, Vector3(0.0, 0.0, -0.035), Vector3(0.66, 0.50, 0.60), face_material)
	for side in [-1.0, 1.0]:
		var socket := SphereMesh.new()
		_ellipsoid("LeftSocket" if side < 0.0 else "RightSocket", _head, socket, Vector3(side * 0.19, 0.075, -0.27), Vector3(0.21, 0.21, 0.11), pupil_material)
		var eye := SphereMesh.new()
		_ellipsoid("LeftEye" if side < 0.0 else "RightEye", _head, eye, Vector3(side * 0.19, 0.075, -0.319), Vector3(0.128, 0.138, 0.052), eye_material)
		_add_limb("Mandible", _head, Vector3(side * 0.20, -0.10, -0.25), Vector3(side * 0.10, -0.21, -0.35), 0.075, 0.029, limb_material)
	for row in 3:
		for side in [-1.0, 1.0]:
			var leg := Node3D.new()
			leg.name = "%sLeg%d" % ["Left" if side < 0.0 else "Right", row + 1]
			leg.position = Vector3(side * 0.36, 0.53, -0.30 + float(row) * 0.30)
			_rig.add_child(leg)
			var knee := Vector3(side * 0.14, -0.11, -0.045)
			var toe := Vector3(side * 0.16, -0.49, -0.08)
			_add_limb("Upper", leg, Vector3.ZERO, knee, 0.12, 0.09, limb_material)
			_add_limb("Lower", leg, knee, toe, 0.085, 0.055, face_material)
			var foot := SphereMesh.new()
			_ellipsoid("Foot", leg, foot, toe + Vector3(0.0, -0.015, -0.025), Vector3(0.18, 0.13, 0.24), limb_material)
			_legs.append(leg)
			_leg_sides.append(side)
			_leg_rows.append(row)
	var warning_mesh := TorusMesh.new()
	warning_mesh.inner_radius = 0.60
	warning_mesh.outer_radius = 0.66
	if _warning_mesh == null: _warning_mesh = warning_mesh
	warning_mesh = _warning_mesh
	_warning = _mesh("Warning", self, warning_mesh, eye_material)
	_warning.position.y = 0.035
	_warning.visible = false


func _plate_mesh(width: float, half_length: float, color: Color) -> ArrayMesh:
	var key := [width,half_length,color]
	if _plate_meshes.has(key): return _plate_meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 4:
		var t0 := float(row) / 4.0
		var t1 := float(row + 1) / 4.0
		for column in 12:
			var a0 := -PI * 0.5 + PI * float(column) / 12.0
			var a1 := -PI * 0.5 + PI * float(column + 1) / 12.0
			var p00 := _plate_point(width, half_length, t0, a0)
			var p10 := _plate_point(width, half_length, t1, a0)
			var p11 := _plate_point(width, half_length, t1, a1)
			var p01 := _plate_point(width, half_length, t0, a1)
			var tint := color.lightened(0.13) if row == 0 else color.darkened(0.025 * float(column % 3))
			_triangle(tool, p00, p10, p11, tint)
			_triangle(tool, p00, p11, p01, tint)
	tool.generate_normals()
	var result := tool.commit()
	_plate_meshes[key] = result
	return result


func _rim_mesh(width: float) -> ArrayMesh:
	if _rim_meshes.has(width): return _rim_meshes[width]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for column in 12:
		var a0 := -PI * 0.5 + PI * float(column) / 12.0
		var a1 := -PI * 0.5 + PI * float(column + 1) / 12.0
		var p00 := _plate_point(width, 0.19, 0.015, a0) + Vector3.UP * 0.008
		var p10 := _plate_point(width, 0.19, 0.085, a0) + Vector3.UP * 0.008
		var p11 := _plate_point(width, 0.19, 0.085, a1) + Vector3.UP * 0.008
		var p01 := _plate_point(width, 0.19, 0.015, a1) + Vector3.UP * 0.008
		_triangle(tool, p00, p10, p11, Color.WHITE)
		_triangle(tool, p00, p11, p01, Color.WHITE)
	tool.generate_normals()
	var result := tool.commit()
	_rim_meshes[width] = result
	return result


func _plate_point(width: float, half_length: float, t: float, angle: float) -> Vector3:
	var profile := 0.89 + 0.11 * sin(t * PI)
	return Vector3(width * profile * sin(angle), 0.06 + 0.34 * profile * cos(angle), lerpf(-half_length, half_length, t))


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


func _add_limb(name: String, parent: Node3D, start: Vector3, finish: Vector3, start_radius: float, end_radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = start_radius
	mesh.bottom_radius = end_radius
	mesh.height = start.distance_to(finish)
	mesh.radial_segments = 7
	var key := Vector3(start_radius,end_radius,mesh.height)
	if not _limb_meshes.has(key): _limb_meshes[key] = mesh
	mesh = _limb_meshes[key]
	var part := _mesh(name, parent, mesh, material)
	part.position = (start + finish) * 0.5
	part.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())


func _ellipsoid(name: String, parent: Node3D, mesh: Mesh, at: Vector3, size: Vector3, material: Material) -> void:
	var part := _mesh(name, parent, mesh, material)
	part.position = at
	part.scale = size


func _mesh(name: String, parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	if mesh is SphereMesh:
		var key := [mesh.radius,mesh.height,mesh.radial_segments,mesh.rings,mesh.is_hemisphere]
		if not _sphere_meshes.has(key): _sphere_meshes[key] = mesh
		mesh = _sphere_meshes[key]
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 0.24
	return material

extends SceneTree

const MODEL_PATH := "res://scenes/enemies/spitter_model.tscn"
const SKIN_SHADER = preload("res://assets/shaders/spitter_skin.gdshader")
const EYE_SHADER = preload("res://assets/shaders/spitter_eye.gdshader")
const CONTACT_SHADER = preload("res://assets/shaders/spitter_contact.gdshader")
const MOUTH_SHADER = preload("res://assets/shaders/spitter_mouth.gdshader")
const SCULPT = preload("res://tools/spitter_sculpt_mesh.gd")
const SKIN_COLOR := Color(0.305, 0.245, 0.275)
var model: Node3D
var skin: ShaderMaterial
var cheek_material: ShaderMaterial
var pupil_material: StandardMaterial3D
var cross_material: StandardMaterial3D


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	model = Node3D.new()
	model.name = "SpitterModel"
	model.set_script(load("res://scripts/enemies/spitter_visual.gd"))
	skin = _skin(SKIN_COLOR, 0.0)
	cheek_material = ShaderMaterial.new()
	cheek_material.shader = MOUTH_SHADER
	cheek_material.set_shader_parameter("lip_color", SKIN_COLOR * Color(0.94, 0.89, 0.91))
	pupil_material = _material(Color(0.075, 0.034, 0.056), 0.82)
	pupil_material.metallic_specular = 0.12
	cross_material = _material(Color(0.98, 0.87, 0.59), 1.0)
	cross_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rig := _node("Rig", model)
	var contact_material := ShaderMaterial.new()
	contact_material.shader = CONTACT_SHADER
	var contact_plane := PlaneMesh.new()
	contact_plane.size = Vector2(1.65, 1.35)
	var contact := _mesh("GroundContact", model, contact_plane, contact_material)
	contact.position.y = -0.672
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var face := _node("Face", rig, SCULPT.HEAD_PIVOT)
	var sculpt := SCULPT.new()
	var body_mesh: ArrayMesh = sculpt.build()
	body_mesh.resource_name = "Spitter crouched sculpt v4"
	var mesh_path := "res://assets/models/spitter_body_v4.res"
	var mesh_error := ResourceSaver.save(body_mesh, mesh_path)
	if mesh_error != OK:
		push_error("Cannot save sculpt: %d" % mesh_error)
		model.free()
		quit(1)
		return
	body_mesh.take_over_path(mesh_path)
	_mesh("Body", rig, body_mesh, _skin(SKIN_COLOR, 1.0))
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0.0 else "Right"
		var eye_position := Vector3(side * SCULPT.EYE_POSITION.x, SCULPT.EYE_POSITION.y, SCULPT.EYE_POSITION.z)
		var eye := _node(prefix + "Eye", face, eye_position - SCULPT.HEAD_PIVOT)
		var lid := _node("Lid", eye)
		var eye_material := ShaderMaterial.new()
		eye_material.shader = EYE_SHADER
		eye_material.set_shader_parameter("lid_color", SKIN_COLOR)
		_ellipsoid("Iris", lid, Vector3(0.0, 0.0, -0.007), Vector3(0.113, 0.085, 0.055), eye_material)
		var dead_eye := _node("DeadEye", eye)
		dead_eye.visible = false
		_ellipsoid("Socket", dead_eye, Vector3(0.0, 0.0, -0.010), Vector3(0.108, 0.078, 0.048), pupil_material)
		for stroke in [-1.0, 1.0]:
			var bar := CapsuleMesh.new()
			bar.radius = 0.013
			bar.height = 0.138
			bar.radial_segments = 8
			bar.rings = 4
			var line := _mesh("CrossA" if stroke < 0.0 else "CrossB", dead_eye, bar, cross_material)
			line.position.z = -0.064
			line.rotation.z = stroke * PI * 0.25
		var front_position := Vector3(side * 0.395, -0.34, -0.21)
		var front := _node(prefix + "FrontLeg", rig, front_position)
		var front_end := Vector3(side * 0.10, -0.29, -0.12)
		_mesh("Shin", front, _leg_mesh(side, front_end, false), _limb_skin(front_position, front_end))
		var foot := _node("Foot", front, front_end)
		_add_foot(foot, 0.85)
		var back_position := Vector3(side * 0.52, -0.34, 0.32)
		var back := _node(prefix + "BackLeg", rig, back_position)
		var back_end := Vector3(side * 0.10, -0.285, -0.23)
		_mesh("Shin", back, _leg_mesh(side, back_end, true), _limb_skin(back_position, back_end))
		var back_foot := _node("Foot", back, back_end)
		_add_foot(back_foot, 1.0)
		_ellipsoid(prefix + "Nostril", face, Vector3(side * 0.087, 0.075, -0.553) - SCULPT.HEAD_PIVOT, Vector3(0.019, 0.007, 0.008), pupil_material)
	var mouth := _node("Mouth", face, SCULPT.MOUTH_POSITION - SCULPT.HEAD_PIVOT)
	_mesh("Lip", mouth, _lip_mesh(), cheek_material)
	var cavity_material := ShaderMaterial.new()
	cavity_material.shader = MOUTH_SHADER
	cavity_material.set_shader_parameter("cavity", 1.0)
	_mesh("Cavity", mouth, _mouth_mesh(), cavity_material)
	var packed := PackedScene.new()
	var packed_error := packed.pack(model)
	var save_error := ResourceSaver.save(packed, MODEL_PATH) if packed_error == OK else packed_error
	print("SPITTER_MODEL path=%s code=%d nodes=%d" % [MODEL_PATH, save_error, model.find_children("*", "", true, false).size()])
	model.free()
	quit(0 if save_error == OK else 1)


func _node(node_name: String, parent: Node, at: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	node.owner = model
	return node


func _mesh(node_name: String, parent: Node, geometry: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = geometry
	node.material_override = material
	parent.add_child(node)
	node.owner = model
	return node


func _ellipsoid(node_name: String, parent: Node, at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var node := _mesh(node_name, parent, sphere, material)
	node.position = at
	node.scale = dimensions
	return node


func _add_foot(parent: Node3D, size: float) -> void:
	var foot := _mesh("WebbedFoot", parent, _foot_mesh(), skin)
	foot.scale = Vector3.ONE * size


func _skin(color: Color, belly: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SKIN_SHADER
	material.set_shader_parameter("skin_color", color)
	material.set_shader_parameter("belly_amount", belly)
	material.set_shader_parameter("head_pose", Transform3D(Basis.IDENTITY, SCULPT.HEAD_PIVOT))
	return material


func _limb_skin(origin: Vector3, endpoint: Vector3) -> ShaderMaterial:
	var material := _skin(SKIN_COLOR, 0.0)
	material.set_shader_parameter("limb_enabled", true)
	material.set_shader_parameter("limb_rest", endpoint)
	material.set_shader_parameter("limb_target", endpoint)
	material.set_shader_parameter("skin_origin", origin)
	return material


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _lip_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	for ring in 49:
		var angle := TAU * float(ring) / 48.0
		var center := Vector3(cos(angle) * 0.251, sin(angle) * 0.013 + pow(cos(angle), 2.0) * 0.024, -0.031 + pow(cos(angle), 2.0) * 0.114)
		var outward := Vector3(cos(angle), sin(angle), 0.0)
		for side in 13:
			var cross_angle := TAU * float(side) / 12.0
			var normal := outward * cos(cross_angle) + Vector3.FORWARD * sin(cross_angle)
			vertices.append(center + normal * 0.009)
			normals.append(normal)
			colors.append(Color(sin(angle) * 0.5 + 0.5, cos(angle) * 0.5 + 0.5, 1.0))
	for ring in 48:
		for side in 12:
			var a := ring * 13 + side
			indices.append_array(PackedInt32Array([a, a + 14, a + 13, a, a + 1, a + 14]))
	return _arrays_mesh(vertices, normals, indices, colors)


func _mouth_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0.0, 0.0, -0.023)])
	var normals := PackedVector3Array([Vector3.FORWARD])
	var indices := PackedInt32Array()
	var colors := PackedColorArray([Color(0.5, 0.5, 1.0)])
	for i in 49:
		var angle := TAU * float(i) / 48.0
		vertices.append(Vector3(cos(angle) * 0.247, sin(angle) * 0.012 + pow(cos(angle), 2.0) * 0.024, -0.028 + pow(cos(angle), 2.0) * 0.112))
		normals.append(Vector3.FORWARD)
		colors.append(Color(sin(angle) * 0.5 + 0.5, cos(angle) * 0.5 + 0.5, 1.0))
		if i < 48:
			indices.append_array(PackedInt32Array([0, i + 1, i + 2]))
	return _arrays_mesh(vertices, normals, indices, colors)


func _leg_mesh(side: float, endpoint: Vector3, hind: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 13:
		var t := float(row) / 12.0
		var bend := Vector3(side * (0.12 if hind else 0.055), 0.0, 0.11 if hind else 0.025)
		var center := endpoint * t + sin(t * PI) * bend
		var radius := lerpf(0.086 if hind else 0.079, 0.034, t) + sin(t * PI) * 0.009
		for column in 21:
			var angle := TAU * float(column) / 20.0
			var normal := Vector3(cos(angle), 0.12, sin(angle)).normalized()
			vertices.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
			normals.append(normal)
	for row in 12:
		for column in 20:
			var a := row * 21 + column
			indices.append_array(PackedInt32Array([a, a + 22, a + 21, a, a + 1, a + 22]))
	return _arrays_mesh(vertices, normals, indices)


func _foot_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 13:
		var phi := -PI / 2.0 + PI * float(row) / 12.0
		for column in 49:
			var angle := TAU * float(column) / 48.0
			var front := maxf(0.0, -sin(angle))
			var lobes := 1.0 + front * 0.31 * cos(angle * 6.0)
			var x := 0.155 * cos(angle) * cos(phi) * lobes
			var z := 0.205 * sin(angle) * cos(phi) * lobes - 0.04
			vertices.append(Vector3(x, 0.024 * sin(phi), z))
			normals.append(Vector3(cos(angle) * cos(phi), sin(phi) * 5.0, sin(angle) * cos(phi)).normalized())
	for row in 12:
		for column in 48:
			var a := row * 49 + column
			indices.append_array(PackedInt32Array([a, a + 50, a + 49, a, a + 1, a + 50]))
	return _arrays_mesh(vertices, normals, indices)


func _arrays_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

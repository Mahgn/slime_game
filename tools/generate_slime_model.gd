extends SceneTree

const MODEL_PATH := "res://assets/models/slime_hero_v1.res"
const LAT_STEPS := 48
const SIDE_STEPS := 96
const EYE_STEPS := 32
const EYE_RINGS := 4


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var model := ArrayMesh.new()
	model.resource_name = "Slime Hero — sculpted body and eyes"
	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _body_arrays())
	model.surface_set_name(0, "gel_body")
	model.surface_set_material(0, _gel_material())

	var eye_details: Array[Dictionary] = []
	var highlight_details: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		var normal := Vector3(side * 0.48, 0.0, -0.877).normalized()
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		var eye_center := Vector3(side * 0.195, 0.09, -0.438)
		eye_details.append({
			"center": eye_center,
			"normal": normal,
			"rx": 0.13,
			"ry": 0.145,
			"lift": 0.025,
			"dome": 0.014,
		})
		highlight_details.append({
			"center": eye_center + tangent * -0.035 + Vector3.UP * 0.038,
			"normal": normal,
			"rx": 0.041,
			"ry": 0.045,
			"lift": 0.051,
			"dome": 0.002,
		})
		highlight_details.append({
			"center": eye_center + tangent * 0.038 + Vector3.UP * -0.023,
			"normal": normal,
			"rx": 0.014,
			"ry": 0.016,
			"lift": 0.051,
			"dome": 0.001,
		})

	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _oval_arrays(eye_details))
	model.surface_set_name(1, "forest_green_eyes")
	var eyes := StandardMaterial3D.new()
	eyes.albedo_color = Color(0.035, 0.31, 0.20)
	eyes.roughness = 0.3
	eyes.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eyes.metallic = 0.03
	eyes.cull_mode = BaseMaterial3D.CULL_DISABLED
	model.surface_set_material(1, eyes)

	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _oval_arrays(highlight_details))
	model.surface_set_name(2, "white_eye_glints")
	var glints := StandardMaterial3D.new()
	glints.albedo_color = Color(1.0, 0.99, 0.95)
	glints.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glints.cull_mode = BaseMaterial3D.CULL_DISABLED
	model.surface_set_material(2, glints)

	var result := ResourceSaver.save(model, MODEL_PATH)
	print("SLIME_MODEL_SAVE path=%s error=%d surfaces=%d aabb=%s" % [MODEL_PATH, result, model.get_surface_count(), model.get_aabb()])
	quit(0 if result == OK and model.get_surface_count() == 3 else 1)


func _gel_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded;
varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	float crown = smoothstep(-0.24, 0.39, model_pos.y);
	vec3 turquoise = vec3(0.06, 0.58, 0.63);
	vec3 mint = vec3(0.23, 0.82, 0.61);
	vec3 gel = mix(turquoise, mint, 0.12 + crown * 0.65);
	float edge_glow = smoothstep(0.25, 0.48, abs(model_pos.x)) * 0.11;
	float soft_sheen = exp(-pow((model_pos.x + 0.23) * 5.0, 2.0) - pow((model_pos.y - 0.23) * 7.0, 2.0)) * 0.35;
	float flank = smoothstep(0.20, 0.47, abs(model_pos.x));
	ALBEDO = gel * (1.0 - flank * 0.13) + vec3(0.18, 0.16, 0.13) * (edge_glow + soft_sheen);
	ROUGHNESS = 0.17;
	METALLIC = 0.0;
	SPECULAR = 0.82;
	EMISSION = vec3(0.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _body_arrays() -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for latitude in range(LAT_STEPS + 1):
		var phi := -PI * 0.5 + PI * float(latitude) / float(LAT_STEPS)
		for longitude in range(SIDE_STEPS + 1):
			var theta := TAU * float(longitude) / float(SIDE_STEPS)
			positions.append(_body_point(phi, theta))
			normals.append(_body_normal(phi, theta))
	for latitude in range(LAT_STEPS):
		for longitude in range(SIDE_STEPS):
			var a := latitude * (SIDE_STEPS + 1) + longitude
			var b := a + SIDE_STEPS + 1
			indices.append_array(PackedInt32Array([a, b + 1, b, a, a + 1, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _body_point(phi: float, theta: float) -> Vector3:
	var ring := pow(absf(cos(phi)), 0.44)
	var height := 0.395 * _signed_power(sin(phi), 0.44)
	var wobble := 1.0 + 0.022 * sin(theta * 3.0 + 0.6) + 0.014 * sin(theta * 5.0 - phi * 1.3)
	var x := 0.47 * ring * _signed_power(cos(theta), 0.69) * wobble
	var z := 0.47 * ring * _signed_power(sin(theta), 0.69) * wobble
	height += 0.015 * sin(theta * 2.0 + 0.5) * ring * maxf(0.0, sin(phi))
	return Vector3(x, height, z)


func _body_normal(phi: float, theta: float) -> Vector3:
	var step := 0.001
	var along_phi := _body_point(clampf(phi + step, -PI * 0.5, PI * 0.5), theta) - _body_point(clampf(phi - step, -PI * 0.5, PI * 0.5), theta)
	var along_theta := _body_point(phi, theta + step) - _body_point(phi, theta - step)
	var normal := along_phi.cross(along_theta)
	if normal.length_squared() < 0.00000001:
		return Vector3.UP if phi > 0.0 else Vector3.DOWN
	return normal.normalized()


func _signed_power(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), exponent)


func _oval_arrays(details: Array[Dictionary]) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for detail in details:
		var center: Vector3 = detail["center"]
		var outward: Vector3 = detail["normal"]
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		var rx: float = detail["rx"]
		var ry: float = detail["ry"]
		var lift: float = detail["lift"]
		var dome: float = detail["dome"]
		var first := positions.size()
		for ring_index in range(EYE_RINGS + 1):
			var radius := float(ring_index) / float(EYE_RINGS)
			for segment in range(EYE_STEPS + 1):
				var angle := TAU * float(segment) / float(EYE_STEPS)
				var offset := tangent * (cos(angle) * rx * radius) + Vector3.UP * (sin(angle) * ry * radius)
				var point := center + offset
				positions.append(Vector3(point.x, point.y, _front_surface_z(point.x, point.y) - lift - dome * (1.0 - radius * radius)))
				normals.append((outward + offset * (0.6 if dome > 0.005 else 0.0)).normalized())
		for ring_index in range(EYE_RINGS):
			for segment in range(EYE_STEPS):
				var a := first + ring_index * (EYE_STEPS + 1) + segment
				var b := a + EYE_STEPS + 1
				indices.append_array(PackedInt32Array([a, b + 1, b, a, a + 1, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays




func _front_surface_z(x: float, y: float) -> float:
	var vertical := pow(clampf(absf(y) / 0.395, 0.0, 1.0), 2.0 / 0.44)
	var ring := pow(maxf(0.0, 1.0 - vertical), 0.44 * 0.5)
	var horizontal_radius := maxf(0.001, 0.47 * ring)
	var horizontal := pow(clampf(absf(x) / horizontal_radius, 0.0, 1.0), 2.0 / 0.69)
	return -horizontal_radius * pow(maxf(0.0, 1.0 - horizontal), 0.69 * 0.5) * 1.025




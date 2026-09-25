extends SceneTree

const MODEL_PATH := "res://assets/models/slime_hero_v5.res"
const LAT_STEPS := 48
const SIDE_STEPS := 96
const EYE_STEPS := 32
const EYE_RINGS := 4
const EYE_RADIUS_X := 0.146
const EYE_RADIUS_Y := 0.160
const EYE_CENTER_PROTRUSION := 0.022
const EYE_RIM_PROTRUSION := -0.004
const GLINT_SURFACE_OFFSET := 0.003
const VERTEX_CODE := """
uniform float gel_time = 0.0;
uniform float gel_energy = 0.0;
uniform vec2 gel_motion = vec2(0.0);
uniform float crawl_phase = 0.0;
uniform float crawl_amount = 0.0;
varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
	// Alternate contact at the rear and front rim; leave the face and crown stable.
	float sole = 1.0 - smoothstep(-0.28, -0.04, VERTEX.y);
	float rear = smoothstep(0.02, 0.34, VERTEX.z);
	float front = smoothstep(0.02, 0.34, -VERTEX.z);
	float rear_stroke = max(sin(crawl_phase), 0.0);
	float front_stroke = max(-sin(crawl_phase), 0.0);
	VERTEX.y += sole * crawl_amount * (0.120 * rear * rear_stroke + 0.070 * front * front_stroke);
	VERTEX.z += sole * crawl_amount * (0.120 * rear * rear_stroke - 0.070 * front * front_stroke);
	VERTEX.x += sign(VERTEX.x) * sole * crawl_amount * 0.070 * rear * rear_stroke * smoothstep(0.14, 0.34, abs(VERTEX.x));
	float crown = smoothstep(-0.27, 0.35, VERTEX.y);
	float wave_x = sin(gel_time * 8.2 + VERTEX.y * 8.0 + VERTEX.z * 3.5);
	float wave_z = cos(gel_time * 7.4 + VERTEX.y * 6.0 + VERTEX.x * 4.0);
	VERTEX.x += crown * (gel_motion.x * 0.075 + wave_x * gel_energy * 0.052);
	VERTEX.z += crown * (gel_motion.y * 0.075 + wave_z * gel_energy * 0.043);
	VERTEX.y += sin(gel_time * 9.0 + VERTEX.x * 5.0 + VERTEX.z * 3.0) * gel_energy * 0.023 * crown;
}
"""


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var model := ArrayMesh.new()
	model.resource_name = "Slime Hero v5 — rounded cube with crawling contact wave"
	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _body_arrays())
	model.surface_set_name(0, "gel_body")
	model.surface_set_material(0, _shader_material(_body_fragment(), "cull_back"))

	var eye_details: Array[Dictionary] = []
	var highlight_details: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		var normal := Vector3(side * 0.48, 0.0, -0.877).normalized()
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		var eye_center := Vector3(side * 0.195, 0.09, -0.438)
		eye_details.append({"center": eye_center, "normal": normal, "rx": EYE_RADIUS_X, "ry": EYE_RADIUS_Y, "dome": 0.0})
		highlight_details.append({"center": eye_center + tangent * -0.035 + Vector3.UP * 0.038, "eye_center": eye_center, "normal": normal, "rx": 0.041, "ry": 0.045, "dome": 0.002})
		highlight_details.append({"center": eye_center + tangent * 0.038 - Vector3.UP * 0.023, "eye_center": eye_center, "normal": normal, "rx": 0.014, "ry": 0.016, "dome": 0.001})

	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _oval_arrays(eye_details))
	model.surface_set_name(1, "forest_green_eyes")
	model.surface_set_material(1, _shader_material("ALBEDO = vec3(0.035, 0.31, 0.20);", "unshaded, cull_disabled"))
	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _oval_arrays(highlight_details))
	model.surface_set_name(2, "white_eye_glints")
	model.surface_set_material(2, _shader_material("ALBEDO = vec3(1.0, 0.99, 0.95);", "unshaded, cull_disabled"))

	model.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _body_arrays(1.012))
	model.surface_set_name(3, "clear_gel_skin")
	model.surface_set_material(3, _shader_material(_shell_fragment(), "unshaded, blend_mix, depth_draw_never, cull_back"))

	var result := ResourceSaver.save(model, MODEL_PATH)
	print("SLIME_MODEL_SAVE path=%s error=%d surfaces=%d aabb=%s" % [MODEL_PATH, result, model.get_surface_count(), model.get_aabb()])
	quit(0 if result == OK and model.get_surface_count() == 4 else 1)


func _shader_material(fragment: String, modes: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode " + modes + ";\n" + VERTEX_CODE + "\nvoid fragment() {\n" + fragment + "\n}\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _body_fragment() -> String:
	return """
	float height_mix = smoothstep(-0.38, 0.38, model_pos.y);
	float radial = length(vec2(model_pos.x * 1.03, model_pos.y * 0.96));
	float inner = 1.0 - smoothstep(0.10, 0.54, radial);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.25);
	float swirl = sin(model_pos.y * 11.0 + model_pos.x * 6.0 + gel_time * 1.4) * 0.5 + 0.5;
	vec3 base = mix(vec3(0.045, 0.43, 0.49), vec3(0.23, 0.79, 0.65), 0.12 + height_mix * 0.69);
	base *= 1.0 - inner * 0.24;
	base += vec3(0.02, 0.05, 0.04) * swirl * 0.34;
	float ribbon_x = model_pos.x + 0.27 + 0.028 * sin(model_pos.y * 8.0 + gel_time * 0.8);
	float ribbon = exp(-pow(ribbon_x * 18.0, 2.0)) * smoothstep(-0.10, 0.16, model_pos.y) * (1.0 - smoothstep(0.26, 0.38, model_pos.y));
	ALBEDO = base + vec3(0.36, 0.48, 0.40) * rim * 0.32 + vec3(0.22, 0.30, 0.26) * ribbon;

    ROUGHNESS = 0.18;
    SPECULAR = 0.8;
    RIM = 0.42;
    RIM_TINT = 0.32;
    EMISSION = base * 0.12;
	"""


func _shell_fragment() -> String:
	return """
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float rim = pow(1.0 - facing, 1.35);
	float sheen = exp(-pow((model_pos.x + 0.20) * 5.0, 2.0) - pow((model_pos.y - 0.23) * 8.0, 2.0));
	ALBEDO = vec3(0.53, 0.98, 0.82);
	ALPHA = clamp(0.025 + rim * 0.43 + sheen * 0.10, 0.0, 0.53);
	"""

func _body_arrays(shell_scale: float = 1.0) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for latitude in range(LAT_STEPS + 1):
		var phi := -PI * 0.5 + PI * float(latitude) / float(LAT_STEPS)
		for longitude in range(SIDE_STEPS + 1):
			var theta := TAU * float(longitude) / float(SIDE_STEPS)
			positions.append(_body_point(phi, theta) * shell_scale)
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
	var vertical := sin(phi)
	var ring := pow(absf(cos(phi)), 0.36)
	var height := 0.395 * _signed_power(vertical, 0.44)
	var lower_fullness := 1.0 + 0.035 * maxf(0.0, -vertical) - 0.015 * maxf(0.0, vertical)
	var contour := 1.0 + 0.008 * sin(theta * 3.0 + 0.6) + 0.006 * sin(theta * 5.0 - phi * 1.3)
	var x := 0.47 * ring * _signed_power(cos(theta), 0.44) * lower_fullness * contour
	var z := 0.47 * ring * _signed_power(sin(theta), 0.44) * lower_fullness * contour
	height += 0.006 * sin(theta * 3.0 + 0.4) * ring * maxf(0.0, vertical)
	height -= 0.006 * sin(theta * 4.0 + 0.7) * ring * maxf(0.0, -vertical)
	return Vector3(x, height, z)

func _body_normal(phi: float, theta: float) -> Vector3:
	var point := _body_point(phi, theta)
	return Vector3(point.x * 0.88, point.y * 1.1, point.z * 0.88).normalized()

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
		var dome: float = detail["dome"]
		var eye_center: Vector3 = detail.get("eye_center", center)
		var glint_offset := GLINT_SURFACE_OFFSET if detail.has("eye_center") else 0.0
		var first := positions.size()
		for ring_index in range(EYE_RINGS + 1):
			var radius := float(ring_index) / float(EYE_RINGS)
			for segment in range(EYE_STEPS + 1):
				var angle := TAU * float(segment) / float(EYE_STEPS)
				var offset := tangent * (cos(angle) * rx * radius) + Vector3.UP * (sin(angle) * ry * radius)
				var point := center + offset
				# Sink the eye perimeter into the gel; the center stays gently raised.
				# Glints follow that same curved eye surface instead of hovering ahead.
				var eye_z := _front_surface_z(point.x, point.y) - _eye_protrusion(point.x, point.y, eye_center, tangent.x)
				positions.append(Vector3(point.x, point.y, eye_z - glint_offset - dome * (1.0 - radius * radius)))
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
	var vertical := pow(clampf(absf(y) / 0.395, 0.0, 1.0), 1.0 / 0.44) * signf(y)
	var ring := pow(maxf(0.0, 1.0 - vertical * vertical), 0.36 * 0.5)
	var fullness := 1.0 + 0.035 * maxf(0.0, -vertical) - 0.015 * maxf(0.0, vertical)
	var horizontal_radius := maxf(0.001, 0.47 * ring * fullness)
	var horizontal := pow(clampf(absf(x) / horizontal_radius, 0.0, 1.0), 2.0 / 0.44)
	return -horizontal_radius * pow(maxf(0.0, 1.0 - horizontal), 0.44 * 0.5)


func _eye_protrusion(x: float, y: float, center: Vector3, tangent_x: float) -> float:
	var horizontal := (x - center.x) / (EYE_RADIUS_X * absf(tangent_x))
	var vertical := (y - center.y) / EYE_RADIUS_Y
	var radius_squared := clampf(horizontal * horizontal + vertical * vertical, 0.0, 1.0)
	return lerpf(EYE_CENTER_PROTRUSION, EYE_RIM_PROTRUSION, pow(radius_squared, 4.0))


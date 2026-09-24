extends Node3D
class_name SlimeWhipVisual

const PREPARATION_SECONDS := 0.12
const ACTIVE_SECONDS := 0.08
const RECOVERY_SECONDS := 0.35
const VARIANT_RIGHT := 0
const VARIANT_LEFT := 1
const VARIANT_OVERHEAD := 2
const VARIANT_COUNT := 3
const RINGS := 14
const SIDES := 8
const ROOT_POINT := Vector3(0.36, -0.04, -0.31)
const OVERHEAD_ROOT_POINT := Vector3(-0.24, 0.18, -0.31)

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Tendril"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.96, 0.74)
	material.roughness = 0.23
	material.metallic = 0.02
	material.emission_enabled = true
	material.emission = Color(0.08, 0.43, 0.31)
	material.emission_energy_multiplier = 1.15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	hide()


func set_phase(phase: StringName, remaining: float, variant: int = VARIANT_RIGHT) -> void:
	var root_point := OVERHEAD_ROOT_POINT if variant == VARIANT_OVERHEAD else ROOT_POINT
	var control_a: Vector3
	var control_b: Vector3
	var tip: Vector3
	var width := 1.0
	match phase:
		&"preparation":
			var progress := clampf(1.0 - remaining / PREPARATION_SECONDS, 0.0, 1.0)
			var eased := progress * progress * (3.0 - 2.0 * progress)
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.45, -0.36)
				control_b = Vector3(-0.55, 0.68, -0.48).lerp(Vector3(-0.82, 1.04, -0.62), eased)
				tip = Vector3(-0.62, 0.72, -0.48).lerp(Vector3(-0.98, 1.16, -0.78), eased)
			else:
				control_a = Vector3(0.51, 0.12, -0.35)
				control_b = Vector3(0.62, 0.24, -0.48).lerp(Vector3(1.20, 0.34, -0.60), eased)
				tip = Vector3(0.57, 0.15, -0.49).lerp(Vector3(1.08, 0.32, -0.78), eased)
			width = 0.55 + 0.45 * eased
		&"active":
			var progress := clampf(1.0 - remaining / ACTIVE_SECONDS, 0.0, 1.0)
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.56, -0.51)
				control_b = Vector3(-0.64, 0.96, -1.25).lerp(Vector3(0.14, 0.51, -1.55), progress)
				tip = Vector3(0.28, -0.12, -1.96).lerp(Vector3(0.38, -0.23, -1.80), progress)
			else:
				control_a = Vector3(0.78, 0.18, -0.53)
				control_b = Vector3(1.42, 0.38, -1.39).lerp(Vector3(-0.80, 0.28, -1.38), progress)
				tip = Vector3(0.28, 0.07, -1.96).lerp(Vector3(-0.78, 0.04, -1.80), progress)
		&"recovery":
			var progress := clampf(1.0 - remaining / RECOVERY_SECONDS, 0.0, 1.0)
			if progress >= 0.72:
				hide()
				return
			var eased := smoothstep(0.0, 0.72, progress)
			if variant == VARIANT_OVERHEAD:
				control_a = Vector3(-0.38, 0.56, -0.51).lerp(Vector3(-0.32, 0.31, -0.36), eased)
				control_b = Vector3(0.14, 0.51, -1.55).lerp(Vector3(-0.44, 0.49, -0.48), eased)
				tip = Vector3(0.38, -0.23, -1.80).lerp(Vector3(-0.48, 0.53, -0.48), eased)
			else:
				control_a = Vector3(0.48, 0.13, -0.48).lerp(Vector3(0.43, 0.04, -0.34), eased)
				control_b = Vector3(-0.80, 0.28, -1.38).lerp(Vector3(0.53, 0.08, -0.46), eased)
				tip = Vector3(-0.78, 0.04, -1.80).lerp(Vector3(0.50, 0.02, -0.39), eased)
			width = 1.0 - 0.72 * eased
		_:
			hide()
			return
	if variant == VARIANT_LEFT:
		root_point.x = -root_point.x
		control_a.x = -control_a.x
		control_b.x = -control_b.x
		tip.x = -tip.x
	_draw_tendril(root_point, control_a, control_b, tip, width)
	show()


func _draw_tendril(root_point: Vector3, control_a: Vector3, control_b: Vector3, tip: Vector3, width: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(RINGS + 1):
		var t := float(ring) / float(RINGS)
		var center := _curve_point(t, root_point, control_a, control_b, tip)
		var before := _curve_point(maxf(0.0, t - 0.01), root_point, control_a, control_b, tip)
		var after := _curve_point(minf(1.0, t + 0.01), root_point, control_a, control_b, tip)
		var tangent := (after - before).normalized()
		var side_axis := tangent.cross(Vector3.UP).normalized()
		var up_axis := side_axis.cross(tangent).normalized()
		var radius := (lerpf(0.14, 0.055, t) + 0.025 * sin(PI * t)) * width
		if ring == RINGS:
			radius = 0.008 * width
		for side in range(SIDES + 1):
			var angle := TAU * float(side) / float(SIDES)
			var normal := (side_axis * cos(angle) + up_axis * sin(angle)).normalized()
			surface.set_normal(normal)
			surface.set_uv(Vector2(t, float(side) / float(SIDES)))
			surface.add_vertex(center + normal * radius)
	var stride := SIDES + 1
	for ring in range(RINGS):
		for side in range(SIDES):
			var a := ring * stride + side
			var b := a + stride
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(a + 1)
			surface.add_index(a + 1)
			surface.add_index(b)
			surface.add_index(b + 1)
	_mesh_instance.mesh = surface.commit()


func _curve_point(t: float, root_point: Vector3, control_a: Vector3, control_b: Vector3, tip: Vector3) -> Vector3:
	var inverse := 1.0 - t
	return root_point * inverse * inverse * inverse + control_a * 3.0 * inverse * inverse * t + control_b * 3.0 * inverse * t * t + tip * t * t * t
extends RefCounted

# Only the authored dungeon's structural assemblies use these private copies.
# Gameplay bodies and room-owned lights are deliberately not hidden/reparented.
const SOLID := preload("res://shaders/keepers/room_wall_solid.gdshader")
const INCLUDE := "\n#include \"res://shaders/keepers/room_wall_fade.gdshaderinc\"\n"
var _shaders: Dictionary = {}


func configure(geometry: Node3D, _rooms: Dictionary, _connections: Array) -> void:
	for section: Dictionary in geometry.cutaway.structural_sections:
		if bool(section.get("keep_full", false)):
			continue
		var copies: Dictionary = {}
		var meshes: Array[MeshInstance3D] = []
		for child in section.node.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh == null:
				continue
			if mesh.material_override != null:
				mesh.material_override = _material_copy(mesh.material_override, copies)
			else:
				for surface in mesh.mesh.get_surface_count():
					var source := mesh.get_active_material(surface)
					if source != null:
						mesh.set_surface_override_material(surface, _material_copy(source, copies))
			meshes.append(mesh)
		section["fade_meshes"] = meshes
	geometry.cutaway.set_render_callbacks(apply_section, Callable())


func _material_copy(source: Material, copies: Dictionary) -> Material:
	if copies.has(source):
		return copies[source]
	var material: ShaderMaterial
	if source is ShaderMaterial:
		material = source.duplicate() as ShaderMaterial
	elif source is StandardMaterial3D:
		var solid := source as StandardMaterial3D
		material = ShaderMaterial.new()
		material.shader = SOLID
		material.set_shader_parameter("base_color", solid.albedo_color)
		material.set_shader_parameter("use_vertex_color", solid.vertex_color_use_as_albedo)
		material.set_shader_parameter("surface_roughness", solid.roughness)
		material.set_shader_parameter("surface_metallic", solid.metallic)
		material.set_shader_parameter("emitted_color", solid.emission * solid.emission_energy_multiplier if solid.emission_enabled else Color.BLACK)
	else:
		push_warning("Wall fade skipped unsupported material")
		return source
	var shader := material.shader
	if shader == null:
		return source
	if not _shaders.has(shader):
		var variant := Shader.new()
		var code := shader.code
		var render_mode_at := code.find("render_mode ")
		var preamble_end := code.find(";", render_mode_at) + 1 if render_mode_at >= 0 else code.find(";") + 1
		code = code.insert(preamble_end, INCLUDE)
		code = _append_to_function(code, "vertex", "\nroom_wall_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n")
		var fragment_start := code.find("{", code.find("void fragment()")) + 1
		code = code.insert(fragment_start, "\nif (room_wall_coverage(FRAGCOORD.xy) < wall_reveal) { discard; }\n")
		variant.code = code
		variant.set_meta(&"room_wall_fade_capable", true)
		_shaders[shader] = variant
	material.shader = _shaders[shader]
	copies[source] = material
	return material


func _append_to_function(code: String, function_name: String, addition: String) -> String:
	var start := code.find("void " + function_name + "()")
	if start < 0:
		return code + "\nvoid " + function_name + "() {" + addition + "}\n"
	var opening := code.find("{", start)
	var nesting := 1
	var closing := opening + 1
	while nesting > 0 and closing < code.length():
		if code[closing] == "{": nesting += 1
		elif code[closing] == "}": nesting -= 1
		if nesting > 0: closing += 1
	return code.insert(closing, addition)


func apply_section(section: Dictionary, amount: float, plinth_y: float) -> void:
	var unique: Dictionary = {}
	var fully_hidden := amount >= 1.0
	section.node.visible = not fully_hidden
	for mesh: MeshInstance3D in section.get("fade_meshes", []):
		if not is_instance_valid(mesh):
			continue
		mesh.visible = not fully_hidden
		if mesh.material_override != null:
			unique[mesh.material_override] = true
		else:
			for surface in mesh.mesh.get_surface_count():
				unique[mesh.get_active_material(surface)] = true
	for material in unique:
		if material is ShaderMaterial:
			material.set_shader_parameter("wall_reveal", amount)
			material.set_shader_parameter("wall_plinth_y", plinth_y)

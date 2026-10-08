extends Node
class_name SlimeKeepersInkStyle

enum Style { ORIGINAL, OUTLINE, COMIC, DARK_COMIC, INK, POSTER, ENGRAVING }
const OUTLINE = preload("res://shaders/keepers/ink_outline.gdshader")
const PALETTE = preload("res://shaders/keepers/ink_palette.gdshader")
const LIGHTING := "\n#include \"res://shaders/keepers/ink_lighting.gdshaderinc\"\n"
const STYLE_NAMES := ["Исходный", "Контур", "Комикс", "Тёмный комикс", "Комикс: Тушь", "Комикс: Постер", "Комикс: Гравюра"]
var mode := Style.INK
var route: Node3D
var outline: MeshInstance3D
var palette: ColorRect
var style_label: Label
var _bindings: Array[Dictionary] = []
var _materials: Dictionary = {}
var _shaders: Dictionary = {}
var _lights: Array[Dictionary] = []
var _environment: Environment
var _ambient_color: Color
var _ambient_energy: float

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_passes()
	_collect_materials(route.geometry)
	_environment = (route.get_node("Environment") as WorldEnvironment).environment.duplicate()
	(route.get_node("Environment") as WorldEnvironment).environment = _environment
	_ambient_color = _environment.ambient_light_color
	_ambient_energy = _environment.ambient_light_energy
	# Animated hazard materials/lights retain their original owner and references.
	var lights: Array[Node] = route.geometry.find_children("*", "Light3D", true, false)
	lights.append(route.get_node("KeyLight"))
	for node in lights:
		var light := node as Light3D
		_lights.append({"node":light, "color":light.light_color, "energy":light.light_energy})
	_build_label()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ink-style="):
			mode = clampi(int(arg.trim_prefix("--ink-style=")), 0, STYLE_NAMES.size() - 1)
	set_mode(mode)

func _build_passes() -> void:
	outline = MeshInstance3D.new()
	outline.name = "GeometryInk"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	outline.mesh = quad
	outline.extra_cull_margin = 16384.0
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink := ShaderMaterial.new()
	ink.shader = OUTLINE
	# Render ink before translucent steam, trail and the occluded hero silhouette.
	ink.render_priority = -100
	outline.material_override = ink
	route.player.presentation.camera.add_child(outline)
	var grading := CanvasLayer.new()
	grading.name = "WorldInkPalette"
	grading.layer = 0
	add_child(grading)
	palette = ColorRect.new()
	palette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := ShaderMaterial.new()
	color.shader = PALETTE
	palette.material = color
	grading.add_child(palette)

func _collect_materials(parent: Node) -> void:
	for node in parent.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.material_override != null:
			_bind(mesh, -1, mesh.material_override)
		elif mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				if material != null:
					_bind(mesh, surface, material)

func _bind(mesh: MeshInstance3D, surface: int, source: Material) -> void:
	if not _materials.has(source):
		var styled: Material
		if source is ShaderMaterial:
			var shader: Shader = source.shader
			if shader == null or not shader.resource_path.begins_with("res://shaders/keepers/"):
				return
			if "ALPHA" in shader.code or "unshaded" in shader.code or "void light(" in shader.code:
				return
			if not _shaders.has(shader):
				var ink_shader := Shader.new()
				ink_shader.code = _graphic_shader_code(shader.code)
				_shaders[shader] = ink_shader
			styled = source.duplicate()
			styled.shader = _shaders[shader]
		elif source is StandardMaterial3D:
			if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return
			styled = source.duplicate()
			styled.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			styled.specular_mode = BaseMaterial3D.SPECULAR_TOON
			styled.roughness = maxf(source.roughness, 0.6)
		else:
			return
		_materials[source] = styled
	# Restore the original override, including null (a mesh-owned surface).
	_bindings.append({"mesh":mesh, "surface":surface, "original":mesh.material_override if surface<0 else mesh.get_surface_override_material(surface), "styled":_materials[source]})

func _graphic_shader_code(source: String) -> String:
	# Only our opaque facility shaders reach this function. The private variant
	# adds world-anchored strokes without editing the original shader resource.
	var vertex_tail := "\nink_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\nink_world_normal = MODEL_NORMAL_MATRIX * NORMAL;\n"
	var code := source
	var vertex_start := code.find("void vertex()")
	if vertex_start < 0:
		code += "\nvoid vertex() {" + vertex_tail + "}\n"
	else:
		var opening := code.find("{", vertex_start)
		var nesting := 1
		var closing := opening + 1
		while nesting > 0 and closing < code.length():
			if code[closing] == "{": nesting += 1
			elif code[closing] == "}": nesting -= 1
			if nesting > 0: closing += 1
		code = code.insert(closing, vertex_tail)
	var preamble_end := code.find(";") + 1
	var render_mode_at := code.find("render_mode ")
	if render_mode_at >= 0:
		preamble_end = code.find(";", render_mode_at) + 1
	return code.insert(preamble_end, LIGHTING)

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	style_label = Label.new()
	style_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	style_label.offset_left = -360
	style_label.offset_right = -24
	style_label.offset_top = 102
	style_label.offset_bottom = 134
	style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	style_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(style_label)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		cycle_style(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()

func cycle_style(direction: int = 1) -> void:
	set_mode(posmod(mode + direction, STYLE_NAMES.size()))

func set_mode(value: int) -> void:
	mode = clampi(value, 0, STYLE_NAMES.size() - 1)
	var comic := mode >= Style.COMIC
	var dark := mode == Style.DARK_COMIC
	var bold := mode == Style.INK
	var poster := mode == Style.POSTER
	var engraving := mode == Style.ENGRAVING
	outline.visible = mode != Style.ORIGINAL
	palette.visible = comic
	var edge_material := outline.material_override as ShaderMaterial
	edge_material.set_shader_parameter("width_pixels", 2.8 if bold else (2.1 if poster or engraving else 1.4))
	edge_material.set_shader_parameter("strength", 0.98 if bold or poster else 0.85)
	edge_material.set_shader_parameter("crease_strength", 0.22 if bold else (0.13 if engraving else 0.0))
	var color_material := palette.material as ShaderMaterial
	color_material.set_shader_parameter("dark_ink", 1.0 if dark else 0.0)
	color_material.set_shader_parameter("saturation", 1.38 if poster else (0.88 if engraving else 1.18))
	color_material.set_shader_parameter("poster_amount", 0.82 if poster else 0.0)
	color_material.set_shader_parameter("paper_amount", 0.32 if engraving else 0.0)
	style_label.text = "F6 / Shift+F6 · " + STYLE_NAMES[mode]
	for binding in _bindings:
		if not is_instance_valid(binding.mesh):
			continue
		var material: Material = binding.styled if comic else binding.original
		if binding.surface < 0:
			binding.mesh.material_override = material
		else:
			binding.mesh.set_surface_override_material(binding.surface, material)
	for material: Material in _materials.values():
		if material is ShaderMaterial:
			material.set_shader_parameter("ink_light_gain", 1.0 if dark else (1.32 if poster else 1.22))
			material.set_shader_parameter("ink_graphic", 1.0 if poster else 0.0)
			material.set_shader_parameter("ink_hatching", 1.0 if engraving else 0.0)
	_environment.ambient_light_color = (Color("8c89b3") if dark else Color("a9aec7")) if comic else _ambient_color
	_environment.ambient_light_energy = (0.34 if dark else 0.58) if comic else _ambient_energy
	for entry in _lights:
		var light: Light3D = entry.node
		if not is_instance_valid(light):
			continue
		if comic:
			light.light_color = Color("d8d5ff") if light is DirectionalLight3D else entry.color.lerp(Color("ffc77c"), 0.18)
			light.light_energy = entry.energy * ((1.18 if dark else 1.38) if light is DirectionalLight3D else 1.10)
		else:
			light.light_color = entry.color
			light.light_energy = entry.energy

func _exit_tree() -> void:
	if is_instance_valid(outline):
		outline.queue_free()

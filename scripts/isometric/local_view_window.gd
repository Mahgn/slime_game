extends RefCounted

# Deliberately authored pilot: the membrane passage, not every room in the game.
const MATERIAL_HELPER := preload("res://scripts/isometric/room_wall_fade_renderer.gd")
const SOLID := preload("res://shaders/keepers/room_wall_solid.gdshader")
const INCLUDE := "\n#include \"res://shaders/keepers/local_view_window.gdshaderinc\"\n"
const OPEN_SECONDS := 0.28
const CLOSE_SECONDS := 0.46
const RELEASE_HOLD := 0.35
const ENTER_DISTANCE := 2.8
const EXIT_DISTANCE := 3.6
var enabled := true
var amount := 0.0
var target := false
var center := Vector3.ZERO
var geometry: Node3D
var camera: Camera3D
var meshes: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var walls: Array[Dictionary] = []
var floor_rects: Array[Rect2] = []
var passage_a := Vector2.ZERO
var passage_b := Vector2.ZERO
var _hold := 0.0
var _copies: Dictionary = {}
var _shaders: Dictionary = {}
var _helper: RefCounted = MATERIAL_HELPER.new()

func configure(owner_geometry: Node3D, rooms: Dictionary, connections: Array) -> void:
	geometry = owner_geometry
	for link: Dictionary in connections:
		if link.a != "furnace" or link.b != "cistern": continue
		passage_a = Vector2(link.path[0].x,link.path[0].z)
		passage_b = Vector2(link.path[1].x,link.path[1].z)
		# The floor extends under the wall footprint. Include that supported
		# edge, otherwise a strip of coping remains suspended over the opening.
		var across := Vector2(0.0,float(link.width)*0.5)
		var along := Vector2(geometry.WALL_WIDTH*0.5,0.0)
		floor_rects.append(Rect2(passage_a-along-across,passage_b-passage_a+2.0*(along+across)))
	assert(floor_rects.size()==1,"Local window requires its authored passage")
	for id: String in ["furnace","cistern"]:
		var room: Dictionary = rooms[id]
		var half: Vector2 = room.half
		floor_rects.append(Rect2(Vector2(room.center.x,room.center.z)-half,half*2.0))
	var vicinity := Rect2(passage_a,passage_b-passage_a).grow(7.0)
	for section: Dictionary in geometry.cutaway.structural_sections:
		if not is_instance_valid(section.get("body")) or not section.has("visual_a"): continue
		var a: Vector3 = section.visual_a
		var b: Vector3 = section.visual_b
		var bounds := Rect2(Vector2(a.x,a.z),Vector2.ZERO).expand(Vector2(b.x,b.z)).grow(0.5)
		if not vicinity.intersects(bounds): continue
		walls.append(section)
		_bind_tree(section.node)
	_bind_tree(geometry.building_crown)
	refresh_materials()

func _bind_tree(root: Node) -> void:
	for child: Node in root.find_children("*","MeshInstance3D",true,false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null: continue
		if mesh.material_override != null:
			mesh.material_override = _material_copy(mesh.material_override)
		else:
			for surface: int in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface)
				if source != null: mesh.set_surface_override_material(surface,_material_copy(source))
		meshes.append(mesh)

func _material_copy(source: Material) -> Material:
	if _copies.has(source): return _copies[source]
	var material: ShaderMaterial
	if source is ShaderMaterial:
		material = source.duplicate() as ShaderMaterial
	elif source is StandardMaterial3D:
		var solid := source as StandardMaterial3D
		material = ShaderMaterial.new()
		material.shader = SOLID
		material.set_shader_parameter("base_color",solid.albedo_color)
		material.set_shader_parameter("use_vertex_color",solid.vertex_color_use_as_albedo)
		material.set_shader_parameter("surface_roughness",solid.roughness)
		material.set_shader_parameter("surface_metallic",solid.metallic)
		material.set_shader_parameter("emitted_color",solid.emission*solid.emission_energy_multiplier if solid.emission_enabled else Color.BLACK)
	else:
		push_error("Unsupported local window material: "+source.get_class())
		return source
	var shader := material.shader
	if not _shaders.has(shader):
		var variant := Shader.new()
		var code := shader.code
		var render_mode_at := code.find("render_mode ")
		var preamble_end := code.find(";",render_mode_at)+1 if render_mode_at>=0 else code.find(";")+1
		code = code.insert(preamble_end,INCLUDE)
		code = _helper._append_to_function(code,"vertex","\nview_window_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;\n")
		var fragment_start := code.find("{",code.find("void fragment()"))+1
		code = code.insert(fragment_start,"\nif (view_window_coverage(view_window_world)>view_window_pattern(view_window_world)) { discard; }\n")
		variant.code = code
		variant.set_meta(&"local_view_window_capable",true)
		_shaders[shader] = variant
	material.shader = _shaders[shader]
	_copies[source] = material
	return material

func refresh_materials() -> void:
	materials.clear()
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and not materials.has(material): materials.append(material)
	_apply_parameters()

func update_view(player: SlimeController, view: Camera3D, delta: float) -> void:
	camera = view
	var point := Vector2(player.global_position.x,player.global_position.z)
	var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,passage_a,passage_b))
	# Use the support height, not a room ID or a fresh jump-height threshold.
	center = Vector3(point.x,0.65,point.y)
	var near := distance <= (EXIT_DISTANCE if target else ENTER_DISTANCE)
	# Arm before the threshold, so a full-speed entry does not spend its first
	# frames behind a wall. The shader itself admits only occluding fragments
	# over real nearby floor; room switches and clear intermediate angles do
	# not toggle this one passage-owned state.
	if delta > 0.0:
		if enabled and near:
			target = true
			_hold = RELEASE_HOLD
		elif _hold>0.0 and enabled:
			_hold = maxf(0.0,_hold-delta)
		else:
			target = false
		amount = move_toward(amount,1.0 if target else 0.0,delta/(OPEN_SECONDS if target else CLOSE_SECONDS))
	_apply_parameters()

func _apply_parameters() -> void:
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("view_window_amount",amount)
		material.set_shader_parameter("view_window_center",center)
		for index: int in floor_rects.size():
			var rect := floor_rects[index]
			material.set_shader_parameter(["view_window_passage","view_window_floor_a","view_window_floor_b"][index],Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y))
		if not is_instance_valid(camera): continue
		material.set_shader_parameter("view_window_right",camera.global_basis.x)
		material.set_shader_parameter("view_window_up",camera.global_basis.y)
		material.set_shader_parameter("view_window_back",camera.global_basis.z)
		material.set_shader_parameter("view_window_camera",camera.global_position)
		material.set_shader_parameter("view_window_pixel",camera.size/camera.get_viewport().get_visible_rect().size.y)

func _on_floor(point: Vector2) -> bool:
	return floor_rects.any(func(rect: Rect2) -> bool: return rect.has_point(point))

func coverage_at(point: Vector3) -> float:
	if amount<=0.0 or point.y<0.06 or not is_instance_valid(camera): return 0.0
	var relative := point-center
	var projected := Vector2(relative.dot(camera.global_basis.x)/2.7,relative.dot(camera.global_basis.y)/2.15)
	var aperture := smoothstep(0.0,1.0,amount)
	var floor_point := point-camera.global_basis.z*((point.y-0.04)/camera.global_basis.z.y)
	if not _on_floor(Vector2(floor_point.x,floor_point.z)): return 0.0
	return 1.0-smoothstep(maxf(0.0,aperture-0.09),aperture,projected.length())

func is_point_cut(body: CollisionObject3D, point: Vector3) -> bool:
	return walls.any(func(section: Dictionary) -> bool: return section.body==body) and coverage_at(point)>0.98

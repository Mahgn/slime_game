extends Node3D
## Authored visibility fixtures. Physics and closed plinths never belong to a fade.
## Each entry owns a complete upper architectural assembly, including its trim.

const WALL_HEIGHT: float = 3.4
const WALL_THICKNESS: float = 0.65
const PLINTH_HEIGHT: float = 0.22
const DECK_HEIGHT: float = 3.2
const SITE_RECT := Rect2(-8.6, -8.6, 17.2, 17.2)

var sections: Array[Dictionary] = []
var floor_regions: Array[Dictionary] = []
var spawn := Vector3.ZERO
var probes: Array[Vector3] = []
var route: Array[Vector3] = []
var upper_spawn := Vector3.ZERO
var upper_route: Array[Vector3] = []
var enemy_spawn := Vector3.ZERO
var title: String = ""
var scenario_index: int = 0
var theme_index: int = 0

var _wall_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _base_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _floor_materials: Array[StandardMaterial3D] = []
var _ground_materials: Array[StandardMaterial3D] = []


func build(index: int, theme: int = 0) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	sections.clear()
	floor_regions.clear()
	probes.clear()
	route.clear()
	upper_route.clear()
	upper_spawn = Vector3.ZERO
	scenario_index = clampi(index, 0, 5)
	theme_index = posmod(theme, 2)
	_make_materials()
	match scenario_index:
		0: _straight_corridor()
		1: _elbow()
		2: _junction()
		3: _column_room()
		4: _doorway()
		5: _bridge()
	_build_ground()
	_add_route_markers()


func _straight_corridor() -> void:
	title = "Тесный коридор"
	_floor_region(Rect2(-2.15, -7.2, 4.3, 14.4))
	_floor_region(Rect2(-4.5, -7.2, 9.0, 2.0))
	_floor_region(Rect2(-4.5, 5.2, 9.0, 2.0))
	_wall("west_wall", Vector2(-1.825, -5.6), Vector2(-1.825, 5.6))
	_wall("east_wall", Vector2(1.825, -5.6), Vector2(1.825, 5.6))
	spawn = Vector3(0, 0, 6.5)
	enemy_spawn = Vector3(0, 0, -4.5)
	probes.assign([Vector3(0, 0, 3.8), Vector3.ZERO, Vector3(0, 0, -3.8)])
	route.assign([spawn, Vector3(0, 0, -6.5)])


func _elbow() -> void:
	title = "Поворот коридора"
	_floor_region(Rect2(-7.2, -2.15, 9.35, 4.3))
	_floor_region(Rect2(-2.15, -7.2, 4.3, 9.35))
	# A corner has two complete meeting wall runs, not an isolated corner shield.
	_wall("outside_south", Vector2(-6.5, 1.825), Vector2(2.15, 1.825))
	_wall("outside_east", Vector2(1.825, -6.5), Vector2(1.825, 1.5))
	_wall("inside_south", Vector2(-6.5, -1.825), Vector2(-1.5, -1.825))
	_wall("inside_east", Vector2(-1.825, -6.5), Vector2(-1.825, -2.15))
	spawn = Vector3(-6.6, 0, 0)
	enemy_spawn = Vector3(0, 0, -4.7)
	probes.assign([Vector3(-3.4, 0, 0), Vector3.ZERO, Vector3(0, 0, -3.4)])
	route.assign([spawn, Vector3.ZERO, Vector3(0, 0, -6.6)])


func _junction() -> void:
	title = "Т-образный перекрёсток"
	_floor_region(Rect2(-7.2, -2.15, 14.4, 4.3))
	_floor_region(Rect2(-2.15, -2.15, 4.3, 9.35))
	_wall("crossbar_north", Vector2(-6.5, -1.825), Vector2(6.5, -1.825))
	_wall("left_return", Vector2(-6.5, 1.825), Vector2(-1.5, 1.825))
	_wall("right_return", Vector2(1.5, 1.825), Vector2(6.5, 1.825))
	_wall("stem_west", Vector2(-1.825, 2.15), Vector2(-1.825, 6.5))
	_wall("stem_east", Vector2(1.825, 2.15), Vector2(1.825, 6.5))
	spawn = Vector3(0, 0, 6.6)
	enemy_spawn = Vector3(-4.5, 0, 0)
	probes.assign([Vector3(0, 0, 3.3), Vector3.ZERO, Vector3(3.3, 0, 0)])
	route.assign([spawn, Vector3.ZERO, Vector3(-6.4, 0, 0), Vector3(6.4, 0, 0)])


func _column_room() -> void:
	title = "Комната с колонной"
	_floor_region(Rect2(-6.15, -6.15, 12.3, 12.3))
	_wall("north", Vector2(-6.15, -5.825), Vector2(6.15, -5.825))
	_wall("west", Vector2(-5.825, -5.5), Vector2(-5.825, 5.5))
	_wall("east", Vector2(5.825, -5.5), Vector2(5.825, 5.5))
	_wall("south_left", Vector2(-6.15, 5.825), Vector2(-1.5, 5.825))
	_wall("south_right", Vector2(1.5, 5.825), Vector2(6.15, 5.825))
	_column("central_column", Vector3.ZERO)
	spawn = Vector3(0, 0, 4.4)
	enemy_spawn = Vector3(0, 0, -3.5)
	probes.assign([Vector3(0, 0, 2.1), Vector3(2.1, 0, 0), Vector3(0, 0, -2.1)])
	route.assign([spawn, Vector3(2.3, 0, 2.3), Vector3(2.3, 0, -2.3), Vector3(-2.3, 0, -2.3), Vector3(-2.3, 0, 2.3), spawn])


func _doorway() -> void:
	title = "Арка между помещениями"
	_floor_region(Rect2(-6.15, -6.8, 12.3, 13.6))
	_wall("west", Vector2(-5.825, -6.175), Vector2(-5.825, 6.175))
	_wall("east", Vector2(5.825, -6.175), Vector2(5.825, 6.175))
	_wall("north_left", Vector2(-6.15, -6.5), Vector2(-1.5, -6.5))
	_wall("north_right", Vector2(1.5, -6.5), Vector2(6.15, -6.5))
	_wall("south_left", Vector2(-6.15, 6.5), Vector2(-1.5, 6.5))
	_wall("south_right", Vector2(1.5, 6.5), Vector2(6.15, 6.5))
	# Both piers, the spanning lintel and the decoration have one owner.
	var portal: Dictionary = _new_section("portal", "wall", 0.0)
	for side: float in [-1.0, 1.0]:
		var center := Vector3(side * 3.5, WALL_HEIGHT * 0.5, 0)
		var size := Vector3(4.0, WALL_HEIGHT, 0.85)
		_collision_box(portal.body, center, size)
		_box(portal.body, center * Vector3(1, 0, 1) + Vector3.UP * PLINTH_HEIGHT * 0.5,
			Vector3(4.0, PLINTH_HEIGHT, 0.85), _base_material, "PortalPlinth")
		_owned_box(portal, Vector3(center.x, (WALL_HEIGHT + PLINTH_HEIGHT) * 0.5, 0),
			Vector3(4.0, WALL_HEIGHT - PLINTH_HEIGHT, 0.85), _wall_material)
		_owned_box(portal, Vector3(side * 1.69, 1.75, 0), Vector3(0.38, 3.06, 1.01), _trim_material)
		_owned_box(portal, Vector3(center.x, 3.39, 0), Vector3(4.0, 0.18, 1.01), _trim_material)
		_owned_box(portal, Vector3(side * 2.15, 2.0, 0.48), Vector3(0.32, 0.6, 0.12), _accent_material)
		_owned_box(portal, Vector3(side * 2.15, 2.0, -0.48), Vector3(0.32, 0.6, 0.12), _accent_material)
	_collision_box(portal.body, Vector3(0, 3.0, 0), Vector3(3.0, 0.8, 0.85))
	_owned_box(portal, Vector3(0, 3.0, 0), Vector3(3.0, 0.8, 0.85), _wall_material)
	_owned_box(portal, Vector3(0, 3.39, 0), Vector3(3.0, 0.18, 1.01), _trim_material)
	_owned_box(portal, Vector3(0, 2.95, 0), Vector3(0.55, 0.9, 1.05), _accent_material)
	_finish_section(portal)
	spawn = Vector3(0, 0, 5.5)
	enemy_spawn = Vector3(0, 0, -4.0)
	probes.assign([Vector3(0, 0, 2.6), Vector3.ZERO, Vector3(0, 0, -2.6)])
	route.assign([spawn, Vector3(0, 0, -5.5)])


func _bridge() -> void:
	title = "Мост и два яруса"
	_floor_region(Rect2(-2.15, -7.5, 4.3, 15.0))
	_floor_region(Rect2(-2.15, 4.8, 10.15, 2.7))
	_floor_region(Rect2(5.0, -1.5, 3.0, 8.0))
	_floor_region(Rect2(-5.5, -1.5, 10.5, 3.0), DECK_HEIGHT)
	_floor_region(Rect2(5.0, -1.5, 3.0, 1.0), DECK_HEIGHT)
	_wall("lower_west_north", Vector2(-1.825, -6.8), Vector2(-1.825, -2.1))
	_wall("lower_east_north", Vector2(1.825, -6.8), Vector2(1.825, -2.1))
	_wall("lower_west_south", Vector2(-1.825, 2.1), Vector2(-1.825, 4.8))
	_wall("lower_east_south", Vector2(1.825, 2.1), Vector2(1.825, 4.8))
	var deck: Dictionary = _new_section("upper_bridge", "overhead", DECK_HEIGHT)
	var center := Vector3(-0.25, DECK_HEIGHT - 0.18, 0)
	var size := Vector3(10.5, 0.36, 3.0)
	_collision_box(deck.body, center, size)
	_owned_box(deck, center, size, _wall_material)
	# The narrow east landing meets the ramp at z=-0.5 without a vertical lip.
	_collision_box(deck.body, Vector3(6.5, 3.02, -1.0), Vector3(3.0, 0.36, 1.0))
	_owned_box(deck, Vector3(6.5, 3.02, -1.0), Vector3(3.0, 0.36, 1.0), _wall_material)
	# Structural edge beams and all rails disappear with the upper walkway.
	for z: float in [-1.39, 1.39]:
		_owned_box(deck, Vector3(-0.25, 2.97, z), Vector3(10.5, 0.42, 0.23), _trim_material)
	_owned_box(deck, Vector3(6.5, 2.97, -1.39), Vector3(3.0, 0.42, 0.23), _trim_material)
	_bridge_rail(deck, -5.5, 8.0, -1.52)
	_bridge_rail(deck, -5.5, 4.8, 1.52)
	_owned_box(deck, Vector3(-5.44, 3.72, 0), Vector3(0.16, 1.04, 3.0), _trim_material)
	_collision_box(deck.body, Vector3(-5.44, 3.72, 0), Vector3(0.16, 1.04, 3.0))
	_owned_box(deck, Vector3(7.94, 3.72, -1.0), Vector3(0.16, 1.04, 1.0), _trim_material)
	_collision_box(deck.body, Vector3(7.94, 3.72, -1.0), Vector3(0.16, 1.04, 1.0))
	for i: int in range(10):
		_owned_box(deck, Vector3(-5.0 + float(i), 3.205, 0), Vector3(0.94, 0.01, 2.76), _floor_materials[i % _floor_materials.size()])
	for i: int in range(3):
		_owned_box(deck, Vector3(5.5 + float(i), 3.205, -1.0), Vector3(0.94, 0.01, 0.76), _floor_materials[i % _floor_materials.size()])
	_finish_section(deck)
	# Supports have separate, permanent ownership; the cleared route remains legible.
	var supports := _body("BridgeSupports")
	for x: float in [-4.4, 4.4]:
		for z: float in [-1.12, 1.12]:
			_collision_box(supports, Vector3(x, 1.42, z), Vector3(0.48, 2.84, 0.48))
			_box(supports, Vector3(x, 1.42, z), Vector3(0.48, 2.84, 0.48), _trim_material, "Support")
			_box(supports, Vector3(x, 0.12, z), Vector3(0.72, 0.24, 0.72), _base_material, "SupportFoot")
	_build_ramp()
	spawn = Vector3(0, 0, 6.4)
	enemy_spawn = Vector3(0, 0, -5.5)
	upper_spawn = Vector3(6.5, DECK_HEIGHT + 0.02, -0.7)
	probes.assign([Vector3(0, 0, 2.8), Vector3.ZERO, Vector3(0, 0, -2.8)])
	route.assign([spawn, Vector3(0, 0, -6.4)])
	upper_route.assign([Vector3(0, 0, 6.8), Vector3(6.5, 0, 6.8), upper_spawn, Vector3(-4.4, DECK_HEIGHT + 0.02, -0.7)])


func _wall(id: String, a: Vector2, b: Vector2) -> void:
	var along_x: bool = absf(b.x - a.x) > absf(b.y - a.y)
	var length: float = a.distance_to(b)
	var center := Vector3((a.x + b.x) * 0.5, WALL_HEIGHT * 0.5, (a.y + b.y) * 0.5)
	var size := Vector3(length, WALL_HEIGHT, WALL_THICKNESS) if along_x else Vector3(WALL_THICKNESS, WALL_HEIGHT, length)
	var section: Dictionary = _new_section(id, "wall", 0.0)
	_collision_box(section.body, center, size)
	var base_size := Vector3(size.x, PLINTH_HEIGHT, size.z)
	_box(section.body, Vector3(center.x, PLINTH_HEIGHT * 0.5, center.z), base_size, _base_material, "ClosedPlinth")
	var upper_size := Vector3(size.x, WALL_HEIGHT - PLINTH_HEIGHT, size.z)
	_owned_box(section, Vector3(center.x, (WALL_HEIGHT + PLINTH_HEIGHT) * 0.5, center.z), upper_size, _wall_material)
	var cap_size := Vector3(size.x, 0.16, size.z)
	cap_size += Vector3(0, 0, 0.12) if along_x else Vector3(0.12, 0, 0)
	_owned_box(section, Vector3(center.x, 3.4, center.z), cap_size, _trim_material)
	if theme_index == 0:
		for y: float in [1.05, 2.12]:
			var band_size := Vector3(size.x, 0.07, size.z + 0.035) if along_x else Vector3(size.x + 0.035, 0.07, size.z)
			_owned_box(section, Vector3(center.x, y, center.z), band_size, _trim_material)
	else:
		var count: int = maxi(1, ceili(length / 2.3))
		for i: int in range(count + 1):
			var point: Vector2 = a.lerp(b, (float(i) + 0.12) / (float(count) + 0.24))
			var rib_size := Vector3(0.17, 3.18, 0.76) if along_x else Vector3(0.76, 3.18, 0.17)
			_owned_box(section, Vector3(point.x, 1.81, point.y), rib_size, _trim_material)
		for y: float in [0.65, 2.7]:
			var band_size := Vector3(size.x, 0.13, 0.73) if along_x else Vector3(0.73, 0.13, size.z)
			_owned_box(section, Vector3(center.x, y, center.z), band_size, _accent_material)
	# A pair of surface-mounted lights proves that dressing has the same owner.
	if length > 3.0:
		for side: float in [-1.0, 1.0]:
			var mount_offset := Vector3(0, 0, side * 0.39) if along_x else Vector3(side * 0.39, 0, 0)
			var mount_size := Vector3(0.38, 0.58, 0.12) if along_x else Vector3(0.12, 0.58, 0.38)
			_owned_box(section, Vector3(center.x, 1.9, center.z) + mount_offset, mount_size, _accent_material)
			_owned_box(section, Vector3(center.x, 1.94, center.z) + mount_offset * 1.2, Vector3(0.17, 0.3, 0.17), _lamp_material)
	_finish_section(section)


func _column(id: String, center: Vector3) -> void:
	var section: Dictionary = _new_section(id, "wall", center.y)
	_collision_box(section.body, center + Vector3(0, 1.7, 0), Vector3(1.6, 3.4, 1.6))
	_box(section.body, center + Vector3(0, 0.11, 0), Vector3(1.72, 0.22, 1.72), _base_material, "ColumnFoot")
	_owned_box(section, center + Vector3(0, 1.81, 0), Vector3(1.6, 3.18, 1.6), _wall_material)
	_owned_box(section, center + Vector3(0, 3.32, 0), Vector3(1.85, 0.32, 1.85), _trim_material)
	for x: float in [-0.8, 0.8]:
		for z: float in [-0.8, 0.8]:
			_owned_box(section, center + Vector3(x, 1.81, z), Vector3(0.12, 3.18, 0.12), _accent_material)
	_finish_section(section)


func _bridge_rail(section: Dictionary, x_min: float, x_max: float, z: float) -> void:
	var length: float = x_max - x_min
	var center := Vector3((x_min + x_max) * 0.5, 3.72, z)
	_collision_box(section.body, center, Vector3(length, 1.04, 0.18))
	_owned_box(section, center + Vector3(0, 0.46, 0), Vector3(length, 0.12, 0.22), _trim_material)
	_owned_box(section, center - Vector3(0, 0.32, 0), Vector3(length, 0.1, 0.17), _accent_material)
	var count: int = ceili(length / 1.1)
	for i: int in range(count + 1):
		var x: float = lerpf(x_min + 0.08, x_max - 0.08, float(i) / float(count))
		_owned_box(section, Vector3(x, 3.72, z), Vector3(0.12, 1.04, 0.18), _trim_material)


func _build_ramp() -> void:
	# A closed convex wedge: slope 3.2 / 7.0, below the controller's floor limit.
	var body := _body("Ramp")
	var points := PackedVector3Array([
		Vector3(5, -0.25, -0.5), Vector3(8, -0.25, -0.5),
		Vector3(5, -0.25, 6.5), Vector3(8, -0.25, 6.5),
		Vector3(5, 3.2, -0.5), Vector3(8, 3.2, -0.5),
		Vector3(5, 0, 6.5), Vector3(8, 0, 6.5)])
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	var faces: Array[Array] = [[4, 6, 7, 5], [0, 1, 3, 2], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face: Array in faces:
		var p0: Vector3 = points[int(face[0])]
		var p1: Vector3 = points[int(face[1])]
		var p2: Vector3 = points[int(face[2])]
		var normal: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
		# Godot front faces use clockwise winding; normals point out of the wedge.
		for corner: int in [0, 2, 1, 0, 3, 2]:
			vertices.append(points[int(face[corner])])
			normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = "ClosedRamp"
	visual.mesh = mesh
	visual.material_override = _floor_materials[1]
	body.add_child(visual)
	# The entry and exit remain open; side guardrails stay with the ramp.
	for x: float in [5.06, 7.94]:
		var rail_z: float = 3.275
		var rail_floor_y: float = (6.5 - rail_z) * 3.2 / 7.0
		var rail_length: float = Vector2(6.25, 6.25 * 3.2 / 7.0).length()
		var rail := _box(body, Vector3(x, rail_floor_y + 0.9, rail_z), Vector3(0.12, 0.14, rail_length), _trim_material, "RampRail")
		rail.rotation.x = atan(3.2 / 7.0)
		for i: int in range(6):
			var z: float = 0.15 + float(i) * 1.25
			var y: float = (6.5 - z) * 3.2 / 7.0
			_box(body, Vector3(x, y + 0.45, z), Vector3(0.1, 0.9, 0.1), _trim_material, "RampPost")
		var rail_collision := CollisionShape3D.new()
		var rail_shape := BoxShape3D.new()
		rail_shape.size = Vector3(0.12, 0.9, rail_length)
		rail_collision.shape = rail_shape
		rail_collision.position = Vector3(x, rail_floor_y + 0.45, rail_z)
		rail_collision.rotation.x = atan(3.2 / 7.0)
		body.add_child(rail_collision)


func floor_height_at(point: Vector3) -> float:
	if scenario_index != 5:
		return 0.0
	if point.x >= 5.0 and point.x <= 8.0 and point.z >= -0.5 and point.z <= 6.5:
		return (6.5 - point.z) * DECK_HEIGHT / 7.0
	if point.y > 2.0 and point.x >= -5.5 and point.x <= 8.0 and absf(point.z) <= 1.5:
		return DECK_HEIGHT
	return 0.0


func _floor_region(rect: Rect2, y: float = 0.0) -> void:
	floor_regions.append({"rect": rect, "y": y})


func _build_ground() -> void:
	var body := _body("Ground")
	_collision_box(body, Vector3(0, -0.2, 0), Vector3(SITE_RECT.size.x, 0.4, SITE_RECT.size.y))
	_box(body, Vector3(0, -0.23, 0), Vector3(SITE_RECT.size.x, 0.4, SITE_RECT.size.y), _base_material, "SolidFoundation")
	var grid: int = 16
	var spacing: float = SITE_RECT.size.x / float(grid)
	for row: int in range(grid):
		for column: int in range(grid):
			var point := Vector2(SITE_RECT.position.x + (float(column) + 0.5) * spacing, SITE_RECT.position.y + (float(row) + 0.5) * spacing)
			var on_route: bool = false
			for region: Dictionary in floor_regions:
				var rect: Rect2 = region.rect
				if is_zero_approx(float(region.y)) and rect.has_point(point):
					on_route = true
					break
			var palette: Array[StandardMaterial3D] = _floor_materials if on_route else _ground_materials
			var material: StandardMaterial3D = palette[(column * 3 + row * 7) % palette.size()]
			_box(body, Vector3(point.x, -0.025, point.y), Vector3(spacing - 0.018, 0.05, spacing - 0.018), material, "FloorTile")


func _add_route_markers() -> void:
	var node := Node3D.new()
	node.name = "RouteMarkers"
	add_child(node)
	var marker_material := _material(Color("65bca8"))
	for point: Vector3 in [spawn, enemy_spawn]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.53
		mesh.bottom_radius = 0.53
		mesh.height = 0.008
		mesh.radial_segments = 32
		var marker := MeshInstance3D.new()
		marker.mesh = mesh
		marker.material_override = marker_material
		marker.position = point + Vector3(0, 0.006, 0)
		node.add_child(marker)


func _new_section(id: String, role: String, floor_y: float) -> Dictionary:
	var body: StaticBody3D = _body(id)
	body.set_meta(&"visibility_section", id)
	var meshes: Array[MeshInstance3D] = []
	return {"id": id, "body": body, "meshes": meshes, "bounds": AABB(), "floor_y": floor_y, "top_y": floor_y, "role": role}


func _finish_section(section: Dictionary) -> void:
	var meshes: Array = section.meshes
	var bounds := AABB()
	var first: bool = true
	for mesh: MeshInstance3D in meshes:
		var mesh_bounds: AABB = mesh.transform * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	section.bounds = bounds
	section.top_y = bounds.end.y
	sections.append(section)


func _owned_box(section: Dictionary, center: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh: MeshInstance3D = _box(section.body, center, size, material, "OwnedVisual")
	mesh.set_meta(&"visibility_section", section.id)
	section.meshes.append(mesh)
	return mesh


func _body(node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 129
	body.collision_mask = 0
	add_child(body)
	return body


func _box(parent: Node3D, center: Vector3, size: Vector3, material: StandardMaterial3D, node_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance


func _collision_box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


func _make_materials() -> void:
	_floor_materials.clear()
	_ground_materials.clear()
	if theme_index == 0:
		_wall_material = _material(Color("718587"))
		_trim_material = _material(Color("41565d"))
		_base_material = _material(Color("42555a"))
		_accent_material = _material(Color("b39666"))
		for color: String in ["b9b5a1", "aeab9b", "c1bba7", "b3b09e"]:
			_floor_materials.append(_material(Color(color)))
		for color: String in ["798989", "7c8b8b", "748586", "81908e"]:
			_ground_materials.append(_material(Color(color)))
	else:
		_wall_material = _material(Color("a87950"))
		_trim_material = _material(Color("513f34"))
		_base_material = _material(Color("555e61"))
		_accent_material = _material(Color("71878a"))
		for color: String in ["c4ac85", "bda17c", "cbb18b", "b79a74"]:
			_floor_materials.append(_material(Color(color)))
		for color: String in ["7a7d75", "747a74", "818278", "7c8078"]:
			_ground_materials.append(_material(Color(color)))
	_lamp_material = _material(Color("f2c87c"))
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color("e9bb68")
	_lamp_material.emission_energy_multiplier = 0.35


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.91
	return material

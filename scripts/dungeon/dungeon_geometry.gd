extends "res://scripts/keepers/keepers_facility_geometry.gd"

const WALL_FADE_RENDERER := preload("res://scripts/isometric/room_wall_fade_renderer.gd")
const WALL_ARCHITECTURE := preload("res://scripts/dungeon/dungeon_wall_architecture.gd")
const HYBRID_PAIR := preload("res://scripts/dungeon/dungeon_hybrid_pair.gd")
const LOCAL_VIEW_WINDOW := preload("res://scripts/isometric/local_view_window.gd")
var wall_fade_renderer: RefCounted

func build_world(rooms: Dictionary, connections: Array) -> void:
	super.build_world(rooms, connections)
	var portal: Node3D = get_node_or_null("FurnaceServicePortal") as Node3D
	if portal != null:
		var kept: Array[Dictionary] = []
		for section: Dictionary in cutaway.structural_sections:
			if section.get("node") != portal:
				kept.append(section)
		cutaway.structural_sections = kept
		portal.free()
	# The orbit trial keeps the original complete shell and continuous crown.
	# Keep the previous hybrid available without rebuilding it in this mode.
	if bool(get_parent().get_meta(&"camera_quarter_turns", false)):
		cutaway.configure_building(rooms, connections)
		_configure_view_window(rooms, connections)
		return
	# Reconfigure after removing the legacy portal; the older facility keeps
	# its full shell while this explicitly selected dungeon experiment fades.
	HYBRID_PAIR.new().build(self, rooms)
	cutaway.configure_building(rooms, connections)
	WALL_ARCHITECTURE.new().build(self)
	wall_fade_renderer = WALL_FADE_RENDERER.new()
	wall_fade_renderer.configure(self, rooms, connections)
	cutaway.set_enabled(true)


func _configure_view_window(rooms: Dictionary, connections: Array) -> void:
	cutaway.local_window = LOCAL_VIEW_WINDOW.new()
	cutaway.local_window.configure(self, rooms, connections)


func _facility_dressing() -> void:
	if _world_id == "entry":
		_sconce(Vector3(-7.35,1.8,-4.8))
		_noticeboard(Vector3(-3.6,0,-5.25))
		_art_kit.dispatch_station(Vector3(-3.6,0,-4.75))
		_crate(Vector3(6.3,0.55,3.8),Vector3(1.7,1.1,1.35))
		_cart(Vector3(-5,0,3.5))
		_eggs(Vector3(-4.5,0.05,-3.0))
		return
	if _world_id == "furnace":
		for x: float in [-6.8, -3.0]:
			for z: float in [-4.5, 2.5]:
				_planter(Vector3(x, 0, z), 4.0)
				_mushrooms(Vector3(x, 0.65, z), Color("899c61"))
		_art_kit.conduit([Vector3(-8.8,0.7,-6.4),Vector3(-8.8,0.7,6.4)], 0.15, Color("698579"))
		return
	if _world_id == "armory":
		_sconce(Vector3(-8.35,1.8,-5.8))
		for x: float in [-6.2,6.2]:
			_art_kit.workbench(Vector3(x,0,-3.6),3.5,"workshop" if x<0 else "fitting")
		_art_kit.gear_rack(Vector3(6.3,0,1.0))
		_art_kit.rest_bench(Vector3(-5.5,0,4.8))
		_banner(Vector3(-6.2,2.7,-6.55),0)
		_noticeboard(Vector3(-3.1,0,-6.45))
		return
	if _world_id in ["spring", "barracks"]:
		_planter(Vector3(-1.5 if _world_id == "barracks" else 1.6, 0, -2.4), 2.4)
		_mushrooms(Vector3(-1.5 if _world_id == "barracks" else 1.6, 0.6, -2.4), Color("b4a46d"))
		_eggs(Vector3(-2.3, 0.05, 2.0))
		return
	super._facility_dressing()
	if _world_id == "junction":
		for x: float in [-5.7, 5.7]:
			_eggs(Vector3(x,0.05,2.5))


func _workplace_details() -> void:
	if _world_id in ["junction", "barracks", "furnace", "spring"]:
		return
	super._workplace_details()


func _noticeboard(at: Vector3) -> void:
	if _world_id == "entry":
		at.x = -3.6
	super._noticeboard(at)


func _work_lantern(at: Vector3) -> void:
	if _world_id == "entry":
		at.x = -3.6
	elif _world_id == "garden":
		at.x = -6.35
	elif _world_id == "hub":
		at.x = -4.0
	super._work_lantern(at)


func _banner(at: Vector3, yaw: float) -> void:
	if _world_id == "armory":
		at.x = -6.2
	super._banner(at,yaw)


func _build_surroundings(rooms: Dictionary, connections: Array) -> void:
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for room: Dictionary in rooms.values():
		var rectangle: Rect2 = Rect2(Vector2(room.center.x,room.center.z)-room.half,room.half*2.0)
		bounds = rectangle if first else bounds.merge(rectangle)
		first = false
	bounds = bounds.grow(6.0)
	_box("BedrockFoundation",Vector3(bounds.get_center().x,-1.3,bounds.get_center().y),Vector3(bounds.size.x,1.1,bounds.size.y),Color("222c2d"),_stone,false,0)
	building_crown = CROWN.new()
	building_crown.name = "UnifiedBuildingMass"
	var empty_slots: Array[Rect2] = []
	building_crown.set("service_slots",empty_slots)
	building_crown.set("outer_bounds",bounds)
	add_child(building_crown)
	building_crown.build(rooms,connections,WALL_WIDTH,WALL_HEIGHT)


func _mushrooms(at: Vector3, color: Color) -> void:
	var stem: StandardMaterial3D = _simple_material(Color("acb49e"))
	var cap: StandardMaterial3D = _simple_material(color)
	for index: int in 5:
		var spot: Vector3 = at + Vector3(0.22 * float((index % 2) * 2 - 1), 0, -1.35 + float(index) * 0.65)
		var height: float = 0.42 + float(index % 3) * 0.11
		var stalk: CylinderMesh = CylinderMesh.new()
		stalk.top_radius = 0.055
		stalk.bottom_radius = 0.07
		stalk.height = height
		stalk.radial_segments = 10
		_part(stalk, stem, spot + Vector3.UP * height * 0.5)
		var dome: SphereMesh = SphereMesh.new()
		dome.radius = 0.3
		dome.height = 0.22
		dome.radial_segments = 12
		dome.rings = 6
		_part(dome, cap, spot + Vector3.UP * height)


func _eggs(at: Vector3) -> void:
	var material: StandardMaterial3D = _simple_material(Color("c7c990"))
	for index: int in 4:
		var egg: SphereMesh = SphereMesh.new()
		egg.radius = 0.22
		egg.height = 0.67
		egg.radial_segments = 12
		egg.rings = 6
		_part(egg, material, at + Vector3(float(index % 2) * 0.55, 0.33, float(index / 2) * 0.6))


func _part(mesh: Mesh, material: Material, at: Vector3) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	add_child(part)


func _simple_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

extends RefCounted

# A deliberately local architecture study, not a new rule for every room.
const KIT := preload("res://scripts/keepers/keepers_facility_details.gd")
const CLOSED_STONE := preload("res://scripts/dungeon/dungeon_wall_architecture.gd")
const CUT_STONE := preload("res://shaders/keepers/hybrid_cut_stone.gdshader")
const PAIR: Array[String] = ["entry", "spring"]
const CUT_TOP := 0.36
var stone = CLOSED_STONE.new()

func build(geometry: Node3D, rooms: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "HybridRoomArchitecture"
	geometry.add_child(root)
	var divider: Array[Dictionary] = []
	var north: Dictionary = {}
	for section: Dictionary in geometry.cutaway.structural_sections:
		var owners: Array = section.get("room_ids", [])
		if owners.is_empty(): owners = [String(section.get("room_id", ""))]
		var selected := owners.all(func(id: String) -> bool: return PAIR.has(id))
		if not selected: continue
		section["hybrid_pair"] = true
		section["cap_color"] = Color("3e4b40")
		section.cut_height = CUT_TOP
		var point: Vector3 = section.point
		var normal: Vector3 = section.normal
		var shared := owners.size() == 2
		var dividing_wall := (owners.has("entry") and absf(point.x + 8.0) < 0.01) or (owners.has("spring") and absf(point.x + 9.0) < 0.01)
		if shared or dividing_wall:
			section["authored_reveal_room_ids"] = PAIR.duplicate()
			section["hybrid_role"] = "portal"
			divider.append(section)
		elif normal.x + normal.z > 0.1:
			section["minimum_reveal"] = 1.0
			section["hybrid_role"] = "fixed_front_cut"
		else:
			section["hybrid_role"] = "rear_wall"
			if owners.has("entry") and absf(point.z - 8.0) < 0.01 and point.x < 0:
				north = section
		# The continuous, recessed stone base remains visible when upper walls fade.
	_build_boundary(root, geometry.building_crown.playable_openings, rooms)
	if not north.is_empty():
		_connect_rear_corner(geometry, north, divider)
	_build_portal(root, divider)

func _connect_rear_corner(geometry: Node3D, north: Dictionary, divider: Array[Dictionary]) -> void:
	# Shorten just the visual upper of the north divider. The original full
	# collider stays; the permanent return and its own aim body occupy the trim.
	for section: Dictionary in divider:
		var point: Vector3 = section.point
		if absf(point.x + 8.0) > 0.01 or point.z > 14.0: continue
		var a: Vector3 = section.visual_a
		var b: Vector3 = section.visual_b
		a.z = maxf(a.z, 10.45)
		b.z = maxf(b.z, 10.45)
		section.visual_a = a
		section.visual_b = b
		var node: Node3D = section.node
		for child: Node in node.get_children():
			if child is MeshInstance3D: child.free()
		node.get("_batches").clear()
		var local_a := node.to_local(a)
		var local_b := node.to_local(b)
		geometry.room_nodes.entry._wall_courses(node, Vector2(local_a.x,local_a.z), Vector2(local_b.x,local_b.z), 0.0, 3.22, 7, -atan2(b.z-a.z,b.x-a.x))
		node.finish()
	var spine = KIT.new()
	spine.name = "ConnectedRearReturn"
	geometry.add_child(spine)
	spine.prepare()
	var bodies: Array[CollisionObject3D] = []
	for run: Array in [[Vector2(-8,8.45), Vector2(-8,9.55)], [Vector2(-8.55,10),Vector2(-7.55,10)]]:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		geometry.room_nodes.entry._wall_courses(spine, a, b, 0.0, 3.22, 7, -atan2(b.y-a.y,b.x-a.x))
		stone._box(spine,"RearReturnCap",Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),0.9,3.22,3.4,Color("3e4b40"))
		var body := StaticBody3D.new()
		body.name = "RearReturnAimWall"
		body.collision_layer = 1
		body.collision_mask = 2
		geometry.add_child(body)
		body.position = Vector3((a.x+b.x)*0.5,1.7,(a.y+b.y)*0.5)
		body.rotation.y = -atan2(b.y-a.y,b.x-a.x)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(a.distance_to(b),3.4,0.9)
		shape.shape = box
		body.add_child(shape)
		bodies.append(body)
	spine.finish()
	spine.reparent(north.node, true)
	north["additional_bodies"] = bodies

func _build_portal(root: Node3D, divider: Array[Dictionary]) -> void:
	if divider.is_empty(): return
	var kit = KIT.new()
	kit.name = "SharedDoorSurround"
	root.add_child(kit)
	kit.prepare()
	# Both jambs and the lintel belong to the same disappearing assembly.
	# Its low feet and dressed threshold describe the opening after the reveal.
	for z: float in [12.45, 15.55]:
		for y: float in [0.68,1.22,1.76,2.30]:
			kit._block("DoorQuoin",Vector3(-8.5,y,z),Vector3(1.82,0.52,0.55),Color("818477"),kit.masonry,0.035)
	kit._block("DoorLintel",Vector3(-8.5,2.84,14),Vector3(1.82,0.56,3.66),Color("70776a"),kit.masonry,0.045)
	kit._block("DoorCrown",Vector3(-8.5,3.19,14),Vector3(1.88,0.14,3.72),Color("4b574d"),kit.masonry,0.025)
	kit.finish()
	kit.reparent(divider[0].node,true)
	var threshold = KIT.new()
	threshold.name = "DressedPortalThreshold"
	root.add_child(threshold)
	threshold.prepare()
	for x: float in [-9.125,-8.5,-7.875]:
		threshold._block("ThresholdSlab",Vector3(x,0.012,14),Vector3(0.62,0.04,2.48),Color("777b70"),threshold.masonry,0.008)
	threshold.finish()

func _build_boundary(root: Node3D, openings: Array[Rect2], rooms: Dictionary) -> void:
	# One union, not independent intersecting rims. The shared strip closes the
	# 10 cm gap between room shells along the whole transition, not just the door.
	var footprints: Array[Rect2] = []
	for id: String in PAIR:
		var room: Dictionary = rooms[id]
		footprints.append(Rect2(Vector2(room.center.x,room.center.z)-room.half,room.half*2.0).grow(0.40))
	footprints.append(Rect2(-9.4,9.6,1.8,8.8))
	var xs: Array[float] = []
	var zs: Array[float] = []
	var holes: Array[Rect2] = []
	for opening: Rect2 in openings: holes.append(opening.grow(0.05))
	for region: Rect2 in footprints + holes:
		for x: float in [region.position.x,region.end.x]:
			var rounded := snappedf(x,0.001)
			if not xs.has(rounded): xs.append(rounded)
		for z: float in [region.position.y,region.end.y]:
			var rounded := snappedf(z,0.001)
			if not zs.has(rounded): zs.append(rounded)
	xs.sort()
	zs.sort()
	var cells: Dictionary = {}
	for ix: int in range(xs.size()-1):
		for iz: int in range(zs.size()-1):
			var center := Vector2((xs[ix]+xs[ix+1])*0.5,(zs[iz]+zs[iz+1])*0.5)
			if footprints.any(func(r: Rect2) -> bool: return r.has_point(center)) and not holes.any(func(r: Rect2) -> bool: return r.has_point(center)):
				cells[Vector2i(ix,iz)] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in cells:
		var a := Vector3(xs[cell.x],CUT_TOP,zs[cell.y])
		var b := Vector3(xs[cell.x+1],CUT_TOP,zs[cell.y])
		var c := Vector3(xs[cell.x+1],CUT_TOP,zs[cell.y+1])
		var d := Vector3(xs[cell.x],CUT_TOP,zs[cell.y+1])
		# This dressed course sits ON the existing continuous foundation.
		# Extending it below 0.18 would duplicate the foundation's inner faces
		# and produce depth fighting along the doorway and floor edge.
		var down := Vector3.DOWN * (CUT_TOP-CLOSED_STONE.FOUNDATION_TOP)
		stone._quad(tool,a,b,c,d,Vector3.UP)
		stone._quad(tool,a+down,b+down,c+down,d+down,Vector3.DOWN)
		for edge: Array in [[a,b,Vector3.FORWARD,Vector2i(0,-1)],[b,c,Vector3.RIGHT,Vector2i(1,0)],[c,d,Vector3.BACK,Vector2i(0,1)],[d,a,Vector3.LEFT,Vector2i(-1,0)]]:
			if not cells.has(cell+edge[3]): stone._quad(tool,edge[0],edge[0]+down,edge[1]+down,edge[1],edge[2])
	tool.index()
	var mesh := MeshInstance3D.new()
	mesh.name = "ContinuousDressedCut"
	mesh.mesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = CUT_STONE
	mesh.material_override = material
	root.add_child(mesh)

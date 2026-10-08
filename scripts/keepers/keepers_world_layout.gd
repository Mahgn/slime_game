extends RefCounted
class_name SlimeKeepersWorldLayout

const ENCOUNTERS = preload("res://scripts/keepers/keepers_run_layout.gd")
const PASSAGE_WIDTH := 3.4


static func rooms() -> Dictionary:
	var result: Dictionary = ENCOUNTERS.rooms().duplicate(true)
	var specs := _specs()
	for id: String in result:
		var room: Dictionary = result[id]
		var spec: Dictionary = specs[id]
		room.center = spec.center
		room.footprint = spec.footprint
		room.spawn = spec.center + spec.spawn
		room.enemy_spawns = _global_points(spec.enemies, spec.center)
		room.walk_points = _global_points(spec.walk, spec.center)
		room.ports = {}
		room.links = []
		room.port_paths = {}
		room.reward_position = spec.center + Vector3(1.4, 0, -1.0) if id == "spring" else spec.center + Vector3(-1.5, 0, -1.8)
		if id == "summit":
			room.exit_point = spec.center + Vector3(0, 1.0, -6.4)
	for connection: Dictionary in connections():
		var path: Array = connection.path
		for side in 2:
			var id: String = connection.a if side == 0 else connection.b
			var neighbor: String = connection.b if side == 0 else connection.a
			var at: Vector3 = path[0] if side == 0 else path[-1]
			var beyond: Vector3 = path[1] if side == 0 else path[-2]
			result[id].ports[neighbor] = {"position": at, "normal": (beyond-at).normalized(), "width": PASSAGE_WIDTH}
			result[id].links.append(neighbor)
			result[id].port_paths[neighbor] = _global_points(_port_path(id, at-specs[id].center, specs[id].spawn), specs[id].center)
	return result


static func connections() -> Array:
	var specs := _specs()
	var roads := [
		["entry", "junction", Vector3(0,0,-7), Vector3(0,0,8), []],
		["junction", "furnace", Vector3(-5,0,-7), Vector3(-3,0,7), [Vector3(-5,0,-18),Vector3(-24,0,-18)]],
		["junction", "cistern", Vector3(5,0,-7), Vector3(0,0,8), [Vector3(5,0,-18),Vector3(21,0,-18)]],
		["furnace", "cinder_gallery", Vector3(0,0,-7), Vector3(0,0,8), []],
		["cistern", "pump_room", Vector3(0,0,-8), Vector3(0,0,7), []],
		["cinder_gallery", "hub", Vector3(0,0,-8), Vector3(-4.5,0,8), [Vector3(-21,0,-63),Vector3(-4.5,0,-63)]],
		["pump_room", "hub", Vector3(0,0,-7), Vector3(4.5,0,8), [Vector3(21,0,-63),Vector3(4.5,0,-63)]],
		["hub", "armory", Vector3(-4.5,0,-8), Vector3(3,0,7), [Vector3(-4.5,0,-84.5),Vector3(-18,0,-84.5)]],
		["hub", "garden", Vector3(4.5,0,-8), Vector3(0,0,8), [Vector3(4.5,0,-84),Vector3(21,0,-84)]],
		["armory", "barracks", Vector3(0,0,-7), Vector3(0,0,7), []],
		["garden", "root_cellar", Vector3(0,0,-8), Vector3(0,0,8), []],
		["barracks", "gauntlet", Vector3(0,0,-7), Vector3(-9,0,0), [Vector3(-21,0,-139)]],
		["root_cellar", "gauntlet", Vector3(0,0,-8), Vector3(9,0,0), [Vector3(21,0,-139)]],
		["gauntlet", "summit", Vector3(0,0,-8), Vector3(0,0,8), []],
		["junction", "spring", Vector3(9,0,-1), Vector3(-3.5,0,0), [Vector3(11.5,0,-9),Vector3(11.5,0,10)]],
		["hub", "archive", Vector3(-9,0,0), Vector3(4,0,0), []],
	]
	var result: Array = []
	for road: Array in roads:
		var path: Array[Vector3] = [specs[road[0]].center + road[2]]
		for point: Vector3 in road[4]:
			path.append(point)
		path.append(specs[road[1]].center + road[3])
		result.append({"a": road[0], "b": road[1], "path": path, "width": PASSAGE_WIDTH})
	return result


static func room_at(global_position: Vector3) -> String:
	var specs := _specs()
	for id: String in specs:
		var spec: Dictionary = specs[id]
		var local: Vector3 = global_position - spec.center
		if Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), spec.footprint):
			return id
	return ""


static func _global_points(points: Array, center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		result.append(center + point)
	return result


static func _port_path(id: String, port: Vector3, spawn: Vector3) -> Array:
	var path: Array = [spawn]
	if id in ["spring", "archive"]:
		path.append(Vector3(spawn.x,0,port.z))
		path.append(port)
		return path
	if port.z >= 6.5:
		if absf(port.x-spawn.x) > 0.1:
			path.append(Vector3(port.x,0,spawn.z))
		path.append(port)
		return path
	match id:
		"junction":
			path.append(Vector3(0,0,-0.2))
			path.append(Vector3(port.x,0,-0.2))
		"furnace":
			path.append(Vector3(-3,0,0))
			path.append(Vector3(-3,0,-4.8))
			path.append(Vector3(0,0,-4.8))
		"cistern":
			path.append(Vector3(-4.5,0,5.2))
			path.append(Vector3(-4.5,0,0))
			path.append(Vector3(-4.5,0,-5.2))
			path.append(Vector3(0,0,-6.0))
		"pump_room":
			path.append(Vector3(2.3,0,3.5))
			path.append(Vector3(2.3,0,-3.5))
			path.append(Vector3(0,0,-5.3))
		"hub":
			var lane := -4.5 if port.x < 0 else 4.5
			path.append(Vector3(lane,0,3.8))
			path.append(Vector3(lane,0,0 if absf(port.x)>8.0 else -4.7))
		"armory":
			path.append(Vector3(3.5,0,1.0))
			path.append(Vector3(3.5,0,-4.8))
			path.append(Vector3(0,0,-4.8))
		"gauntlet":
			var lane := 4.4 if port.x > 0 else -4.4
			path.append(Vector3(lane,0,3.8))
			path.append(Vector3(lane,0,0 if absf(port.x)>8.0 else -4.1))
			if absf(port.x)<1.0:
				path.append(Vector3(0,0,-5.8))
		_:
			path.append(Vector3(0,0,2.0))
			path.append(Vector3(0,0,-3.0))
	path.append(port)
	return path


static func _rect(x: float, z: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-x,-z),Vector2(x,-z),Vector2(x,z),Vector2(-x,z)])


static func _clip(x: float, z: float, cut: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-x+cut,-z),Vector2(x-cut,-z),Vector2(x,-z+cut),Vector2(x,z-cut),Vector2(x-cut,z),Vector2(-x+cut,z),Vector2(-x,z-cut),Vector2(-x,-z+cut)])


static func _specs() -> Dictionary:
	var t_junction := PackedVector2Array([Vector2(-9,-7),Vector2(9,-7),Vector2(9,1),Vector2(4,1),Vector2(4,8),Vector2(-4,8),Vector2(-4,1),Vector2(-9,1)])
	var furnace_l := PackedVector2Array([Vector2(-8,-7),Vector2(7,-7),Vector2(7,2),Vector2(2,2),Vector2(2,7),Vector2(-8,7)])
	var armory_l := PackedVector2Array([Vector2(-7,-7),Vector2(8,-7),Vector2(8,7),Vector2(-2,7),Vector2(-2,2),Vector2(-7,2)])
	var barracks_t := PackedVector2Array([Vector2(-8,-7),Vector2(8,-7),Vector2(8,1),Vector2(4,1),Vector2(4,7),Vector2(-4,7),Vector2(-4,1),Vector2(-8,1)])
	var root_s := PackedVector2Array([Vector2(-7,-8),Vector2(5,-8),Vector2(5,-2),Vector2(8,-2),Vector2(8,8),Vector2(-5,8),Vector2(-5,2),Vector2(-7,2)])
	var oval := PackedVector2Array([Vector2(-3.5,-8),Vector2(3.5,-8),Vector2(7,-6),Vector2(9,-2.5),Vector2(9,2.5),Vector2(7,6),Vector2(3.5,8),Vector2(-3.5,8),Vector2(-7,6),Vector2(-9,2.5),Vector2(-9,-2.5),Vector2(-7,-6)])
	return {
		"entry": {"center":Vector3(0,0,14),"footprint":_rect(4,7),"spawn":Vector3(0,0,5),"enemies":[Vector3(0,0,-3),Vector3(-1,0,-1),Vector3(1,0,1)],"walk":[Vector3(0,0,5),Vector3(0,0,0),Vector3(0,0,-5.5)]},
		"junction": {"center":Vector3(0,0,-8),"footprint":t_junction,"spawn":Vector3(0,0,5.6),"enemies":[Vector3(-5,0,-3.5),Vector3(5,0,-3.5),Vector3(0,0,-0.2)],"walk":[Vector3(0,0,5.6),Vector3(0,0,0),Vector3(-5,0,-0.2),Vector3(-5,0,-5.4),Vector3(-2,0,-5.4),Vector3(2,0,-5.4),Vector3(5,0,-5.4),Vector3(5,0,-0.2),Vector3(8,0,-0.2),Vector3(0,0,-0.2),Vector3(0,0,5.6)]},
		"furnace": {"center":Vector3(-21,0,-28),"footprint":furnace_l,"spawn":Vector3(-3,0,5.3),"enemies":[Vector3(-4,0,-3),Vector3(-3,0,1.5),Vector3(0.5,0,-2)],"walk":[Vector3(-3,0,5.3),Vector3(-3,0,0),Vector3(-5,0,-3),Vector3(-3,0,-5),Vector3(0,0,-5),Vector3(0,0,-1),Vector3(4,0,0),Vector3(0,0,0),Vector3(-3,0,0),Vector3(-3,0,5.3)]},
		"cistern": {"center":Vector3(21,0,-28),"footprint":_rect(8,8),"spawn":Vector3(0,0,6),"enemies":[Vector3(-4.5,0,-3),Vector3(4.5,0,-3),Vector3(4.5,0,3)],"walk":[Vector3(0,0,6),Vector3(-4.5,0,5.2),Vector3(-4.5,0,0),Vector3(-4.5,0,-5.2),Vector3(0,0,-6),Vector3(4.5,0,-5.2),Vector3(4.5,0,0),Vector3(4.5,0,5.2),Vector3(0,0,6),Vector3(0,0,4.7),Vector3(0,-0.275,3.5),Vector3(0,-0.55,2.3),Vector3(0,-0.55,0)]},
		"cinder_gallery": {"center":Vector3(-21,0,-51),"footprint":_rect(4,8),"spawn":Vector3(0,0,6),"enemies":[Vector3(0,0,-5),Vector3(1.3,0,-1.3),Vector3(-1.3,0,2)],"walk":[Vector3(0,0,6),Vector3(0,0,2),Vector3(0,0,-2),Vector3(0,0,-6)]},
		"pump_room": {"center":Vector3(21,0,-51),"footprint":_clip(8,7,2),"spawn":Vector3(0,0,5),"enemies":[Vector3(3,0,-4),Vector3(-3,0,-4),Vector3(3,0,2)],"walk":[Vector3(0,0,5),Vector3(2.3,0,3.5),Vector3(2.3,0,-3.5),Vector3(0,0,-5.3),Vector3(-5.4,0,-4.4),Vector3(-5.4,0,3.2),Vector3(0,0,5)]},
		"hub": {"center":Vector3(0,0,-74),"footprint":_clip(9,8,2),"spawn":Vector3(0,0,5.8),"enemies":[Vector3(-4.5,0,-3),Vector3(4.5,0,-3),Vector3(0,0,-5.5)],"walk":[Vector3(0,0,5.8),Vector3(-4.5,0,3.8),Vector3(-4.5,0,0),Vector3(-4.5,0,-4.7),Vector3(0,0,-5.5),Vector3(4.5,0,-4.7),Vector3(4.5,0,0),Vector3(4.5,0,3.8),Vector3(0,0,5.8)]},
		"armory": {"center":Vector3(-21,0,-94),"footprint":armory_l,"spawn":Vector3(3,0,5.3),"enemies":[Vector3(-3,0,-3),Vector3(4,0,-3),Vector3(3.5,0,1)],"walk":[Vector3(3,0,5.3),Vector3(3.5,0,1),Vector3(3.5,0,-4.8),Vector3(0,0,-4.8),Vector3(-3,0,-4.8),Vector3(-3,0,0),Vector3(0,0,1)]},
		"garden": {"center":Vector3(21,0,-94),"footprint":_clip(6,8,1),"spawn":Vector3(0,0,6),"enemies":[Vector3(0,0,-4.8),Vector3(2,0,-2),Vector3(-2,0,2)],"walk":[Vector3(0,0,6),Vector3(0,0,3),Vector3(0,0,0),Vector3(0,0,-3),Vector3(0,0,-6),Vector3(3.5,0,-5),Vector3(3.5,0,-1),Vector3(0,0,0),Vector3(-3.5,0,2),Vector3(-3.5,0,5),Vector3(0,0,6)]},
		"barracks": {"center":Vector3(-21,0,-116),"footprint":barracks_t,"spawn":Vector3(0,0,5.5),"enemies":[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(0,0,0)],"walk":[Vector3(0,0,5.5),Vector3(0,0,1),Vector3(-3,0,-1),Vector3(-3,0,-5),Vector3(0,0,-5),Vector3(3,0,-5),Vector3(3,0,-1),Vector3(0,0,1)]},
		"root_cellar": {"center":Vector3(21,0,-116),"footprint":root_s,"spawn":Vector3(0,0,5.6),"enemies":[Vector3(-3,0,4.5),Vector3(3,0,0),Vector3(1,0,-4.5)],"walk":[Vector3(0,0,5.6),Vector3(0,0,2),Vector3(0,0,-2),Vector3(0,0,-5.8),Vector3(-4.5,0,-5.8),Vector3(-4.5,0,0),Vector3(-3,0,4.5),Vector3(0,0,5.6),Vector3(2.5,0,5.6),Vector3(2.5,0,0)]},
		"gauntlet": {"center":Vector3(0,0,-139),"footprint":oval,"spawn":Vector3(0,0,5.8),"enemies":[Vector3(-4.4,0,-3),Vector3(4.4,0,-3),Vector3(4.4,0,3)],"walk":[Vector3(0,0,5.8),Vector3(-4.4,0,3.8),Vector3(-4.4,0,0),Vector3(-4.4,0,-4.1),Vector3(0,0,-5.8),Vector3(4.4,0,-4.1),Vector3(4.4,0,0),Vector3(4.4,0,3.8),Vector3(0,0,5.8)]},
		"summit": {"center":Vector3(0,0,-162),"footprint":_rect(8,8),"spawn":Vector3(0,0,5.6),"enemies":[Vector3(-4,1,-5),Vector3(4,1,-5),Vector3(0,1,-5)],"walk":[Vector3(0,0,5.6),Vector3(0,0,2),Vector3(0,0.175,0.8),Vector3(0,0.5,-0.5),Vector3(0,1,-2.5),Vector3(-4,1,-5),Vector3(0,1,-6.4),Vector3(4,1,-5),Vector3(0,1,-2.5),Vector3(0,0.5,-0.5),Vector3(0,0,2),Vector3(0,0,5.6)]},
		"spring": {"center":Vector3(17,0,10),"footprint":_rect(3.5,3),"spawn":Vector3(-1.6,0,0),"enemies":[Vector3(0,0,0),Vector3(1,0,1),Vector3(1,0,-1)],"walk":[Vector3(-1.6,0,0),Vector3(0,0,0),Vector3(1.4,0,-1)]},
		"archive": {"center":Vector3(-19,0,-74),"footprint":_clip(4,4.5,0.7),"spawn":Vector3(2.1,0,1.5),"enemies":[Vector3(0,0,0),Vector3(1,0,1),Vector3(-1,0,-1)],"walk":[Vector3(2.1,0,1.5),Vector3(0,0,1.5),Vector3(-1.5,0,-1.8)]},
	}

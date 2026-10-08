extends SlimeKeepersRunGeometry
class_name SlimeKeepersWorldGeometry

# The old primitive/material toolkit is shared; no old arena shell is built.
# Each permanent room owns its batches and lights, while corridor surfaces
# live on the world root. Hiding a room node never removes physical walls.
var room_nodes: Dictionary = {}
var _world_room: Dictionary = {}
var _world_id := ""
var _reward_node: Node3D


func build_world(rooms: Dictionary, connections: Array) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for child in get_children():
		remove_child(child)
		child.queue_free()
	room_nodes.clear()
	_batches.clear()
	cutaway = SlimeRoomCutaway.new()
	cutaway.name = "WorldArchitecturalCutaway"
	add_child(cutaway)
	for id: String in rooms:
		var shell: SlimeKeepersWorldGeometry = get_script().new()
		shell.name = "Room_" + id
		add_child(shell)
		shell.position = rooms[id].center
		shell._build_authored_room(id, rooms[id])
		room_nodes[id] = shell
	_theme = "entry"
	_run_materials()
	for connection: Dictionary in connections:
		_build_corridor(connection)
	_flush_batches()


func set_world_reward_visible(room_id: String, value: bool) -> void:
	if room_nodes.has(room_id):
		var shell: SlimeKeepersWorldGeometry = room_nodes[room_id]
		if is_instance_valid(shell._reward_node):
			shell._reward_node.visible = value


func _build_authored_room(id: String, room: Dictionary) -> void:
	_world_id = id
	_world_room = room
	_theme = String(room.theme)
	_exit_count = room.exits.size()
	_run_materials()
	set_meta("room_id", id)
	set_meta("footprint", room.footprint)
	_build_authored_floor()
	_build_open_boundary()
	_world_floor_pattern()
	_world_furniture()
	_world_lights()
	if id == "archive":
		_world_reward()
	_flush_batches()


func _build_authored_floor() -> void:
	if _world_id == "cistern":
		# A real lowered basin, two broad side walks and a southern return ramp.
		_rect("WestPoolWalk",-8,-2,-8,8,0,0.45,_tile)
		_rect("EastPoolWalk",2,8,-8,8,0,0.45,_tile)
		_rect("NorthPoolWalk",-2,2,-8,-2.3,0,0.45,_tile)
		_rect("SouthPoolLanding",-2,2,4.7,8,0,0.45,_tile)
		_rect("SouthPoolLeft",-2,-1.2,2.3,4.7,0,0.45,_tile)
		_rect("SouthPoolRight",1.2,2,2.3,4.7,0,0.45,_tile)
		_rect("PoolBottom",-2,2,-2.3,2.3,-0.55,0.35,_basin_tile)
		_prism("PoolReturnRamp",PackedVector2Array([Vector2(-1.2,2.3),Vector2(1.2,2.3),Vector2(1.2,4.7),Vector2(-1.2,4.7)]),PackedFloat32Array([-0.55,-0.55,0,0]),0.22,Color.WHITE,_tile,true)
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
		_rect("ShallowBasinWater",-1.9,1.9,-2.2,2.2,-0.46,0.003,_water,false)
		for x in [-2.08,2.08]:
			_box("PoolStoneRim",Vector3(x,0.12,0),Vector3(0.16,0.24,4.75),TRIM,_stone,true,0.025)
		_box("PoolRearRim",Vector3(0,0.12,-2.38),Vector3(4.30,0.24,0.16),TRIM,_stone,true,0.025)
	else:
		var polygon: PackedVector2Array = _world_room.footprint
		var heights := PackedFloat32Array()
		heights.resize(polygon.size())
		heights.fill(0.0)
		_prism("AuthoredFloor",polygon,heights,0.45,Color.WHITE,_tile,true)
		if _world_id == "summit":
			_rect("RaisedTerrace",-8,8,-8,-2.5,1.0,1.45,_tile)
			_prism("TerraceRamp",PackedVector2Array([Vector2(-2,-2.5),Vector2(2,-2.5),Vector2(2,1.5),Vector2(-2,1.5)]),PackedFloat32Array([1,1,0,0]),1.45,Color.WHITE,_tile,true)
			for side in [-1.0,1.0]:
				_box("TerraceFrontParapet",Vector3(side*5.12,1.16,-2.5),Vector3(5.75,0.32,0.24),TRIM,_stone,true,0.025)


func _build_open_boundary() -> void:
	var polygon: PackedVector2Array = _world_room.footprint
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		var length := a.distance_to(b)
		var direction := (b-a)/length
		var openings: Array[Vector2] = []
		var cuts: Array[float] = [0.0,length]
		for port: Dictionary in _world_room.ports.values():
			var at: Vector3 = port.position-_world_room.center
			var point := Vector2(at.x,at.z)
			var distance := (point-a).dot(direction)
			if point.distance_to(a+direction*distance) < 0.05 and distance >= -0.01 and distance <= length+0.01:
				var margin := float(port.width)*0.5+0.22
				var interval := Vector2(maxf(0,distance-margin),minf(length,distance+margin))
				openings.append(interval)
				cuts.append(interval.x)
				cuts.append(interval.y)
		if _world_id == "summit" and (a.y+2.5)*(b.y+2.5)<0:
			cuts.append((-2.5-a.y)/direction.y)
		cuts.sort()
		var outward := Vector2(direction.y,-direction.x)
		var height := 0.34 if outward.dot(Vector2(1,1))>0.1 else 2.65
		for part in range(cuts.size()-1):
			var from := cuts[part]
			var to := cuts[part+1]
			if to-from<0.025:
				continue
			var middle := (from+to)*0.5
			var open := false
			for interval: Vector2 in openings:
				if middle>interval.x and middle<interval.y:
					open = true
			if not open:
				var center := a+direction*middle
				var base_y := 1.0 if _world_id=="summit" and center.y<-2.49 else 0.0
				_world_wall("RoomWall",a+direction*from,a+direction*to,height,base_y)
	for port: Dictionary in _world_room.ports.values():
		var at: Vector3 = port.position-_world_room.center
		var normal: Vector3 = port.normal
		var tangent := Vector3(-normal.z,0,normal.x)
		for side in [-1.0,1.0]:
			var foot: Vector3 = at+tangent*side*(float(port.width)*0.5+0.45)-normal*0.28
			_candle_group(foot,2)


func _world_wall(label: String, a: Vector2, b: Vector2, height: float, base_y: float = 0.0) -> void:
	var length := a.distance_to(b)
	var yaw := -atan2(b.y-a.y,b.x-a.x)
	var width := 0.28 if height<0.6 else 0.40
	var middle := (a+b)*0.5
	_collision_box(label,Vector3(middle.x,base_y+height*0.5,middle.y),Vector3(length,height,width),yaw)
	var rows := maxi(1,int(round(height/0.48)))
	var columns := maxi(1,int(ceil(length/1.1)))
	for row in rows:
		for column in columns:
			var point := a.lerp(b,(float(column)+0.5)/float(columns))
			_box("WorldMasonry",Vector3(point.x,base_y+height*(float(row)+0.5)/float(rows),point.y),Vector3(length/float(columns)-0.026,height/float(rows)-0.025,width),_wall_tone.lightened(0.023*((row+column)%4)),_stone,false,0.025,yaw)
	_box("WorldCoping",Vector3(middle.x,base_y+height-0.025,middle.y),Vector3(length,0.07,width+0.035),DARK,_stone,false,0.012,yaw)


func _build_corridor(connection: Dictionary) -> void:
	var path: Array = connection.path
	var half := float(connection.width)*0.5
	var polygon := PackedVector2Array()
	for index in range(path.size()-1):
		var a: Vector3 = path[index]
		var b: Vector3 = path[index+1]
		var segment: PackedVector2Array
		if absf(a.x-b.x)<0.01:
			segment = _rectangle(a.x-half,a.x+half,minf(a.z,b.z),maxf(a.z,b.z))
		else:
			segment = _rectangle(minf(a.x,b.x),maxf(a.x,b.x),a.z-half,a.z+half)
		polygon = _union(polygon,segment)
		if index<path.size()-2:
			polygon = _union(polygon,_rectangle(b.x-half,b.x+half,b.z-half,b.z+half))
	var heights := PackedFloat32Array()
	heights.resize(polygon.size())
	heights.fill(0.0)
	_prism("Passage_"+String(connection.a)+"_"+String(connection.b),polygon,heights,0.42,Color.WHITE,_tile,true)
	var start: Vector3 = path[0]
	var finish: Vector3 = path[-1]
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		var middle := (a+b)*0.5
		# Only the two cap edges are omitted: the same opening continues
		# through each room boundary, with no invisible threshold collider.
		if middle.distance_to(Vector2(start.x,start.z))<0.05 or middle.distance_to(Vector2(finish.x,finish.z))<0.05:
			continue
		_world_wall("PassageRail",a,b,0.30)
	for index in range(path.size()-1):
		var a: Vector3 = path[index]
		var b: Vector3 = path[index+1]
		_floor_line("PassageGuide",Vector2(a.x,a.z),Vector2(b.x,b.z),0.085,_accent.darkened(0.22))
		if a.distance_to(b)>7:
			var at := a.lerp(b,0.5)
			_light(at+Vector3(0,1.7,0),Color("baa77e"),0.50,4.4,false)


func _rectangle(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0,z0),Vector2(x1,z0),Vector2(x1,z1),Vector2(x0,z1)])


func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if a.is_empty():
		return b
	var merged := Geometry2D.merge_polygons(a,b)
	assert(merged.size()==1,"Authored corridor must be one connected floor")
	return merged[0]


func _world_floor_pattern() -> void:
	match _world_id:
		"entry", "junction", "pump_room", "hub", "garden", "barracks", "root_cellar", "gauntlet":
			_floor_composition()
		"furnace":
			_floor_field(_rectangle(-6,0.6,-5.2,5.2),_floor_tone.darkened(0.055))
			for z in [-3.2,2.9]:
				_flush_drain(Vector2(-5.6,z),Vector2(0.3,z),0.23)
		"cistern":
			for x in [-5.8,5.8]:
				_floor_line("PoolWalkInlay",Vector2(x,-6.5),Vector2(x,6.5),0.14,_accent)
			for z in [-6.5,6.5]:
				_floor_line("PoolCrossInlay",Vector2(-5.8,z),Vector2(5.8,z),0.14,_accent)
		"cinder_gallery":
			for x in [-1.8,-0.9,0.0,0.9,1.8]:
				_floor_line("GalleryCopperRail",Vector2(x,-6.8),Vector2(x,6.8),0.045,_accent.darkened(0.12))
			for index in 16:
				var z := -6.7+float(index)*0.89
				_floor_line("GalleryCopperCross",Vector2(-1.8,z),Vector2(1.8,z),0.045,_accent.darkened(0.12))
		"armory":
			_floor_field(_rectangle(-0.8,5.7,-5.7,5.7),_floor_tone.lightened(0.055))
			for z in [-5.3,-3.0,1.7,4.7]:
				_floor_line("ArmoryWorkingLane",Vector2(-0.6,z),Vector2(5.5,z),0.10,_accent.darkened(0.20))
		"summit":
			_raised_ring(Vector2(0,-5.1),2.2,0.12,1.015)
			for z in [-1.8,-0.9,0.0,0.9]:
				var y: float = (1.5-z)/4.0+0.012
				_floor_line("RampStoneCourse",Vector2(-1.85,z),Vector2(1.85,z),0.045,_accent,y)
		"spring", "archive":
			_floor_field(_rectangle(-2.1,2.1,-2.2,2.2),_floor_tone.lightened(0.07))
			_mosaic_ring(Vector2.ZERO,1.35,0.10,_accent.darkened(0.22),16)


func _raised_ring(center: Vector2, radius: float, width: float, top: float) -> void:
	for index in 24:
		var a := float(index)*TAU/24.0
		var b := float(index+1)*TAU/24.0
		var polygon := PackedVector2Array([center+Vector2.from_angle(a)*radius,center+Vector2.from_angle(b)*radius,center+Vector2.from_angle(b)*(radius-width),center+Vector2.from_angle(a)*(radius-width)])
		_surface_patch("TerraceMosaic",polygon,_accent,top,_stone)


func _world_furniture() -> void:
	match _world_id:
		"entry":
			_crate(Vector3(-2.7,0.48,1.8),Vector3(1.2,0.96,1.4))
			_barrel(Vector3(-2.65,0,-3.0),0.43,1.1)
			_box("ArrivalBench",Vector3(2.65,0.40,-0.4),Vector3(1.0,0.8,4.0),WOOD,_wood,true,0.04)
			_sack(Vector3(2.65,0.8,-1.3),0.32,0.5)
		"junction":
			_box("DistributorFoot",Vector3(0,0.25,-3.6),Vector3(2.1,0.5,1.8),TRIM,_stone,true,0.07)
			_cylinder("DistributorTank",Vector3(0,1.0,-3.6),0.64,0.77,1.4,COPPER,_metal,true,20)
			_pipe(Vector3(-0.75,1.25,-3.6),Vector3(-3.4,1.25,-3.6),0.13,COPPER)
			_pipe(Vector3(0.75,1.25,-3.6),Vector3(3.4,1.25,-3.6),0.13,Color("658477"))
			_crate(Vector3(-7.6,0.4,-4.8),Vector3(1.0,0.8,1.1))
		"furnace":
			_box("CornerFurnace",Vector3(3.9,1.2,-3.8),Vector3(3.2,2.4,2.7),_wall_tone,_stone,true,0.08)
			_box("FurnaceCap",Vector3(3.9,2.42,-3.8),Vector3(3.3,0.16,2.8),DARK,_metal)
			_side_firebox(Vector3(5.56,0,-3.8))
			for x in [3.0,4.6]:
				_cylinder("FurnaceStack",Vector3(x,2.95,-4.0),0.27,0.32,0.95,DARK,_metal)
			_crate(Vector3(-6.7,0.5,3.9),Vector3(1.3,1.0,2.2))
			_barrel(Vector3(-6.7,0,1.6),0.45,1.25)
		"cistern":
			for z in [-3.6,0.0,3.6]:
				_pipe(Vector3(-7.55,2.4,z),Vector3(-7.55,0.85,z),0.12,Color("607e77"))
				_pipe(Vector3(-7.55,0.85,z),Vector3(-6.5,0.85,z),0.12,Color("607e77"))
			_cylinder("PoolValveStand",Vector3(6.7,0.6,2.0),0.42,0.52,1.2,COPPER,_metal,true,18)
			_bowl(Vector3(6.7,1.2,2.0),0.3)
		"cinder_gallery":
			for side in [-1.0,1.0]:
				var z := -1.0 if side<0 else 2.0
				_box("CoalBin",Vector3(side*2.9,0.48,z),Vector3(1.25,0.96,3.0),TRIM,_stone,true,0.035)
				_box("CoalBinContents",Vector3(side*2.9,0.99,z),Vector3(1.06,0.12,2.75),DARK,_stone,false,0.025)
			_pipe(Vector3(-3.72,2.12,-6.0),Vector3(-3.72,2.12,6.0),0.13,COPPER)
		"pump_room":
			_box("PumpFoundation",Vector3(-3.4,0.3,0),Vector3(2.2,0.6,3.4),TRIM,_stone,true,0.055)
			for z in [-0.85,0.85]:
				_cylinder("PumpPiston",Vector3(-3.4,1.2,z),0.61,0.68,1.8,Color("668985"),_metal,true,20)
				_pipe(Vector3(-3.4,1.7,z),Vector3(-6.8,1.7,z),0.12,COPPER)
			_box("PumpToolStand",Vector3(6.2,0.6,0.5),Vector3(1.1,1.2,2.3),WOOD,_wood,true,0.035)
			_bowl(Vector3(6.2,1.2,0.0),0.28)
		"hub":
			_hub_dressing()
			_cylinder("CentralBoilerFoot",Vector3(0,0.18,0),1.85,1.85,0.36,TRIM,_stone,true,24)
			_cylinder("CentralBoiler",Vector3(0,1.28,0),1.35,1.55,2.2,COPPER,_metal,true,24)
			_cylinder("BoilerCrown",Vector3(0,2.46,0),1.51,1.51,0.18,DARK,_metal)
			_pipe(Vector3(0,2.55,0),Vector3(0,3.65,0),0.3,DARK)
		"armory":
			_armory_dressing()
			_box("ArmorerWorktable",Vector3(1.0,0.51,-1),Vector3(2.6,1.02,1.4),WOOD,_wood,true,0.035)
			_box("TableAnvil",Vector3(1,1.19,-1),Vector3(0.70,0.33,0.40),TRIM,_metal,false,0.04)
			_candle_group(Vector3(0.15,1.04,-1),3)
		"garden":
			_growing_cover(Vector3(-3.6,0,-2.0),Vector3(2.3,0.8,3.4))
			_growing_cover(Vector3(3.6,0,2.0),Vector3(2.3,0.8,3.4))
			for z in [-5.8,-3.4,-1.0]:
				_box("GardenTrellis",Vector3(-5.72,1.55,z),Vector3(0.10,2.5,0.09),WOOD,_wood)
			for y in [0.8,1.5,2.2]:
				_box("GardenTrellisCross",Vector3(-5.72,y,-3.4),Vector3(0.09,0.08,5.0),WOOD,_wood)
		"barracks":
			for side in [-1.0,1.0]:
				_box("KeeperBed",Vector3(side*5.8,0.4,-2.6),Vector3(1.8,0.8,3.6),WOOD,_wood,true,0.035)
				_box("BedCover",Vector3(side*5.8,0.85,-2.6),Vector3(1.65,0.15,3.25),Color("687367"),_cloth)
				_box("BedPillow",Vector3(side*5.8,0.99,-3.7),Vector3(1.20,0.18,0.57),Color("a89c7e"),_cloth)
				_crate(Vector3(side*5.4,0.48,-5.65),Vector3(1.5,0.96,0.8))
			_barrel(Vector3(-2.8,0,4.5),0.42,1.0)
		"root_cellar":
			_growing_cover(Vector3(-2.8,0,-2.5),Vector3(2.1,1.1,3.0))
			_growing_cover(Vector3(4.5,0,3.5),Vector3(2.0,1.3,2.5))
			for index in 4:
				var z := -3.5+float(index)*0.7
				_pipe(Vector3(-6.6,0.5,z),Vector3(-4.0,1.05,z+0.28),0.11,Color("5c6242"))
			_bowl(Vector3(6.7,0,5.6),0.48)
		"gauntlet":
			_box("SealPedestal",Vector3(0,0.50,0),Vector3(2.6,1.0,2.6),_wall_tone,_stone,true,0.12)
			_cylinder("SealDisc",Vector3(0,1.04,0),1.1,1.1,0.08,_accent,_metal,false,32)
			for x in [-6.6,6.6]:
				for z in [-3.8,3.8]:
					_box("ChamberPillar",Vector3(x,1.3,z),Vector3(0.74,2.6,0.74),_wall_tone,_stone,true,0.055)
					_box("ChamberCapital",Vector3(x,2.62,z),Vector3(0.94,0.19,0.94),TRIM,_stone)
		"summit":
			for x in [-6.0,6.0]:
				_box("TerracePillar",Vector3(x,2.6,-5.7),Vector3(0.85,3.2,0.9),_wall_tone,_stone,true,0.06)
				_candle_group(Vector3(x,4.24,-5.7),4)
			_arch(Vector3(0,1,-7.4),1.15,1.6,0.32,_accent)
			_box("UpperLightNiche",Vector3(0,2.52,-7.74),Vector3(1.8,2.8,0.03),Color("789b90"),_cold_window)
		"spring":
			_side_trough(Vector3(1.9,0,1.1),1.5)
			_box("SpringRestBench",Vector3(-0.7,0.28,-2.3),Vector3(2.0,0.56,0.7),_wall_tone,_stone,true,0.04)
			_leaf_cluster(Vector3(2.7,0.55,-1.9),0.43)
			_pipe(Vector3(2.85,1.9,1.1),Vector3(2.85,0.9,1.1),0.10,Color("718675"))
		"archive":
			_bookcase(Vector3(-3.38,0,-0.1),4.9)
			_box("ArchiveDesk",Vector3(0,0.6,-3.5),Vector3(2.5,1.2,0.9),WOOD,_wood,true,0.04)
			_box("ArchiveLedger",Vector3(0,1.23,-3.5),Vector3(0.82,0.05,0.51),Color("c3b28b"),_cloth)
			_candle_group(Vector3(0.83,1.2,-3.5),3)


func _growing_cover(at: Vector3, size: Vector3) -> void:
	_box("RootBed",at+Vector3.UP*size.y*0.5,size,_wall_tone.darkened(0.10),_stone,true,0.06)
	_box("RootBedSoil",at+Vector3.UP*(size.y+0.01),Vector3(size.x-0.18,0.03,size.z-0.18),Color("3b4931"),_stone)
	for row in 4:
		for side in [-1.0,1.0]:
			_leaf_cluster(at+Vector3(side*size.x*0.23,size.y+0.18,-size.z*0.32+float(row)*size.z*0.21),0.31)


func _world_lights() -> void:
	var polygon: PackedVector2Array = _world_room.footprint
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	var radius := maxf(bounds.size.x,bounds.size.y)*0.61
	_light(Vector3(-bounds.size.x*0.22,2.4,-bounds.size.y*0.22),_lamp_tone,1.15,radius,false)
	_light(Vector3(bounds.size.x*0.26,2.0,bounds.size.y*0.20),Color("c5bfaa"),0.78,radius*0.80,false)
	if _world_id == "cistern":
		_light(Vector3(0,0.7,0),Color("77b6b2"),0.75,5.4,false)
	if _world_id == "summit":
		_light(Vector3(0,3.1,-6.3),Color("badace"),1.2,6.8,false)


func _world_reward() -> void:
	_reward_node = Node3D.new()
	_reward_node.name = "ArchiveCoreMarker"
	_reward_node.position = _world_room.reward_position-_world_room.center
	add_child(_reward_node)
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	mesh.radial_segments = 12
	mesh.rings = 6
	orb.mesh = mesh
	orb.material_override = _cold_window
	orb.position.y = 0.5
	_reward_node.add_child(orb)

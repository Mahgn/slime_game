extends SlimeKeepersWorldGeometry

const CUTAWAY = preload("res://scripts/keepers/keepers_architectural_cutaway.gd")
const ART_KIT = preload("res://scripts/keepers/keepers_facility_details.gd")
const CROWN = preload("res://scripts/keepers/keepers_building_crown.gd")
const WALL_WIDTH := 0.9
const CUT_HEIGHT := 1.05
const WALL_HEIGHT := 3.4
# Rooms can stand one metre apart. The former 1.5 m outward skins overlapped
# each other and the passage cheeks; use the actual structural envelope.
const VISIBLE_WALL_WIDTH := WALL_WIDTH
var _corridor_center := Vector2.ZERO
var _masonry: ShaderMaterial
var upper_sections: Array[Dictionary] = []
var masonry_spans: Array[Dictionary] = []
var _art_kit: SlimeKeepersGeometry
var building_crown: Node3D

func build_world(rooms: Dictionary, connections: Array) -> void:
	super.build_world(rooms, connections)
	cutaway.free()
	cutaway = CUTAWAY.new()
	cutaway.name = "FixedArchitecturalSection"
	add_child(cutaway)
	for shell: Node3D in room_nodes.values():
		cutaway.structural_sections.append_array(shell.upper_sections)
	_build_surroundings(rooms, connections)
	_art_kit = ART_KIT.new()
	_art_kit.name = "ConnectedServiceRuns"
	add_child(_art_kit)
	_art_kit.prepare()
	# Inter-room feeds are below the floors. Exposed risers belong to the
	# machines in their rooms; a doorway is never crossed by a visual pipe.
	for path: Array in [
		[Vector3(-17.4,-0.8,-10),Vector3(-17.4,-0.8,-24),Vector3(-10.7,-0.8,-24)],
		[Vector3(-10.7,-0.8,-24),Vector3(11,-0.8,-24),Vector3(11,-0.8,-26.6)],
		[Vector3(14.5,-0.8,-10.2),Vector3(14.5,-0.8,-26.6)]
	]:
		_art_kit.conduit(path,0.24,COPPER)
	_art_kit.finish()
	var portal := ART_KIT.new()
	portal.name = "FurnaceServicePortal"
	add_child(portal)
	portal.position = Vector3(-9,0,-13.5)
	portal.prepare()
	var portal_body: StaticBody3D = portal.service_portal()
	portal.finish()
	cutaway.structural_sections.append({"node":portal,"body":portal_body,"point":portal.global_position,"normal":Vector3(0,0,-1),"cut_height":CUT_HEIGHT,"keep_full":true})
	cutaway.configure_building(rooms,connections)
	_flush_batches()

func _build_authored_room(id: String, room: Dictionary) -> void:
	_world_id = id
	_world_room = room
	_theme = String(room.theme)
	_run_materials()
	_art_kit = ART_KIT.new()
	_art_kit.name = "AuthoredFacilityKit"
	add_child(_art_kit)
	_art_kit.prepare()
	if id in ["furnace","hub"]:
		_tile.shader = preload("res://shaders/keepers/facility_floor.gdshader")
		_tile.set_shader_parameter("furnace",1.0 if id == "furnace" else 0.0)
	else:
		_tile.shader = preload("res://shaders/keepers/facility_surfaces.gdshader")
		_tile.set_shader_parameter("room_style",["entry","cistern","pump_room","armory","garden","summit","spring","archive"].find(id))
		_tile.set_shader_parameter("half_extent",room.half)
	_masonry = ShaderMaterial.new()
	_masonry.shader = preload("res://shaders/keepers/facility_stone.gdshader")
	set_meta("room_id", id)
	set_meta("footprint", room.footprint)
	_build_authored_floor()
	_build_open_boundary()
	_facility_dressing()
	_workplace_details()
	if _art_kit != null:
		_art_kit.finish()
	_world_lights()
	if id == "archive":
		_world_reward()
	_flush_batches()

func _build_authored_floor() -> void:
	if _world_id == "garden":
		# A real broken channel: the east service walk always remains traversable.
		_rect("SouthCollector",-7,7,1,9,0,0.5,_tile)
		_rect("NorthCollector",-7,7,-9,-1,0,0.5,_tile)
		_rect("ServiceBypass",3.2,7,-1,1,0,0.5,_tile)
		_rect("ChannelRecovery",-7,3.2,-1,1,-0.6,0.4,_basin_tile)
		_prism("RecoverySlope",_rectangle(1,3.2,-1,1),PackedFloat32Array([-0.6,0,0,-0.6]),0.25,Color.WHITE,_tile,true)
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
		_rect("DrainWater",-6.8,0.9,-0.9,0.9,-0.54,0.01,_water,false)
	elif _world_id == "summit":
		_rect("GateFloor",-13,13,-10,10,0,0.5,_tile)
		_rect("GateDais",-13,13,-10,-2.5,1,1.5,_tile)
		_prism("GateRamp",_rectangle(-2,2,-2.5,1.5),PackedFloat32Array([1,1,0,0]),1.5,Color.WHITE,_tile,true)
		for side in [-1,1]:
			_box("DaisCoping",Vector3(side*7.6,1.18,-2.5),Vector3(10.8,0.36,0.35),TRIM,_stone,true,0.04)
	else:
		super._build_authored_floor()

func _build_open_boundary() -> void:
	# Rectangular facility shells use butt joints: horizontal courses own the
	# corners, vertical courses meet their inner face. No overlapping corner slabs.
	var polygon: PackedVector2Array = _world_room.footprint
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		var length := a.distance_to(b)
		var direction := (b-a)/length
		var cuts: Array[float] = [0.0,length]
		var openings: Array[Vector2] = []
		for port: Dictionary in _world_room.ports.values():
			var local: Vector3 = port.position-_world_room.center
			var point := Vector2(local.x,local.z)
			var along := (point-a).dot(direction)
			if point.distance_to(a+direction*along)<0.05 and along>=0 and along<=length:
				# Matches the INNER face of the passage wall, not its centre line.
				var half_open := float(port.width)*0.5-WALL_WIDTH*0.5
				var interval := Vector2(maxf(0,along-half_open),minf(length,along+half_open))
				openings.append(interval)
				cuts.append(interval.x)
				cuts.append(interval.y)
		if _world_id == "summit" and (a.y+2.5)*(b.y+2.5)<0:
			cuts.append((-2.5-a.y)/direction.y)
		cuts.sort()
		for part in range(cuts.size()-1):
			var middle := (cuts[part]+cuts[part+1])*0.5
			var open := false
			for interval: Vector2 in openings:
				open = open or (middle>interval.x and middle<interval.y)
			if open or cuts[part+1]-cuts[part]<0.025:
				continue
			var center := a+direction*middle
			var base_y := 1.0 if _world_id=="summit" and center.y<-2.49 else 0.0
			_world_wall("RoomWall",a+direction*cuts[part],a+direction*cuts[part+1],WALL_HEIGHT,base_y)

func _build_corridor(connection: Dictionary) -> void:
	var a: Vector3 = connection.path[0]
	var b: Vector3 = connection.path[-1]
	_corridor_center = Vector2((a.x+b.x)*0.5,(a.z+b.z)*0.5)
	super._build_corridor(connection)

func _world_wall(label: String, a: Vector2, b: Vector2, _old_height: float, base_y: float = 0) -> void:
	var direction := (b-a).normalized()
	var outward := Vector2(direction.y,-direction.x)
	var middle := (a+b)*0.5
	if label == "PassageRail" and outward.dot(middle-_corridor_center)<0:
		outward = -outward
	var yaw := -atan2(b.y-a.y,b.x-a.x)
	var body := StaticBody3D.new()
	body.name = "FullStructuralWall"
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	body.position = Vector3(middle.x,(base_y+WALL_HEIGHT)*0.5,middle.y)
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(a.distance_to(b),WALL_HEIGHT-base_y,WALL_WIDTH)
	shape.shape = box
	body.add_child(shape)
	# Keep visual skins within the structural footprint; neighbouring rooms
	# share short passages and must not receive overlapping wall surfaces.
	var va := a
	var vb := b
	if label == "PassageRail":
		# Visual cheeks start at the OUTER room face, not its centre plane.
		# The original full physical blocker still joins the room collision.
		va += direction*WALL_WIDTH*0.5
		vb -= direction*WALL_WIDTH*0.5
	if label != "PassageRail":
		var half: Vector2 = _world_room.half
		for endpoint in 2:
			var p: Vector2 = a if endpoint==0 else b
			var shift := 0.0
			if absf(direction.x)>0.5 and absf(absf(p.x)-half.x)<0.01:
				shift = -(VISIBLE_WALL_WIDTH-WALL_WIDTH*0.5)
			elif absf(direction.y)>0.5 and absf(absf(p.y)-half.y)<0.01:
				shift = WALL_WIDTH*0.5
			if endpoint==0: va += direction*shift
			else: vb -= direction*shift
	var offset := outward*(VISIBLE_WALL_WIDTH-WALL_WIDTH)*0.5
	va += offset
	vb += offset
	var lower = ART_KIT.new()
	lower.name = "FullHeightMasonry"
	add_child(lower)
	lower.prepare()
	_wall_courses(lower,va,vb,base_y,WALL_HEIGHT-base_y-0.18,7 if base_y<0.5 else 5,yaw)
	lower.finish()
	masonry_spans.append({"lower":lower,"body":body,"label":label})
	upper_sections.append({"node":lower,"body":body,"point":global_position+Vector3(middle.x,0,middle.y),"normal":Vector3(outward.x,0,outward.y),"base_height":base_y,"top_height":WALL_HEIGHT,"room_id":_world_id})

func _wall_courses(builder, a: Vector2, b: Vector2, bottom: float, height: float, rows: int, yaw: float) -> void:
	var length := a.distance_to(b)
	var center := (a+b)*0.5
	# Mortar fills the joints. Chamfers expose real stone faces, never empty air.
	builder._block("MortarCore",Vector3(center.x,bottom+height*0.5,center.y),Vector3(length,height,VISIBLE_WALL_WIDTH-0.075),Color("454841"),builder.masonry,0.005,Basis(Vector3.UP,yaw))
	var count := maxi(1,int(ceil(length/1.65)))
	var weights: Array[float]=[]
	var total := 0.0
	for row in rows:
		var weight := 0.83+0.34*(sin(row*7.3+bottom*4.1)*0.5+0.5)
		weights.append(weight)
		total+=weight
	var y := bottom
	for row in rows:
		var course := height*weights[row]/total
		var widths: Array[float]=[]
		var sum_width := 0.0
		for column in range(count+(1 if row%2 else 0)):
			var weight := 0.74+(sin(column*7.13+row*3.71+a.x+a.y)*0.5+0.5)*0.55
			if row%2 and (column==0 or column==count): weight*=0.57
			widths.append(weight); sum_width+=weight
		var cursor := 0.0
		for column in widths.size():
			var width := length*widths[column]/sum_width
			var p := a.lerp(b,(cursor+width*0.5)/length)
			var age := fposmod(sin(column*11.7+row*9.1+a.x*3.0+a.y)*17.13,1.0)
			var tone := _wall_tone.lightened(age*0.105).darkened(0.028 if column%4==0 else 0.0)
			tone.a=0.15+age*0.82
			builder._block("DressedMasonry",Vector3(p.x,y+course*0.5,p.y),Vector3(width-0.022,course-0.022,VISIBLE_WALL_WIDTH),tone,builder.masonry,0.025+age*0.015,Basis(Vector3.UP,yaw))
			cursor+=width
		y+=course

func _build_surroundings(rooms: Dictionary, connections: Array) -> void:
	_box("BedrockFoundation",Vector3(-6,-1.3,-26),Vector3(72,1.1,108),Color("222c2d"),_stone,false,0)
	building_crown=CROWN.new()
	building_crown.name="UnifiedBuildingMass"
	add_child(building_crown)
	building_crown.build(rooms,connections,WALL_WIDTH,WALL_HEIGHT)

func _world_lights() -> void:
	# Broad fill keeps combat readable; the brighter pools now have a visible
	# source at the desk, machine service point or final gate.
	var half: Vector2 = _world_room.half
	_light(Vector3(0,3.0,1),Color("c0c9bd"),0.48,maxf(half.x,half.y)*1.25,false)
	var positions := {
		"entry":Vector3(-1.2,2.55,-5.45),"furnace":Vector3(7.5,2.6,-8.45),
		"cistern":Vector3(6.2,2.55,-7.45),"pump_room":Vector3(4.6,2.6,-7.45),
		"hub":Vector3(-7.2,2.6,-9.45),"armory":Vector3(6.2,2.55,-6.45),
		"garden":Vector3(-5.9,2.55,-8.45)}
	if positions.has(_world_id):
		_work_lantern(positions[_world_id])
	if _world_id in ["cistern","garden"]:
		# Muted reflected water light is subordinate to the warm service lamp.
		_light(Vector3(0,0.7,0),Color("86b6ac"),0.38,6.0,false)
	if _world_id == "summit":
		_light(Vector3(0,3.1,-6.3),Color("badace"),0.65,6.8,false)

func _work_lantern(at: Vector3) -> void:
	var lamp := SlimeKeepersGeometry.new()
	lamp.name = "ServiceLantern"
	add_child(lamp)
	lamp.position = at
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("dfc389")
	glow.emission_enabled = true
	glow.emission = Color("edb96f")
	glow.emission_energy_multiplier = 1.1
	lamp._box("WallPlate",Vector3(0,0.05,0.04),Vector3(0.20,0.64,0.09),DARK,_metal,false,0.025)
	lamp._box("Hook",Vector3(0,0.33,0.16),Vector3(0.06,0.09,0.30),DARK,_metal,false,0.015)
	lamp._box("Suspension",Vector3(0,0.28,0.24),Vector3(0.05,0.17,0.05),DARK,_metal,false,0.01)
	lamp._box("Glass",Vector3(0,0,0.24),Vector3(0.28,0.37,0.25),Color.WHITE,glow,false,0.035)
	for sign_value in [-1,1]:
		lamp._box("Cap",Vector3(0,sign_value*0.23,0.24),Vector3(0.40,0.09,0.37),COPPER,_metal,false,0.025)
		for depth in [-1,1]:
			lamp._box("Cage",Vector3(sign_value*0.16,0,0.24+depth*0.145),Vector3(0.045,0.41,0.045),DARK,_metal,false,0.008)
	lamp._flush_batches()
	# A cut wall takes its mounted mesh with it. The real lamp still illuminates
	# the room: architectural cutaway is a camera convention, not a power switch.
	_attach_to_wall(lamp)
	_light(to_local(lamp.to_global(Vector3(0,0,0.55))),Color("ffd49a"),1.45,7.4,false)

func _sconce(at: Vector3) -> void:
	var bracket := SlimeKeepersGeometry.new()
	bracket.name = "WallSconce"
	add_child(bracket)
	bracket.position = at
	bracket._stone = _stone
	bracket._metal = _metal
	bracket._flame = _flame
	bracket._box("BackPlate",Vector3(0,-0.23,0.035),Vector3(0.18,0.62,0.08),DARK,_metal)
	bracket._box("Bracket",Vector3(0,-0.06,0.24),Vector3(0.50,0.12,0.50),DARK,_metal)
	bracket._pipe(Vector3(0,-0.48,0.07),Vector3(0,-0.13,0.43),0.035,DARK)
	bracket._candle_group(Vector3(0,0,0.28),3,false)
	bracket._flush_batches()
	_attach_to_wall(bracket)
	_light(to_local(bracket.to_global(Vector3(0,0.40,0.45))),Color("ffc07b"),1.4,4.8,false)

func _attach_to_wall(mounted: Node3D) -> void:
	var nearest: Dictionary = {}
	var distance := INF
	for section: Dictionary in upper_sections:
		var local: Vector3 = section.body.to_local(mounted.global_position)
		var shape: BoxShape3D = section.body.get_child(0).shape
		if absf(local.z)<distance and absf(local.x)<shape.size.x*0.5-0.12:
			nearest = section
			distance = absf(local.z)
	assert(not nearest.is_empty() and distance<1.5,"Mounted prop has no supporting wall")
	if nearest.is_empty(): return
	var inward: Vector3 = -nearest.normal
	var point: Vector3 = mounted.global_position
	var plane: Vector3 = nearest.point+inward*(WALL_WIDTH*0.5+0.004)
	point += inward*((plane-point).dot(inward))
	mounted.global_transform = Transform3D(Basis(Vector3.UP,atan2(inward.x,inward.z)),point)
	mounted.set_meta("mount_anchor",point)
	mounted.set_meta("mount_normal",inward)
	mounted.set_meta("mount_body",nearest.body)
	mounted.reparent(nearest.node,true)

func _facility_dressing() -> void:
	var half: Vector2 = _world_room.half
	# Functional thresholds and warm lights identify real doors; secrets have
	# subdued broken reveals, not bright exit rings.
	for neighbor: String in _world_room.ports:
		var port: Dictionary = _world_room.ports[neighbor]
		var at: Vector3 = port.position-_world_room.center
		var side := Vector3(-port.normal.z,0,port.normal.x)
		if neighbor not in ["spring","archive"]:
			_floor_line("WornThreshold",Vector2(at.x,at.z)-Vector2(side.x,side.z)*1.55,Vector2(at.x,at.z)+Vector2(side.x,side.z)*1.55,0.22,_accent)
	_sconce(Vector3(-half.x+0.65,2.8 if _world_id=="summit" else 1.8,-half.y+1.2))
	match _world_id:
		"entry":
			for z in [0.0,1.7,3.4]:
				_crate(Vector3(6.3,0.55,z),Vector3(1.7,1.1,1.35))
			_sack(Vector3(5.9,1.1,1.7),0.44,0.65)
			_cart(Vector3(-5,0,3.5))
			for x in [-1.4,1.4]:
				_floor_line("CargoWheelRut",Vector2(x,4),Vector2(x,-3.5),0.07,Color("403e34"))
			_art_kit.conduit([Vector3(7.8,0.8,-3.7),Vector3(7.05,0.8,-3.7),Vector3(7.05,-0.8,-3.7)],0.18,Color("728b7a"))
			_noticeboard(Vector3(-1.2,0,-5.25))
			_art_kit.dispatch_station(Vector3(-1.2,0,-4.75))
		"furnace":
			_furnace(Vector3(-5.4,0,-4.8))
			_coal_bin(Vector3(-7.1,0,3.7),Vector3(3.4,1.05,5.0))
			_cart(Vector3(-2.4,0,6.4))
			for x in [-0.65,0.65]:
				_floor_line("FurnaceCargoRail",Vector2(-2.4+x,5.6),Vector2(-2.4+x,0),0.075,COPPER)
			_art_kit.conduit([Vector3(-5.4,1.7,-6.2),Vector3(-5.4,1.7,-7.3),Vector3(-5.4,-0.8,-7.3)],0.26,Color("88704b"))
			for x in [2.0,5.0]:
				_flush_drain(Vector2(x,-1.7),Vector2(x,1.7),0.7)
			_barrel(Vector3(8.2,0,5.8),0.48,1.3)
		"cistern":
			_art_kit.settling_equipment()
			_valve(Vector3(-3.5,1.05,-6.90),0.40)
		"pump_room":
			for x in [-1.8,1.8]:
				_pump(Vector3(x,0,-2.1))
			_art_kit.conduit([Vector3(-6.6,-0.8,-6.6),Vector3(-6.6,0.85,-6.6),Vector3(5.6,0.85,-6.6),Vector3(5.6,-0.8,-6.6)],0.25,Color("728a82"))
			for x in [-5.0,0.0,4.3]:
				_art_kit.pipe_saddle(Vector3(x,0.85,-6.6),Vector3.RIGHT,0.25)
			_valve(Vector3(-5.6,0.85,-6.26),0.48)
			_workbench(Vector3(6.4,0,3.2),2.4)
		"hub":
			_boiler_assembly(Vector3(-0.7,0,0),2.15)
			# Keep the entire drop over the boiler's existing plinth. An external
			# elbow here blocks approach to fallen enemies behind the vessel.
			_art_kit.conduit([Vector3(-0.7,1.5,-1.9),Vector3(-0.7,1.5,-2.27),Vector3(-0.7,-0.8,-2.27)],0.22,Color("917046"))
			_art_kit.conduit([Vector3(1.25,1.2,0),Vector3(1.65,1.2,0),Vector3(1.65,-0.8,0)],0.22,Color("6b8270"))
			for z in [-6,5]:
				_workbench(Vector3(-8.5,0,z),2.2)
			for x in [-4.1,4.1]:
				_flush_drain(Vector2(x,-7),Vector2(x,7),0.20)
		"armory":
			for x in [-6.2,6.2]:
				_art_kit.workbench(Vector3(x,0,-3.6),3.5,"workshop" if x<0 else "fitting")
			_art_kit.gear_rack(Vector3(6.3,0,3.7))
			_art_kit.rest_bench(Vector3(-5.5,0,4.8))
			_banner(Vector3(2.6,2.7,-6.55),0)
			_noticeboard(Vector3(-3.1,0,-6.45))
		"garden":
			_art_kit.broken_collector()
		"summit":
			_art_kit.sluice()
			_raised_ring(Vector2(0,-5),2.3,0.16,1.015)
			_light(Vector3(0,3.8,-8),Color("b8d9ca"),1.4,8,false)
		"spring":
			_art_kit.maintenance_niche()
			_valve(Vector3(-3.3,1.3,1.9),0.38)
		"archive":
			_art_kit.archive_cabinet(Vector3(-3.8,0,0),6)
			_art_kit.workbench(Vector3(0,0,-3.5),3.6,"archive")
			_candle_group(Vector3(1.1,1.12,-3.4),3,true)
			_barrel(Vector3(3.4,0,3.5),0.55,1.3)

func _workplace_details() -> void:
	var placements := {
		"entry":[Vector3(2.8,2.05,-5.55),1.6,"intake"],
		"furnace":[Vector3(7.0,1.7,-8.55),1.7,"hearth"],
		"cistern":[Vector3(-5.5,2.25,-7.55),1.6,"water"],
		"pump_room":[Vector3(0,2.1,-7.55),3.0,"pressure"],
		"hub":[Vector3(3.8,2.1,-9.55),2.6,"boiler"],
		"armory":[Vector3(7.9,2.0,-6.55),1.3,"parts"],
		"garden":[Vector3(3.5,2.05,-8.55),1.8,"collector"],
		"summit":[Vector3(-12.55,2.60,-4.8),1.9,"sluice"],
		"spring":[Vector3(1.0,2.0,-2.55),1.55,"tools"],
		"archive":[Vector3(0,2.25,-4.55),2.8,"plan"]}
	var spec: Array = placements[_world_id]
	var detail := ART_KIT.new()
	detail.name = "WallServiceDetail"
	add_child(detail)
	detail.position = spec[0]
	detail.prepare()
	detail.service_detail(spec[2],spec[1])
	detail.finish()
	_attach_to_wall(detail)
	match _world_id:
		"armory":
			for x in [-6.2,6.2]:
				_art_kit.work_mat(Vector3(x,0,-3.15),Vector2(4.4,2.5),Color("414d3d"))
		"archive":
			_art_kit.work_mat(Vector3(0,0,-3.2),Vector2(4.2,2.5),Color("505043"))
		"hub":
			for z in [-6,5]:
				_art_kit.work_mat(Vector3(-8.5,0,z+0.3),Vector2(2.8,2.0),Color("494a3b"))

func _furnace(at: Vector3) -> void:
	_art_kit.furnace(at)

func _boiler_assembly(at: Vector3, radius: float) -> void:
	_art_kit.boiler(at,radius)

func _pump(at: Vector3) -> void:
	_art_kit.pump(at)

func _valve(at: Vector3, radius: float) -> void:
	_art_kit.valve_wheel(at,radius)

func _sack(at: Vector3, radius: float, height: float) -> void:
	_art_kit._sack(at,radius,height)

func _barrel(at: Vector3, radius: float, height: float) -> void:
	_art_kit.coopered_barrel(at,radius,height)

func _crate(at: Vector3, size: Vector3) -> void:
	_art_kit.cargo_crate(at,size)

func _workbench(at: Vector3, width: float) -> void:
	_art_kit.workbench(at,width)

func _coal_bin(at: Vector3, size: Vector3) -> void:
	_art_kit.coal_bin(at,size)

func _cart(at: Vector3) -> void:
	_art_kit.cart(at)

func _noticeboard(at: Vector3) -> void:
	var board := SlimeKeepersGeometry.new()
	board.name = "WallNoticeboard"
	add_child(board)
	board.position = at+Vector3.UP*1.65
	board._box("DutyBoard",Vector3(0,0,0.045),Vector3(1.6,1.1,0.09),WOOD,_wood,false,0.025)
	for i in 3:
		board._box("ServiceNotice",Vector3(-0.48+i*0.45,0.05,0.103),Vector3(0.35,0.7-i*0.07,0.015),Color("bdac87"),_cloth,false,0)
	board._flush_batches()
	_attach_to_wall(board)

func _banner(at: Vector3, _yaw: float) -> void:
	var banner := SlimeKeepersGeometry.new()
	banner.name = "WallBanner"
	add_child(banner)
	banner.position = at
	banner._metal = _metal
	banner._cloth = _cloth
	banner._banner(Vector3(0,0,0.08),0)
	for x in [-0.42,0.42]:
		banner._box("RodBracket",Vector3(x,0,0.04),Vector3(0.08,0.14,0.12),DARK,_metal)
	banner._flush_batches()
	_attach_to_wall(banner)

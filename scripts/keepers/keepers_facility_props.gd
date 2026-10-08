extends "res://scripts/keepers/keepers_facility_art.gd"

# F05 room equipment, built from the F04 material/profile kit. Large physical
# bodies are explicit; tools, leaves, bolts and cables are visual dressing.
var foliage: StandardMaterial3D

func prepare() -> void:
	super.prepare()
	foliage = _vertex_material(0.97)
	foliage.cull_mode = BaseMaterial3D.CULL_DISABLED

func pump(at: Vector3) -> void:
	_block("PumpMasonryBed",at+Vector3.UP*0.2,Vector3(1.9,0.4,3.2),Color("56594e"),masonry,0.11)
	_collision_box("PumpPlinth",at+Vector3.UP*0.2,Vector3(1.9,0.4,3.2),0)
	_lathe("CastPumpHousing",at,[Vector2(0,0.4),Vector2(0.76,0.4),Vector2(0.76,0.55),Vector2(0.63,0.66),Vector2(0.63,1.37),Vector2(0.74,1.45),Vector2(0.74,1.61),Vector2(0.55,1.77),Vector2(0,1.77)],Color("5d8075"),copper,Basis.IDENTITY,true)
	for y in [0.52,1.50]:
		_ring("PumpSealingFlange",at+Vector3.UP*y,0.71,0.065,Color("393f34"),iron)
		for i in 12:
			var a := i*TAU/12
			_cylinder("PumpFlangeStud",at+Vector3(sin(a)*0.68,y+0.09,cos(a)*0.68),0.045,0.045,0.085,Color("b39a67"),copper,false,6)
	# Piston guide and fork connect the cylinder to the actual flywheel axle.
	_strut(at+Vector3(0,1.72,0),at+Vector3(0,2.61,0),0.12,Color("b7b4a0"),_metal)
	for side in [-1,1]:
		_block("PumpGuide",at+Vector3(side*0.43,2.07,0),Vector3(0.12,1.02,0.16),Color("53695b"),iron,0.028)
	_block("PistonCrosshead",at+Vector3(0,2.43,0),Vector3(1.0,0.21,0.33),Color("6c7a63"),copper,0.04)
	_flywheel(at+Vector3(0,2.41,-0.64),0.78,Color("92744b"))
	_strut(at+Vector3(0,2.41,-0.74),at+Vector3(0,2.41,0.05),0.10,Color("606f5d"),iron)
	_strut(at+Vector3(0,2.43,0.06),at+Vector3(0.34,2.08,-0.47),0.065,Color("c4af7b"),copper)
	_gauge(at+Vector3(-0.30,1.16,0.65),0.19)
	# The maintenance aisle behind the pumps remains continuous. Feeds drop
	# inside each plinth, cross below the floor, then rise into the wall manifold.
	conduit([at+Vector3(0,0.85,-0.57),at+Vector3(0,0.85,-1.05),at+Vector3(0,-0.8,-1.05),at+Vector3(0,-0.8,-4.5),at+Vector3(0,0.85,-4.5)],0.23,Color("688376"))
	_block("PumpInspectionPlate",at+Vector3(0.24,0.99,0.615),Vector3(0.36,0.34,0.07),Color("424c3e"),iron,0.04)

func workbench(at: Vector3, width: float, role: String = "repair") -> void:
	_collision_box("Workbench",at+Vector3.UP*0.55,Vector3(width,1.1,1.15),0)
	for plank in 4:
		_block("PlanedWorkbenchTop",at+Vector3(0,1.02,-0.43+plank*0.286),Vector3(width,0.18,0.263),Color("896b44").darkened((plank%3)*0.06),_wood,0.026)
	for side in [-1,1]:
		for z in [-0.39,0.39]:
			_block("WorkbenchLeg",at+Vector3(side*(width*0.5-0.22),0.47,z),Vector3(0.18,0.94,0.18),Color("5e4c30"),_wood,0.025)
		_block("BenchTrestleTie",at+Vector3(side*(width*0.5-0.22),0.30,0),Vector3(0.24,0.14,1.0),Color("685338"),_wood,0.02)
	_block("LowerStorageShelf",at+Vector3.UP*0.32,Vector3(width-0.35,0.09,0.82),Color("5b482e"),_wood,0.02)
	if role == "archive":
		_ledger(at+Vector3(-width*0.18,1.1325,0),0.78)
		for i in 3:
			_cylinder("RolledMaintenancePlan",at+Vector3(width*0.27,1.175,-0.28+i*0.17),0.065,0.065,0.66,Color("b6a781"),_cloth,false,12,Vector3(0,0,PI/2))
		_cylinder("InkPot",at+Vector3(width*0.37,1.19,0.25),0.085,0.095,0.16,Color("343b31"),iron,false,12)
	else:
		# Jaw blocks, spindle and handle read as a vice at normal camera scale.
		var vice := at+Vector3(width*0.31,1.18,0.30)
		_block("ViceFoot",vice,Vector3(0.57,0.14,0.5),Color("4c645a"),iron,0.035)
		for z in [-0.12,0.19]:
			_block("ViceJaw",vice+Vector3(0,0.18,z),Vector3(0.60,0.23,0.12),Color("778877"),iron,0.025)
		_strut(vice+Vector3(0,0.13,0.24),vice+Vector3(0,0.13,0.51),0.047,Color("a79670"),copper)
		_strut(vice+Vector3(-0.21,0.13,0.50),vice+Vector3(0.21,0.13,0.50),0.027,Color("b9aa83"),copper)
		if role != "fitting":
			_hammer(at+Vector3(-width*0.23,1.105,0.05))
		if role == "fitting":
			_block("BearingAlignmentStand",at+Vector3(-width*0.20,1.28,-0.15),Vector3(0.8,0.34,0.65),Color("4e5d4d"),iron,0.04)
			_flywheel(at+Vector3(-width*0.20,1.82,0.25),0.47,Color("9b8150"))
			_block("BearingPedestal",at+Vector3(-width*0.20,1.66,-0.15),Vector3(0.22,0.45,0.27),Color("4e5d4d"),iron,0.025)
			_strut(at+Vector3(-width*0.20,1.82,-0.15),at+Vector3(-width*0.20,1.82,0.32),0.09,Color("a09273"),copper)
		_ring("RepairGasket",at+Vector3(0,1.14,-0.17),0.21,0.035,Color("a88853"),copper)
		for i in 4:
			_block("SpareBearingBox",at+Vector3(-width*0.28+i*width*0.18,0.5,0),Vector3(width*0.15,0.26,0.6),Color("64513a").lightened(i*0.025),_wood,0.025)
		if role == "workshop":
			for side in [-1,1]:
				_block("ToolBoardPost",at+Vector3(side*(width*0.5-0.25),1.41,-0.54),Vector3(0.13,1.55,0.14),Color("665034"),_wood,0.02)
			_block("ToolBoard",at+Vector3(0,1.68,-0.54),Vector3(width-0.15,1.03,0.08),Color("5b4e36"),_wood,0.03)
			for i in 5:
				var x := -width*0.37+i*width*0.18
				_strut(at+Vector3(x,1.53,-0.46),at+Vector3(x,1.93,-0.46),0.035,Color("a3926d"),copper)
				_strut(at+Vector3(x,2.02,-0.51),at+Vector3(x,2.02,-0.40),0.018,Color("454f42"),iron)
				_ring("HangingWrench",at+Vector3(x,1.96,-0.46),0.09,0.022,Color("aaa58a"),_metal,Basis(Vector3.RIGHT,PI/2))

func gear_rack(at: Vector3) -> void:
	# Fits within the old loose-gear corner; the base is a visible low blocker.
	_block("GearRackFoot",at+Vector3.UP*0.14,Vector3(2.35,0.28,1.0),Color("615239"),_wood,0.06)
	_collision_box("GearRackFoot",at+Vector3.UP*0.14,Vector3(2.35,0.28,1.0),0)
	for side in [-1,1]:
		_block("RackUpright",at+Vector3(side*0.95,0.73,-0.24),Vector3(0.16,1.46,0.2),Color("655335"),_wood,0.025)
	_strut(at+Vector3(-1,1.05,-0.2),at+Vector3(1,1.05,-0.2),0.08,Color("4c5749"),iron)
	_flywheel(at+Vector3(-0.45,0.99,0),0.70,Color("887048"))
	_flywheel(at+Vector3(0.71,0.69,0.11),0.40,Color("647465"))

	for anchor in [Vector3(-0.45,0.99,0),Vector3(0.71,0.69,0.11)]:
		_strut(at+Vector3(anchor.x,1.05,-0.2),at+anchor,0.045,Color("70745c"),iron)

func rest_bench(at: Vector3) -> void:
	_collision_box("StaffRestBench",at+Vector3.UP*0.36,Vector3(3.5,0.72,0.9),0)
	for z in [-0.30,0.0,0.30]:
		_block("RestBenchSeat",at+Vector3(0,0.66,z),Vector3(3.5,0.12,0.28),Color("897246"),_wood,0.025)
	for x in [-1.25,1.25]:
		_block("RestBenchFoot",at+Vector3(x,0.30,0),Vector3(0.22,0.60,0.82),Color("596451"),iron,0.04)
	_strut(at+Vector3(-1.25,0.22,0),at+Vector3(1.25,0.22,0),0.07,Color("65563b"),_wood)

func sluice() -> void:
	# Same footprints as the original piers and gate; the platform and exit
	# stay entirely clear. Recessed panels replace the single blank rectangle.
	for side in [-1,1]:
		var at := Vector3(side*9.6,1,-7.6)
		_collision_box("SluicePier",at+Vector3.UP*1.5,Vector3(2.2,3,3),0)
		for row in 6:
			for part in 2:
				_block("AshlarWinchPier",at+Vector3(-0.55+part*1.1,0.25+row*0.5,0),Vector3(1.07,0.47,3),Color("70766a").darkened((row+part)%3*0.04),masonry,0.05)
		_block("PierCapital",at+Vector3(0,3.05,0),Vector3(2.35,0.20,3.15),Color("8b8972"),masonry,0.055)
		_flywheel(at+Vector3(0,2.13,1.57),1.02,Color("a28b5c"))
		_strut(at+Vector3(0,2.13,1.05),at+Vector3(0,2.13,1.66),0.13,Color("65715e"),iron)
		_cylinder("WinchDrum",at+Vector3(0,2.1,0.35),0.58,0.58,1.6,Color("4b6054"),iron,false,24,Vector3(PI/2,0,0))
		for i in 6:
			_ring("WinchCableTurns",at+Vector3(0,2.1,-0.21+i*0.20),0.60,0.038,Color("9d916e"),copper,Basis(Vector3.RIGHT,PI/2))
		conduit([at+Vector3(0,2.7,-0.25),Vector3(side*4.9,3.7,-7.85),Vector3(side*4.9,3.7,-8.92)],0.15,Color("877957"))
		# Vertical rack has meaningful connection to the moving iron leaf.
		_block("GateRackRail",Vector3(side*4.9,2.70,-8.90),Vector3(0.20,3.25,0.16),Color("4f6054"),iron,0.02)
		for tooth in 14:
			_block("GateRackTooth",Vector3(side*4.9,1.20+tooth*0.23,-8.77),Vector3(0.31,0.09,0.11),Color("a89871"),copper,0.01)
	_collision_box("IronSluice",Vector3(0,2.55,-9.2),Vector3(13,3.1,0.35),0)
	_block("SluiceInnerLeaf",Vector3(0,2.55,-9.2),Vector3(13,3.1,0.35),Color("3c5b51"),iron,0.06)
	for column in 6:
		var x := -5.45+column*2.18
		for row in 2:
			_block("GateRecessPanel",Vector3(x,1.80+row*1.39,-8.98),Vector3(1.97,1.16,0.09),Color("536e5b").darkened((column+row)%3*0.055),copper,0.07)
			for side in [-1,1]:
				_rivet(Vector3(x+side*0.83,1.40+row*1.39,-8.90),0.05)
		_block("GateStile",Vector3(x-1.07,2.55,-8.89),Vector3(0.11,3.05,0.17),Color("aa9160"),copper,0.025)
	for y in [1.14,2.49,4.02]:
		_block("GateCrossRail",Vector3(0,y,-8.87),Vector3(13.18,0.16,0.23),Color("6b7058"),iron,0.04)
	for side in [-1,1]:
		_block("CarvedGateJamb",Vector3(side*2.51,1.82,-8.70),Vector3(0.48,1.65,0.55),Color("8a8b74"),masonry,0.06)
		_collision_box("GateJamb",Vector3(side*2.51,1.82,-8.70),Vector3(0.48,1.65,0.55),0)
	for i in 13:
		var arch_mesh := _arch_stone(Vector3(0,2.60,-8.47),2.22,2.58,i*PI/13+0.006,(i+1)*PI/13-0.006,0.55,Color("a3a087").darkened((i%3)*0.04))
		var body := StaticBody3D.new()
		body.name = "GateArchStone"
		body.collision_layer = 1
		body.collision_mask = 2
		body.position = Vector3(0,2.60,-8.47)
		var shape := CollisionShape3D.new()
		shape.shape = arch_mesh.create_convex_shape()
		body.add_child(shape)
		add_child(body)
	# Small brass water emblem, modelled instead of baked text or a UI sign.
	_ring("GateMedallion",Vector3(0,3.05,-8.78),0.50,0.055,Color("c0ac77"),copper,Basis(Vector3.RIGHT,PI/2))
	for y in [2.82,3.02,3.22]:
		_strut(Vector3(-0.32,y,-8.70),Vector3(0.32,y+0.10,-8.70),0.025,Color("c6b581"),copper)

func settling_equipment() -> void:
	# Scale staff and filter baskets stay against the basin edge; the ramp and
	# the two broad walks keep their existing clearance.
	_block("WaterLevelStaff",Vector3(-1.97,0.51,-1.35),Vector3(0.12,1.6,0.14),Color("bdc4a7"),_stone,0.02)
	for i in 10:
		_block("WaterLevelNotch",Vector3(-1.90,-0.14+i*0.14,-1.35),Vector3(0.018,0.023,0.12),Color("41524a"),iron,0.006)
	for side in [-1,1]:
		# Buried feed leaves the north maintenance walk open. Only the wall
		# drop and short outlet inside the basin are exposed above the stone.
		var at := Vector3(side*3.5,0,-7.2)
		conduit([at+Vector3(0,1.5,-0.65),at+Vector3.UP*1.5,at-Vector3.UP*0.85,Vector3(side*1.45,-0.85,-2.65),Vector3(side*1.45,-0.10,-2.65),Vector3(side*1.45,-0.10,-1.9)],0.22,Color("6b9182"))
		_ring("StrainerMouth",Vector3(side*1.45,-0.10,-1.9),0.26,0.045,Color("a09065"),copper,Basis(Vector3.RIGHT,PI/2))
		_pipe_body("WallFeed",at+Vector3.UP*1.5,at,0.22)
	for z in [-5.6,5.6]:
		var p := Vector3(6.6,0,z)
		_block("SettlingButtress",p+Vector3.UP*0.60,Vector3(1.3,1.2,1.2),Color("6b7969"),masonry,0.08)
		_collision_box("SettlingButtress",p+Vector3.UP*0.60,Vector3(1.3,1.2,1.2),0)
		_block("FilterBasket",p+Vector3.UP*1.35,Vector3(0.86,0.3,0.83),Color("374e44"),iron,0.06)
		for i in 6:
			_strut(p+Vector3(-0.35+i*0.14,1.515,-0.36),p+Vector3(-0.35+i*0.14,1.515,0.36),0.018,Color("a18d61"),copper)
	fern(Vector3(6.6,0.03,-3.1),0.80,0.4)
	fern(Vector3(6.8,0.03,2.5),0.55,1.1)

func dispatch_station(at: Vector3) -> void:
	workbench(at,2.7,"archive")
	# Balance scales make this a receiving station, not another repair table.
	_strut(at+Vector3(0.80,1.12,-0.20),at+Vector3(0.80,1.95,-0.20),0.045,Color("bb9e68"),copper)
	_strut(at+Vector3(0.30,1.86,-0.20),at+Vector3(1.30,1.86,-0.20),0.032,Color("bb9e68"),copper)
	for x in [0.32,1.28]:
		for z in [-0.34,-0.06]:
			_strut(at+Vector3(x,1.86,-0.20),at+Vector3(x,1.44,z),0.009,Color("a39268"),copper)
		_bowl(at+Vector3(x,1.35,-0.2),0.21)

func maintenance_niche() -> void:
	conduit([Vector3(-3.30,1.3,-2.85),Vector3(-3.3,1.3,1.5),Vector3(-3.3,-0.8,1.5)],0.30,Color("597f6f"))
	pipe_saddle(Vector3(-3.3,1.3,-1.7),Vector3.FORWARD,0.30)
	pipe_saddle(Vector3(-3.3,1.3,0.5),Vector3.FORWARD,0.30)
	_strut(Vector3(-3.3,1.3,-0.7),Vector3(-3.3,1.75,-0.7),0.07,Color("667562"),iron)
	_gauge(Vector3(-3.3,1.75,-0.65),0.20)
	_block("OpenToolChest",Vector3(0,0.25,1.9),Vector3(1.5,0.5,0.65),Color("73583b"),_wood,0.05)
	_collision_box("InspectionTools",Vector3(0,0.25,1.9),Vector3(1.5,0.5,0.65),0)
	_block("ChestDarkInterior",Vector3(0,0.509,1.9),Vector3(1.27,0.017,0.46),Color("2d352b"),_stone,0.01)
	_hammer(Vector3(-0.21,0.514,1.89))
	for x in [-0.6,0.6]:
		_block("ChestIronBand",Vector3(x,0.25,2.24),Vector3(0.11,0.5,0.05),Color("364739"),iron,0.01)
	fern(Vector3(-2.6,0.02,-2.1),0.62,0.7)

func archive_cabinet(at: Vector3, length: float) -> void:
	_collision_box("RecordsCabinet",at+Vector3(0.15,1.2,0),Vector3(1,2.4,length+0.14),0)
	_block("CabinetDarkBack",at+Vector3(-0.18,1.17,0),Vector3(0.25,2.34,length),Color("483e2c"),_wood,0.035)
	for y in [0.13,0.84,1.59,2.34]:
		_block("CabinetShelf",at+Vector3(0.15,y,0),Vector3(1,0.12,length+0.1),Color("907244"),_wood,0.028)
	for z in [-length*0.5,0,length*0.5]:
		_block("CabinetUpright",at+Vector3(0,1.2,z),Vector3(0.91,2.4,0.14),Color("75603b"),_wood,0.028)
	for row in 3:
		for i in 10:
			var z := -length*0.44+i*length*0.095
			var height := 0.36+float((i*3+row)%4)*0.07
			var tint: Color = [Color("80583e"),Color("566f5a"),Color("8d7b49"),Color("65594d")][(i+row)%4]
			_block("BoundRepairJournal",at+Vector3(0.29,[0.19,0.90,1.65][row]+height*0.5,z),Vector3(0.44,height,length*0.077),tint,_cloth,0.016)
			for y in [-0.3,0.3]:
				_block("JournalSpineBand",at+Vector3(0.515,[0.19,0.90,1.65][row]+height*(0.5+y),z),Vector3(0.015,0.023,length*0.077),Color("baa574"),_cloth,0.004)

func broken_collector() -> void:
	for z in [-6.0,5.0]:
		var at := Vector3(-5.6,0,z)
		_block("BrokenVaultFoundation",at+Vector3.UP*0.5,Vector3(1.7,1,2.2),Color("6a735d"),masonry,0.12)
		_collision_box("BrokenVaultFoot",at+Vector3.UP*0.5,Vector3(1.7,1,2.2),0)
		for i in 4:
			_block("CollapsedVaultCourse",at+Vector3(-0.25,1.14+i*0.26,-0.52),Vector3(1.2-i*0.19,0.25,0.92),Color("757e65"),masonry,0.075)
			_collision_box("CollapsedVaultCourse",at+Vector3(-0.25,1.14+i*0.26,-0.52),Vector3(1.2-i*0.19,0.25,0.92),0)
		fern(at+Vector3(0.25,1.0,0.30),0.95,z)
		fern(at+Vector3(-0.56,1.0,0.10),0.72,z+1)
		for i in 3:
			var start := at+Vector3(-0.34,1.94,-0.52+i*0.05)
			var mid := at+Vector3(-0.40,0.96,0.98)
			_root(start,mid,0.09)
			_root(mid,at+Vector3(0.45+i*0.18,0.08,0.79),0.058)
	# Boards lie on the safe bypass; broken ends point towards the real channel.
	for i in 5:
		_block("ServiceCrossingBoard",Vector3(4.65,0.035,-0.76+i*0.38),Vector3(2.75,0.07,0.34),Color("716442").darkened((i%3)*0.07),_wood,0.022)
		for x in [3.49,5.81]:
			_cylinder("BoardFixing",Vector3(x,0.078,-0.76+i*0.38),0.028,0.028,0.02,Color("a49a73"),iron,false,6)
	for side in [-1,1]:
		var pipe_a := Vector3(6.15,0.65,side*7.6)
		var pipe_b := Vector3(6.15,0.65,side*1.8)
		conduit([Vector3(6.85,0.65,side*7.6),pipe_a,pipe_b],0.27,Color("55766a"))
		for z in [side*6.7,side*2.7]:
			pipe_saddle(Vector3(6.15,0.65,z),Vector3.FORWARD,0.27)
		_pipe_body("BrokenCollectorPipe",pipe_a,pipe_b,0.27)
		_ring("BrokenConduitFlange",pipe_b,0.33,0.055,Color("92906a"),copper,Basis(Vector3.RIGHT,PI/2))
	for i in 14:
		_shard(Vector3(-5.7+i*0.26,0.06,2.60+sin(i*3.7)*0.38),Vector3(0.21,0.13,0.28),Color("75806a"),masonry,i)

func fern(at: Vector3, size: float, phase: float) -> void:
	# Folded lance-shaped leaves with a raised midrib. No flowerpot-like lumps.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in 7:
		var angle := phase+frond*TAU/7
		var forward := Vector3(sin(angle),0,cos(angle))
		var across := Vector3(cos(angle),0,-sin(angle))
		var height := size*(0.42+0.17*sin(frond*3+phase))
		for segment in 5:
			var a := segment/5.0
			var b := (segment+1)/5.0
			var center_a := forward*size*a*0.77+Vector3.UP*sin(a*PI*0.82)*height
			var center_b := forward*size*b*0.77+Vector3.UP*sin(b*PI*0.82)*height
			var wa := size*0.16*sin(a*PI)
			var wb := size*0.16*sin(b*PI)
			for side in [-1,1]:
				var pa: Vector3 = center_a+across*side*wa-Vector3.UP*wa*0.34
				var pb: Vector3 = center_b+across*side*wb-Vector3.UP*wb*0.34
				var tint := Color("52754d").lightened(frond%3*0.055)
				var normal: Vector3 = (across*side-Vector3.UP*0.34).cross(center_b-center_a).normalized()
				if normal.y<0: normal = -normal
				_triangle(tool,center_a,pa,pb,normal,tint)
				_triangle(tool,center_a,pb,center_b,normal,tint)
	tool.index()
	_emit("FoldedFernFronds",tool.commit(),Transform3D(Basis.IDENTITY,at),foliage,false)

func press_dressing(size: Vector2, moving_head: bool) -> void:
	if moving_head:
		_block("ForgedPressWeight",Vector3.ZERO,Vector3(size.x*0.92,0.5,size.y*0.92),Color("54675a"),iron,0.09)
		for side in [-1,1]:
			_block("WeightForgedBand",Vector3(0,0,side*size.y*0.40),Vector3(size.x*0.96,0.18,0.13),Color("a49165"),copper,0.028)
			for x in [-size.x*0.36,size.x*0.36]:
				_rivet(Vector3(x,0.01,side*size.y*0.465),0.055)
		_block("PistonLink",Vector3(0,0.39,0),Vector3(0.32,0.35,0.34),Color("a3ab93"),_metal,0.04)
	else:
		for side in [-1,1]:
			var x: float = side*(size.x*0.5+0.14)
			_block("DriveGuideFoot",Vector3(x,0.09,0),Vector3(0.27,0.18,0.38),Color("736f52"),masonry,0.03)
			_block("DriveGuideCapital",Vector3(x,3.04,0),Vector3(0.26,0.20,0.27),Color("839078"),iron,0.04)
		_block("PressCrosshead",Vector3(0,3.10,0),Vector3(size.x+0.49,0.18,0.22),Color("536654"),iron,0.04)
		_cylinder("HydraulicPistonSocket",Vector3(0,2.82,0),0.24,0.24,0.50,Color("7f8b74"),copper,false,20)

func _flywheel(at: Vector3, radius: float, tint: Color) -> void:
	var face := Basis(Vector3.RIGHT,PI/2)
	_ring("FlywheelOuterRim",at,radius*0.89,radius*0.10,tint,copper,face)
	_ring("FlywheelEdge",at+Vector3(0,0,0.045),radius*0.95,0.033,Color("bbb18b"),_metal,face)
	_cylinder("FlywheelHub",at,0.18*radius,0.18*radius,0.31,tint,iron,false,16,Vector3(PI/2,0,0))
	for i in 6:
		var a := i*TAU/6
		_strut(at,at+Vector3(sin(a),cos(a),0)*radius*0.85,radius*0.058,tint,copper)
	for i in 18:
		var a := i*TAU/18
		_box("FlywheelTooth",at+Vector3(sin(a),cos(a),0)*radius,Vector3(radius*0.13,radius*0.17,0.12),tint,iron,false,0.015,0,Vector3(0,0,-a))

func _hammer(at: Vector3) -> void:
	_strut(at+Vector3(0,0.045,-0.22),at+Vector3(0,0.045,0.32),0.038,Color("9a7644"),_wood)
	_block("HammerHead",at+Vector3(0,0.08,-0.19),Vector3(0.34,0.15,0.17),Color("80917b"),iron,0.026)

func _ledger(at: Vector3, width: float) -> void:
	_block("LedgerCover",at,Vector3(width,0.045,width*0.72),Color("594831"),_wood,0.022)
	for side in [-1,1]:
		_block("LedgerPages",at+Vector3(side*width*0.235,0.034,0),Vector3(width*0.44,0.04,width*0.66),Color("c9bb91"),_cloth,0.008)
		for line in 5:
			_block("LedgerRuling",at+Vector3(side*width*0.235,0.057,-width*0.21+line*width*0.098),Vector3(width*0.32,0.004,0.01),Color("8d8669"),_cloth,0)

func _root(a: Vector3, b: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*0.52
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	mesh.rings = 1
	_emit("RootThroughVault",_color_mesh(mesh,Color("626242")),Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5),_stone,false)

func _pipe_body(label: String, a: Vector3, b: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 2
	body.transform = Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = a.distance_to(b)
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)

func pipe_saddle(at: Vector3, direction: Vector3, radius: float) -> void:
	# A collar, a continuous pedestal and an anchored foot form one support.
	var basis := Basis(Quaternion(Vector3.UP,direction))
	_ring("AnchoredPipeClamp",at,radius+0.025,0.04,Color("4b5749"),iron,basis)
	var height := maxf(0.05,at.y-radius)
	_block("PipeSaddleStem",Vector3(at.x,height*0.5,at.z),Vector3(0.16,height,0.16),Color("4b5749"),iron,0.018)
	_block("PipeSaddleFoot",Vector3(at.x,0.045,at.z),Vector3(0.40,0.09,0.38),Color("6d6e59"),iron,0.025)

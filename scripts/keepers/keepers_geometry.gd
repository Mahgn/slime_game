extends Node3D
class_name SlimeKeepersGeometry

# One authored hall. Draw calls are batched by material; static bodies retain
# the same surfaces used to build the visible walkable geometry.
const FLOOR_SHADER = preload("res://shaders/keepers/floor.gdshader")
const WATER_SHADER = preload("res://shaders/keepers/water.gdshader")
const WOOD_SHADER = preload("res://shaders/keepers/wood.gdshader")
const GRIME_SHADER = preload("res://shaders/keepers/contact_grime.gdshader")
const WALL := Color("62594b")
const WALL_ALT := Color("706453")
const DARK := Color("292d2b")
const TRIM := Color("444740")
const WOOD := Color("64452e")
const COPPER := Color("71573c")

var cutaway: SlimeRoomCutaway
var _batches: Dictionary = {}
var _stone: StandardMaterial3D
var _metal: StandardMaterial3D
var _tile: ShaderMaterial
var _basin_tile: ShaderMaterial
var _cloth: StandardMaterial3D
var _flame: StandardMaterial3D
var _coal: StandardMaterial3D
var _water: ShaderMaterial
var _water_time := 0.0
var _wood: ShaderMaterial
var _grime: ShaderMaterial
var _cold_window: StandardMaterial3D


func build() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	cutaway = SlimeRoomCutaway.new()
	cutaway.name = "ArchitecturalCutaway"
	add_child(cutaway)
	_stone = _vertex_material(0.91)
	_metal = _vertex_material(0.47, 0.66)
	_cloth = _vertex_material(1.0)
	_tile = ShaderMaterial.new()
	_tile.shader = FLOOR_SHADER
	_tile.set_shader_parameter("tile_color", Color("756d59"))
	_basin_tile = ShaderMaterial.new()
	_basin_tile.shader = FLOOR_SHADER
	_basin_tile.set_shader_parameter("tile_color", Color("526c64"))
	_flame = _vertex_material(0.4)
	_flame.emission_enabled = true
	_flame.emission = Color("ffa331")
	_flame.emission_energy_multiplier = 2.4
	_coal = _vertex_material(0.72)
	_coal.emission_enabled = true
	_coal.emission = Color("c95713")
	_coal.emission_energy_multiplier = 0.65
	_wood = ShaderMaterial.new()
	_wood.shader = WOOD_SHADER
	_grime = ShaderMaterial.new()
	_grime.shader = GRIME_SHADER
	_cold_window = _vertex_material(0.7)
	_cold_window.emission_enabled = true
	_cold_window.emission = Color("527b87")
	_cold_window.emission_energy_multiplier = 0.20
	_floor_plan()
	_walls()
	_basin()
	_boiler()
	_exit_dais()
	_storeroom()
	_small_dressing()
	_lived_in_details()
	_flush_batches()


func _process(delta: float) -> void:
	if _water != null:
		_water_time += delta
		_water.set_shader_parameter("water_time", _water_time)


func _vertex_material(roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness
	material.metallic = metallic
	return material


func _floor_plan() -> void:
	# The south rim is clipped around the actual recovery ramp. A flat slab
	# across that slot would trap the hero below an invisible vertical lip.
	_rect("FloorWest", -9, -2.7, -8, 8, 0, 0.42, _tile)
	_rect("FloorEast", 2.7, 9, -8, 8, 0, 0.42, _tile)
	_rect("FloorNorth", -2.7, 2.7, -8, -2.7, 0, 0.42, _tile)
	_rect("FloorSouthWest", -2.7, -1, 2.7, 8, 0, 0.42, _tile)
	_rect("FloorSouthEast", 1, 2.7, 2.7, 8, 0, 0.42, _tile)
	_rect("FloorSouthLanding", -1, 1, 4, 8, 0, 0.42, _tile)
	_rect("BasinSupport", -2.7, 2.7, -2.7, 2.7, -0.65, 0.3, _basin_tile)
	# The low dark plinth exposes the miniature-like thickness at the front.
	_box("SouthFoundation", Vector3(0,-0.48,7.95), Vector3(18.0,0.18,0.18), DARK, _stone)
	_box("EastFoundation", Vector3(8.95,-0.48,0), Vector3(0.18,0.18,16.0), DARK, _stone)
	var ramp := PackedVector2Array([Vector2(-1,2.3),Vector2(1,2.3),Vector2(1,4),Vector2(-1,4)])
	_prism("BasinReturnRamp", ramp, PackedFloat32Array([-0.65,-0.65,0,0]), 0.18, Color.WHITE, _tile, true)


func _walls() -> void:
	_masonry_wall("NorthWall", Vector2(-9,-8), Vector2(9,-8), 3.45, 0.58)
	_masonry_wall("WestWall", Vector2(-9,8), Vector2(-9,-8), 3.45, 0.58)
	_masonry_wall("EastFrontWall", Vector2(9,-8), Vector2(9,8), 0.35, 0.32)
	_masonry_wall("SouthFrontLeft", Vector2(-9,8), Vector2(4.8,8), 0.35, 0.32)
	_masonry_wall("SouthFrontRight", Vector2(7.2,8), Vector2(9,8), 0.35, 0.32)
	# Large buttresses and dark capitals interrupt the regular brick courses.
	for x in [-8.7,-4.5,0.0,4.1,8.7]:
		_box("NorthButtress", Vector3(x,1.65,-7.66), Vector3(0.65,3.3,0.75), TRIM, _stone, true, 0.07)
		_box("NorthCapital", Vector3(x,3.3,-7.64), Vector3(0.83,0.27,0.94), DARK, _stone)
	for z in [-3.9,0.5,5.1]:
		_box("WestButtress", Vector3(-8.64,1.62,z), Vector3(0.76,3.24,0.66), TRIM, _stone, true, 0.07)
		_box("WestCapital", Vector3(-8.62,3.27,z), Vector3(0.94,0.25,0.84), DARK, _stone)
	_banner(Vector3(-2.2,2.75,-7.58), 0.0)
	_banner(Vector3(-8.55,2.75,2.5), PI * 0.5)
	_sconce(Vector3(-4.1,1.75,-7.22))
	_sconce(Vector3(2.1,1.75,-7.22))
	_sconce(Vector3(-8.05,1.75,-1.5))


func _masonry_wall(label: String, a: Vector2, b: Vector2, height: float, width: float) -> void:
	var span := a.distance_to(b)
	var yaw := -atan2(b.y-a.y,b.x-a.x)
	var center := Vector3((a.x+b.x)*0.5,height*0.5,(a.y+b.y)*0.5)
	# Single continuous blocker; small bevels and mortar are only surface detail.
	_collision_box(label, center, Vector3(span,height,width), yaw)
	var rows := maxi(1, int(round(height/0.48)))
	var row_height := height/rows
	var count := maxi(1, int(ceil(span/1.18)))
	var module := span/count
	for row in rows:
		for column in count:
			var start := column*module
			var end := (column+1)*module
			# Alternating joint positions keep wall faces from reading as a grid.
			if row%2 == 1:
				start = maxf(0.0,start-module*0.5)
				end -= module*0.5
			var p := a.lerp(b,(start+end)*0.5/span)
			_box(label+"Brick",Vector3(p.x,row_height*(row+0.5),p.y),Vector3(end-start-0.026,row_height-0.026,width), WALL.lerp(WALL_ALT,float((row*7+column*3)%5)/6.0), _stone, false, 0.035, yaw)
		if row%2 == 1:
			var p := a.lerp(b,1.0-module*0.25/span)
			_box(label+"EndBrick",Vector3(p.x,row_height*(row+0.5),p.y),Vector3(module*0.5-0.026,row_height-0.026,width),WALL,_stone,false,0.035,yaw)
	# The cap stays within the physical height, including the low foreground.
	_box(label+"DarkTop",Vector3(center.x,height-0.055,center.z),Vector3(span,0.11,width+0.05),DARK,_stone,false,0.026,yaw)


func _basin() -> void:
	# The rim leaves genuine openings at both bridge ends and the recovery ramp.
	var rim_color := Color("303c39")
	for x in [-2.82,2.82]:
		_box("BasinRim",Vector3(x,0.10,-1.1),Vector3(0.23,0.20,3.2),rim_color,_stone,true,0.045)
		_box("BasinRim",Vector3(x,0.10,2.49),Vector3(0.23,0.20,0.38),rim_color,_stone,true,0.045)
	_box("BasinNorthRim",Vector3(0,0.10,-2.82),Vector3(5.86,0.20,0.23),rim_color,_stone,true,0.045)
	for x in [-1.96,1.96]:
		_box("BasinSouthRim",Vector3(x,0.10,2.82),Vector3(1.46,0.20,0.23),rim_color,_stone,true,0.045)
	# Solid abutments communicate that there is no headroom under the bridge.
	_rect("BridgeWest",-2.7,-0.7,0.6,2.2,0.04,0.69,_tile)
	_rect("BridgeEast",0.7,2.7,0.6,2.2,0.04,0.69,_tile)
	for x in [-0.82,0.82]:
		_box("BridgeBrokenEdge",Vector3(x,0.032,1.4),Vector3(0.16,0.016,1.56),Color("7b7965"),_stone,false,0.004)
	_water = ShaderMaterial.new()
	_water.shader = WATER_SHADER
	_rect("ShallowWater",-2.68,2.68,-2.68,2.68,-0.595,0.006,_water,false)
	# Short drains and riveted lips mark the basin's service function.
	for x in [-1.8,-1.5,-1.2,1.2,1.5,1.8]:
		_box("DrainSlot",Vector3(x,0.011,-3.08),Vector3(0.075,0.013,0.42),DARK,_metal,false,0.0)
	_candle_group(Vector3(-3.15,0,2.9),3)
	_candle_group(Vector3(3.1,0,-3.15),3)


func _boiler() -> void:
	# This authored mass closes the direct right-hand route. Its visible shell
	# and continuous blocker agree; the bridge approaches its southern side.
	_box("BoilerBlock",Vector3(6.15,1.35,-1.3),Vector3(5.7,2.7,2.8),Color("434238"),_stone,true,0.10)
	_box("BoilerDarkRoof",Vector3(6.15,2.65,-1.3),Vector3(5.68,0.14,2.78),DARK,_metal,false,0.05)
	for x in [3.62,5.16,6.70,8.24]:
		_box("FurnaceFrontPier",Vector3(x,1.32,0.16),Vector3(0.32,2.64,0.30),TRIM,_stone,true,0.04)
	for row in 5:
		for column in 9:
			var x := 3.62+float(column)*0.57
			_box("FurnaceFaceBrick",Vector3(x,0.24+float(row)*0.45,0.12),Vector3(0.53,0.42,0.12),WALL.darkened(0.16+0.025*((row+column)%3)),_stone)
	# Broad black firebox, framed by individual wedge stones.
	_box("FireboxRecess",Vector3(6.1,1.07,0.20),Vector3(2.05,1.64,0.06),Color("161f1d"),_stone,false,0.06)
	_arch(Vector3(6.1,0.18,0.28),0.89,1.03,0.31,Color("8d7855"))
	_box("CoalBed",Vector3(6.1,0.35,0.35),Vector3(1.42,0.15,0.15),Color("983f15"),_coal,false,0.03)
	for i in 7:
		var x := 5.53+float(i)*0.19
		_cylinder("FireTongue",Vector3(x,0.56+0.06*(i%3),0.36),0.0,0.09,0.35+0.09*(i%3),Color("ffb94b"),_flame,false,7)
	for i in 6:
		_box("FireGrate",Vector3(5.48+float(i)*0.25,0.70,0.43),Vector3(0.055,0.80,0.08),DARK,_metal)
	_light(Vector3(6.0,1.1,1.1),Color("ffb360"),3.6,7.5,true)
	# Copper pressure drum and black chimney are visible above the dark roof.
	_cylinder("PressureDrum",Vector3(5.25,3.36,-1.32),0.80,0.84,1.35,COPPER,_metal,true)
	_cylinder("DrumUpperRim",Vector3(5.25,4.00,-1.32),0.90,0.90,0.12,Color("a17f4d"),_metal)
	_cylinder("DrumLid",Vector3(5.25,4.085,-1.32),0.19,0.85,0.11,DARK,_metal)
	_cylinder("Chimney",Vector3(7.75,3.75,-1.55),0.41,0.47,2.12,DARK,_metal,true)
	for y in [2.86,3.55,4.62]:
		_cylinder("ChimneyBand",Vector3(7.75,y,-1.55),0.51,0.51,0.12,TRIM,_metal)
	_pipe(Vector3(5.25,3.7,-0.58),Vector3(5.25,3.7,0.14),0.13,COPPER)
	_pipe(Vector3(5.25,3.7,0.14),Vector3(5.25,2.82,0.14),0.13,COPPER)
	# Large dial, pipe collars and rivets make the landmark readable at distance.
	_cylinder("PressureDialRim",Vector3(5.25,3.30,0.18),0.28,0.28,0.09,DARK,_metal,false,24,Vector3(PI*0.5,0,0))
	_cylinder("PressureDialFace",Vector3(5.25,3.30,0.235),0.225,0.225,0.025,Color("d4c89a"),_stone,false,24,Vector3(PI*0.5,0,0))
	_box("PressureNeedle",Vector3(5.29,3.37,0.26),Vector3(0.025,0.18,0.015),Color("752f20"),_stone,false,0.0,0.0,Vector3(0,0,-0.55))
	for x in [3.65,4.8,7.35,8.50]:
		for y in [0.27,2.40]:
			_cylinder("FrontRivet",Vector3(x,y,0.22),0.055,0.055,0.05,Color("a18b63"),_metal,false,8,Vector3(PI*0.5,0,0))


func _exit_dais() -> void:
	_rect("ExitDais",4,8,-7,-3.5,0.65,0.65,_tile)
	var ramp := PackedVector2Array([Vector2(2,-6.4),Vector2(4,-6.4),Vector2(4,-4.4),Vector2(2,-4.4)])
	_prism("ExitRamp",ramp,PackedFloat32Array([0,0.65,0.65,0]),0.17,Color.WHITE,_tile,true)
	# Shallow ceremonial steps sit beside the broad functional ramp.
	for step in 4:
		var x := 2.3+float(step)*0.48
		_rect("ExitSideStep",x,x+0.48,-4.36,-3.66,0.16*(step+1),0.16*(step+1),_tile)
	_arch(Vector3(6.0,0.65,-6.82),1.02,1.65,0.39,Color("8a806a"))
	_box("ExitDoorShadow",Vector3(6.0,1.88,-7.2),Vector3(1.83,2.4,0.06),Color("252c28"),_stone)
	for i in 6:
		_box("OldDoorPlank",Vector3(5.24+float(i)*0.30,1.74,-7.15),Vector3(0.27,2.14,0.065),WOOD.darkened(float(i%3)*0.045),_wood,false,0.018)
	for y in [1.0,2.15]:
		_box("DoorStrap",Vector3(6.0,y,-7.08),Vector3(1.75,0.105,0.075),DARK,_metal)
	_box("ExitRunner",Vector3(5.93,0.662,-5.45),Vector3(2.55,0.018,1.10),Color("772d2c"),_cloth,false,0.0)
	for z in [-5.95,-4.95]:
		_box("RunnerGoldHem",Vector3(5.93,0.674,z),Vector3(2.45,0.006,0.035),Color("b69a59"),_cloth,false,0.0)
	_candle_group(Vector3(4.72,0.65,-6.33),5)
	_candle_group(Vector3(7.45,0.65,-6.35),5)
	_light(Vector3(6,2.4,-6.55),Color("ffd18b"),2.0,6.0,true)


func _storeroom() -> void:
	# All tall service props hug the far left wall, outside the 2.2 m route.
	_box("StorageBase",Vector3(-7.65,0.15,4.55),Vector3(1.8,0.30,3.0),TRIM,_stone,true,0.045)
	_crate(Vector3(-7.7,0.82,5.4),Vector3(1.3,1.04,1.15))
	_barrel(Vector3(-7.72,0.30,3.45),0.53,1.22)
	_barrel(Vector3(-7.75,0,1.12),0.50,1.13)
	_box("WorkbenchTop",Vector3(-7.85,1.10,-5.55),Vector3(1.7,0.16,2.5),WOOD,_wood,true,0.035)
	for x in [-8.42,-7.3]:
		for z in [-6.45,-4.65]:
			_box("WorkbenchLeg",Vector3(x,0.51,z),Vector3(0.17,1.02,0.17),WOOD.darkened(0.2),_wood,true,0.015)
	for i in 7:
		_cylinder("StackedFirewood",Vector3(-7.8+float(i%3)*0.27,0.12+float(i/3)*0.21,-6.8),0.13,0.13,1.3,WOOD.lightened(0.09*(i%2)),_wood,false,8,Vector3(0,0,PI*0.5))
	_candle_group(Vector3(-7.7,1.18,-5.85),4)
	_pipe(Vector3(-8.35,2.28,-6.7),Vector3(-8.35,2.28,-3.6),0.12,COPPER)
	_pipe(Vector3(-8.35,2.28,-3.6),Vector3(-8.35,0.5,-3.6),0.12,COPPER)
	_light(Vector3(-6.95,2.0,-5.5),Color("ffc37b"),1.6,6.2,false)


func _small_dressing() -> void:
	# Low props reserve the foreground for the hero and the route.
	_crate(Vector3(7.88,0.43,6.65),Vector3(0.92,0.86,0.85))
	_box("FoldedRedCloth",Vector3(7.85,0.90,6.60),Vector3(0.90,0.055,0.60),Color("7f3431"),_cloth,false,0.02)
	_candle_group(Vector3(-7.8,0,7.05),3)
	_candle_group(Vector3(8.1,0,3.3),4)
	for i in 5:
		_box("LooseFlagstone",Vector3(-4.0-0.25*(i%2),0.015,6.1+0.28*i),Vector3(0.40,0.026,0.26),Color("777964"),_stone,false,0.025,float(i)*0.41)
	# Copper drain grilles accompany, but never occupy, the central crossings.
	for z in [-6.9,5.9]:
		for x in [-1.2,-0.9,-0.6,-0.3,0.0,0.3,0.6,0.9,1.2]:
			_box("FloorDrain",Vector3(x,0.008,z),Vector3(0.045,0.010,0.50),DARK,_metal,false,0.0)


func _lived_in_details() -> void:
	# A shallow plank surface distinguishes the stores without changing the
	# collision or height of any authored path.
	for plank in 10:
		var x := -8.7+(float(plank)+0.5)*0.21
		_box("StorageFloorPlank",Vector3(x,0.012,4.9),Vector3(0.196,0.024,4.6),WOOD.darkened(0.04*float(plank%3)),_wood,false,0.013)
		for z in [2.78,7.02]:
			_cylinder("FloorNail",Vector3(x,0.029,z),0.015,0.015,0.010,DARK,_metal,false,7)
	_barrel(Vector3(-6.99,0.024,6.58),0.42,0.97)
	_sack(Vector3(-7.52,0.025,7.18),0.37,0.61)
	_sack(Vector3(-8.13,0.025,6.97),0.33,0.54)
	_barrel(Vector3(-2.98,0,-6.91),0.48,1.14)
	_barrel(Vector3(-2.10,0,-7.10),0.40,0.91)
	_sack(Vector3(-1.59,0,-6.55),0.37,0.64)
	_sack(Vector3(-3.65,0,-6.90),0.34,0.56)
	# The workbench is a place of use: copper dishes, a mug, a mallet and
	# rolled paper, all kept within the existing tabletop footprint.
	_bowl(Vector3(-8.10,1.18,-5.12),0.26)
	_bowl(Vector3(-7.63,1.18,-4.69),0.18)
	_cylinder("WorkbenchMug",Vector3(-7.36,1.29,-6.39),0.095,0.085,0.22,Color("567168"),_stone,false,14)
	_cylinder("MugInside",Vector3(-7.36,1.405,-6.39),0.071,0.071,0.005,DARK,_stone,false,14)
	_box("MalletHandle",Vector3(-7.44,1.217,-5.14),Vector3(0.53,0.056,0.065),WOOD.lightened(0.17),_wood,false,0.012,0.40)
	_box("MalletHead",Vector3(-7.66,1.245,-5.045),Vector3(0.16,0.12,0.25),TRIM,_metal,false,0.025,0.40)
	_box("UnrolledPaper",Vector3(-8.13,1.192,-6.21),Vector3(0.46,0.016,0.66),Color("b9ad83"),_cloth,false,0.0)
	for x in [-8.36,-7.90]:
		_cylinder("PaperRoll",Vector3(x,1.238,-6.21),0.050,0.050,0.67,Color("c8ba8a"),_cloth,false,12,Vector3(PI*0.5,0,0))
	for line in 5:
		_box("PaperInk",Vector3(-8.13,1.203,-6.43+float(line)*0.09),Vector3(0.23-0.025*(line%2),0.004,0.015),Color("656652"),_cloth,false,0.0)
	# One cold ventilation niche breaks the repeated warm wall bays.
	_box("VentDarkRecess",Vector3(1.1,2.09,-7.63),Vector3(1.38,1.38,0.045),Color("1a3339"),_cold_window,false,0.04)
	_arch(Vector3(1.1,1.38,-7.47),0.56,0.55,0.18,Color("515953"))
	for x in [0.67,0.89,1.11,1.33,1.55]:
		_box("VentGrille",Vector3(x,2.02,-7.39),Vector3(0.042,1.15,0.06),DARK,_metal,false,0.01)
	_box("VentCrossbar",Vector3(1.11,1.92,-7.36),Vector3(1.05,0.043,0.08),DARK,_metal)
	_box("VentShelf",Vector3(1.10,1.24,-7.17),Vector3(2.16,0.11,0.70),WOOD.darkened(0.15),_wood,false,0.026)
	for x in [0.31,1.89]:
		_box("ShelfBracket",Vector3(x,1.02,-7.24),Vector3(0.10,0.35,0.38),DARK,_metal)
	for i in 3:
		var x := 0.53+float(i)*0.29
		_cylinder("ShelfBottle",Vector3(x,1.46,-7.03),0.082,0.105,0.31,Color("37534b").lightened(0.045*i),_metal,false,12)
		_cylinder("BottleNeck",Vector3(x,1.66,-7.03),0.037,0.044,0.13,Color("486454"),_metal,false,12)
		_cylinder("BottleCork",Vector3(x,1.735,-7.03),0.039,0.039,0.05,WOOD.lightened(0.18),_wood,false,10)
	_bowl(Vector3(1.75,1.295,-7.05),0.18)
	_light(Vector3(1.08,2.08,-6.83),Color("83bdcd"),0.65,4.3,false)
	# Soft analytic patches supply contact beneath clustered props; they use
	# a shared transparent material and contain no downloaded texture.
	_contact_patch(Vector3(-7.70,0.030,4.95),Vector2(2.10,4.4),0.29)
	_contact_patch(Vector3(-7.82,0.008,-5.60),Vector2(2.55,3.20),0.32)
	_contact_patch(Vector3(-2.68,0.009,-6.83),Vector2(3.65,1.70),0.28)
	_contact_patch(Vector3(1.10,0.010,-7.02),Vector2(2.70,1.40),0.20)
	_contact_patch(Vector3(6.10,0.009,0.45),Vector2(6.10,2.25),0.24)
	_contact_patch(Vector3(7.84,0.011,6.62),Vector2(1.50,1.30),0.22)


func _sack(at: Vector3, radius: float, height: float) -> void:
	var bag := SphereMesh.new()
	bag.radius = radius
	bag.height = height
	bag.radial_segments = 14
	bag.rings = 7
	_emit("GrainSack",_color_mesh(bag,Color("777555")),Transform3D(Basis.IDENTITY,at+Vector3.UP*height*0.5),_cloth,true)
	_cylinder("SackGather",at+Vector3.UP*(height-0.01),0.10,0.13,0.14,Color("8a825e"),_cloth)
	_cylinder("SackTie",at+Vector3.UP*(height-0.035),0.12,0.12,0.031,WOOD,_wood)
	_box("SackSeam",at+Vector3(0,height*0.48,radius*0.97),Vector3(0.022,height*0.38,0.018),Color("555a43"),_cloth,false,0.004)


func _bowl(at: Vector3, radius: float) -> void:
	_cylinder("CopperBowl",at+Vector3.UP*0.055,radius,radius*0.67,0.11,COPPER.lightened(0.13),_metal,false,20)
	_cylinder("BowlInterior",at+Vector3.UP*0.112,radius*0.82,radius*0.82,0.006,COPPER.darkened(0.40),_metal,false,20)
	var rim := TorusMesh.new()
	rim.inner_radius = radius*0.82
	rim.outer_radius = radius
	rim.rings = 20
	rim.ring_segments = 6
	_emit("BowlRolledRim",_color_mesh(rim,Color("a4885b")),Transform3D(Basis.IDENTITY,at+Vector3.UP*0.11),_metal,false)


func _contact_patch(at: Vector3, size: Vector2, opacity: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	_emit("ContactGrime",_color_mesh(plane,Color(0.12,0.12,0.09,opacity)),Transform3D(Basis.IDENTITY,at),_grime,false)


func _arch(at: Vector3, radius: float, spring: float, thickness: float, color: Color) -> void:
	for side in [-1.0,1.0]:
		_box("ArchPier",at+Vector3(side*(radius+thickness*0.42),spring*0.5,0),Vector3(thickness,spring,0.46),color,_stone,true,0.045)
		_box("ArchFoot",at+Vector3(side*(radius+thickness*0.42),0.10,0),Vector3(thickness+0.15,0.20,0.60),TRIM,_stone,true,0.04)
	for i in 11:
		var angle := PI*(float(i)+0.5)/11.0
		var p := at+Vector3(cos(angle)*(radius+thickness*0.5),spring+sin(angle)*(radius+thickness*0.5),0)
		_box("ArchVoussoir",p,Vector3(thickness,0.34,0.50),color.lightened(0.025*(i%3)),_stone,true,0.025,0.0,Vector3(0,0,angle-PI*0.5))


func _barrel(at: Vector3, radius: float, height: float) -> void:
	_cylinder("BarrelLower",at+Vector3.UP*height*0.25,radius,radius*0.83,height*0.5,WOOD,_wood,true,16)
	_cylinder("BarrelUpper",at+Vector3.UP*height*0.75,radius*0.83,radius,height*0.5,WOOD.lightened(0.05),_wood,true,16)
	for y in [height*0.12,height*0.5,height*0.88]:
		var r := radius*(0.88 if y != height*0.5 else 1.025)
		_cylinder("BarrelHoop",at+Vector3.UP*y,r,r,0.075,DARK,_metal)
	_cylinder("BarrelLid",at+Vector3.UP*(height+0.005),radius*0.83,radius*0.83,0.028,WOOD.lightened(0.12),_wood)
	for x in [-0.2,0.0,0.2]:
		_box("BarrelLidJoint",at+Vector3(x,height+0.021,0),Vector3(0.016,0.009,radius*1.2),WOOD.darkened(0.35),_wood,false,0.0)


func _crate(at: Vector3, size: Vector3) -> void:
	_box("CrateBody",at,size,WOOD.darkened(0.12),_wood,true,0.045)
	for i in 4:
		var x := at.x-size.x*0.375+float(i)*size.x*0.25
		_box("CrateFrontPlank",Vector3(x,at.y,at.z+size.z*0.5+0.018),Vector3(size.x*0.25-0.028,size.y-0.05,0.035),WOOD.lightened(0.035*(i%2)),_wood)
	for y in [-0.35,0.35]:
		_box("CrateCrossbar",at+Vector3(0,size.y*y,size.z*0.5+0.055),Vector3(size.x+0.035,0.11,0.08),WOOD.lightened(0.14),_wood)
	for x in [-0.38,0.38]:
		_box("CrateTopBrace",at+Vector3(size.x*x,size.y*0.5+0.025,0),Vector3(0.10,0.05,size.z),WOOD.lightened(0.14),_wood)


func _banner(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP,yaw)
	_box("BannerRod",at,Vector3(1.0,0.075,0.10),COPPER,_metal,false,0.015,yaw)
	_box("WineRedBanner",at+basis*Vector3(0,-0.72,0.035),Vector3(0.82,1.38,0.025),Color("772e31"),_cloth,false,0.0,yaw)
	for x in [-0.34,0.34]:
		_box("BannerBorder",at+basis*Vector3(x,-0.72,0.055),Vector3(0.035,1.34,0.009),Color("a88647"),_cloth,false,0.0,yaw)
	_box("BannerDevice",at+basis*Vector3(0,-0.69,0.058),Vector3(0.18,0.40,0.012),Color("bd995d"),_cloth,false,0.018,yaw)


func _sconce(at: Vector3) -> void:
	_box("SconceBracket",at+Vector3(0,-0.12,0),Vector3(0.46,0.12,0.45),DARK,_metal)
	_candle_group(at,3,false)
	_light(at+Vector3(0,0.40,0.15),Color("ffc07b"),1.4,4.8,false)


func _candle_group(at: Vector3, count: int, add_light: bool = false) -> void:
	for i in count:
		var offset := Vector3(float(i%3)*0.14-0.14,0,float(i/3)*0.13)
		var height := 0.19+0.08*float((i*3+1)%4)
		_cylinder("CandleWax",at+offset+Vector3.UP*height*0.5,0.044,0.052,height,Color("c8ba89"),_stone,false,8)
		_cylinder("CandleFlame",at+offset+Vector3.UP*(height+0.057),0.0,0.035,0.12,Color("ffe0a0"),_flame,false,7)
	if add_light:
		_light(at+Vector3.UP*0.48,Color("ffd092"),0.8,3.2,false)


func _light(at: Vector3, color: Color, energy: float, radius: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.3
	light.shadow_enabled = shadows
	add_child(light)


func _pipe(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 16
	cylinder.rings = 1
	var transform := Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
	_emit("ServicePipe",_color_mesh(cylinder,color),transform,_metal,false)
	for p in [a,b]:
		var collar := CylinderMesh.new()
		collar.top_radius = radius*1.3
		collar.bottom_radius = radius*1.3
		collar.height = 0.11
		collar.radial_segments = 16
		_emit("PipeCollar",_color_mesh(collar,DARK),Transform3D(transform.basis,p),_metal,false)


func _cylinder(label: String, at: Vector3, top: float, bottom: float, height: float, color: Color, material: Material, collide: bool = false, segments: int = 24, rotation: Vector3 = Vector3.ZERO) -> void:
	var primitive := CylinderMesh.new()
	primitive.top_radius = top
	primitive.bottom_radius = bottom
	primitive.height = height
	primitive.radial_segments = segments
	primitive.rings = 1
	_emit(label,_color_mesh(primitive,color),Transform3D(Basis.from_euler(rotation),at),material,collide)


func _color_mesh(source: PrimitiveMesh, color: Color) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	# All batched surfaces share vertex/normal/color/UV; tangent-free stone
	# and cylinder details must not introduce different vertex formats.
	arrays[Mesh.ARRAY_TANGENT] = null
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


func _rect(label: String, x0: float, x1: float, z0: float, z1: float, y: float, depth: float, material: Material, collide: bool = true) -> void:
	var poly := PackedVector2Array([Vector2(x0,z0),Vector2(x1,z0),Vector2(x1,z1),Vector2(x0,z1)])
	_prism(label,poly,PackedFloat32Array([y,y,y,y]),depth,Color.WHITE,material,collide)


func _box(label: String, at: Vector3, size: Vector3, color: Color, material: Material, collide: bool = false, bevel: float = 0.025, yaw: float = 0.0, rotation: Vector3 = Vector3.ZERO) -> void:
	var x := size.x*0.5
	var z := size.z*0.5
	var b := minf(bevel,minf(x,z)*0.45)
	var poly := PackedVector2Array([Vector2(-x+b,-z),Vector2(x-b,-z),Vector2(x,-z+b),Vector2(x,z-b),Vector2(x-b,z),Vector2(-x+b,z),Vector2(-x,z-b),Vector2(-x,-z+b)])
	if b <= 0.0:
		poly = PackedVector2Array([Vector2(-x,-z),Vector2(x,-z),Vector2(x,z),Vector2(-x,z)])
	var heights := PackedFloat32Array()
	heights.resize(poly.size())
	heights.fill(size.y*0.5)
	var mesh := _prism_mesh(poly,heights,size.y,color)
	var angles := rotation+Vector3(0,yaw,0)
	_emit(label,mesh,Transform3D(Basis.from_euler(angles),at),material,collide)


func _prism(label: String, poly: PackedVector2Array, heights: PackedFloat32Array, depth: float, color: Color, material: Material, collide: bool) -> void:
	_emit(label,_prism_mesh(poly,heights,depth,color),Transform3D.IDENTITY,material,collide)


func _prism_mesh(poly: PackedVector2Array, heights: PackedFloat32Array, depth: float, color: Color) -> ArrayMesh:
	var triangles := Geometry2D.triangulate_polygon(poly)
	assert(not triangles.is_empty(),"Invalid authored keepers surface")
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for i in poly.size():
		top.append(Vector3(poly[i].x,heights[i],poly[i].y))
		bottom.append(top[-1]-Vector3.UP*depth)
	for i in range(0,triangles.size(),3):
		var a := triangles[i]
		var b := triangles[i+1]
		var c := triangles[i+2]
		var normal := (top[b]-top[a]).cross(top[c]-top[a]).normalized()
		if normal.y < 0.0:
			normal = -normal
		_triangle(tool,top[a],top[b],top[c],normal,color)
		_triangle(tool,bottom[a],bottom[b],bottom[c],-normal,color.darkened(0.18))
	for i in poly.size():
		var j := (i+1)%poly.size()
		var edge := poly[j]-poly[i]
		var normal := Vector3(edge.y,0,-edge.x).normalized()
		_triangle(tool,top[i],bottom[i],bottom[j],normal,color.darkened(0.08))
		_triangle(tool,top[i],bottom[j],top[j],normal,color.darkened(0.08))
	tool.index()
	return tool.commit()


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var points := [a,b,c] if (b-a).cross(c-a).dot(normal) < 0.0 else [a,c,b]
	for point: Vector3 in points:
		tool.set_normal(normal)
		tool.set_color(color)
		tool.set_uv(Vector2(point.x,point.z))
		tool.add_vertex(point)


func _emit(label: String, mesh: ArrayMesh, transform: Transform3D, material: Material, collide: bool) -> void:
	var key := material.get_instance_id()
	if not _batches.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"tool":tool,"material":material}
	(_batches[key].tool as SurfaceTool).append_from(mesh,0,transform)
	if collide:
		var body := StaticBody3D.new()
		body.name = label
		body.transform = transform
		body.collision_layer = 1
		body.collision_mask = 2
		add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)


func _collision_box(label: String, at: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


func _flush_batches() -> void:
	for entry: Dictionary in _batches.values():
		var mesh := MeshInstance3D.new()
		mesh.name = "HallBatch"
		mesh.mesh = (entry.tool as SurfaceTool).commit()
		mesh.material_override = entry.material
		if entry.material == _grime or entry.material == _water:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	_batches.clear()

extends SlimeKeepersGeometry
class_name SlimeKeepersRunGeometry

# Geometry only: combat, route gates, rewards and Russian labels belong to
# the run scene. Every theme preserves the same open, level fighting floor.
var secret_reward_marker: Node3D
var _theme := "entry"
var _floor_tone := Color("746b57")
var _wall_tone := Color("615849")
var _accent := Color("996544")
var _lamp_tone := Color("ffc47b")
var _exit_count := 0
var _corner_clip := 0.0


func build_room(room: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_batches.clear()
	_water = null
	_water_time = 0.0
	secret_reward_marker = null
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_theme = String(room.get("theme", "entry"))
	var exits: Variant = room.get("exits", [])
	_exit_count = exits.size() if exits is Array else int(exits)
	cutaway = SlimeRoomCutaway.new()
	cutaway.name = "ArchitecturalCutaway"
	add_child(cutaway)
	_run_materials()
	_run_shell()
	_floor_composition()
	match _theme:
		"entry": _entry_dressing()
		"junction": _junction_dressing()
		"furnace": _furnace_dressing()
		"cistern": _cistern_dressing()
		"hub": _hub_dressing()
		"armory": _armory_dressing()
		"garden": _garden_dressing()
		"summit": _summit_dressing()
		"spring": _spring_dressing()
		"archive": _archive_dressing()
		"cinder_gallery": _furnace_dressing()
		"pump_room": _cistern_dressing()
		"barracks": _armory_dressing()
		"root_cellar": _garden_dressing()
		"gauntlet": _summit_dressing()
	for index in mini(_exit_count, 2):
		_run_portal(get_door_position(index, _exit_count), index)
	_back_threshold()
	if String(room.get("id", "")).to_upper() in ["B", "E"] or room.has("secret_exit"):
		_secret_masonry()
	if _theme in ["spring", "archive"] or bool(room.get("secret", false)):
		_build_reward_marker()
	_flush_batches()


func get_door_position(index: int, total: int) -> Vector3:
	return Vector3((-3.7 if index == 0 else 3.7) if total >= 2 else 0.0, 0.0, -5.6)


func get_secret_position() -> Vector3:
	return Vector3(-5.5, 0.0, 1.0)


func get_back_position() -> Vector3:
	return Vector3(0.0, 0.0, 5.6)


func set_reward_visible(value: bool) -> void:
	if is_instance_valid(secret_reward_marker):
		secret_reward_marker.visible = value


func _run_materials() -> void:
	# The existing primitive toolkit is reused without constructing or changing
	# the standalone boiler hall. Materials remain local to this active room.
	var palettes := {
		"entry": ["766b57", "625746", "92623e", "ffd08c"],
		"junction": ["68736b", "555e55", "819589", "b3d6c7"],
		"furnace": ["76604e", "665247", "af633d", "ffad65"],
		"cistern": ["566b68", "4c5a56", "628e8a", "95c5d0"],
		"hub": ["786e58", "655b49", "bc9460", "ffcb84"],
		"armory": ["66665a", "56584e", "88938b", "c3d4cd"],
		"garden": ["666c50", "4c5848", "81985b", "c9d6a3"],
		"summit": ["777b73", "5b6663", "a6b4a3", "d0e5dc"],
		"spring": ["536b61", "445b51", "74b69f", "9bd8c4"],
		"archive": ["72624f", "5d5145", "b79055", "ffca86"],
		"cinder_gallery": ["746354", "594e49", "ba8157", "eeb375"],
		"pump_room": ["637779", "4a5d61", "8cafaa", "b0d5df"],
		"barracks": ["797467", "5d5953", "ad9271", "ddc8a0"],
		"root_cellar": ["716e51", "555546", "a1aa73", "c3ca92"],
		"gauntlet": ["87897c", "5c6464", "c0aa7a", "d5dfd0"]
	}
	var colors: Array = palettes.get(_theme, palettes.entry)
	_floor_tone = Color(colors[0])
	_wall_tone = Color(colors[1])
	_accent = Color(colors[2])
	_lamp_tone = Color(colors[3])
	_stone = _vertex_material(0.93)
	_metal = _vertex_material(0.48, 0.58)
	_cloth = _vertex_material(1.0)
	_tile = ShaderMaterial.new()
	_tile.shader = FLOOR_SHADER
	_tile.set_shader_parameter("tile_color", _floor_tone)
	_basin_tile = ShaderMaterial.new()
	_basin_tile.shader = FLOOR_SHADER
	_basin_tile.set_shader_parameter("tile_color", Color("48635b"))
	_wood = ShaderMaterial.new()
	_wood.shader = WOOD_SHADER
	_grime = ShaderMaterial.new()
	_grime.shader = GRIME_SHADER
	_flame = _vertex_material(0.4)
	_flame.emission_enabled = true
	_flame.emission = Color("ffb75a")
	_flame.emission_energy_multiplier = 1.7
	_coal = _vertex_material(0.7)
	_coal.emission_enabled = true
	_coal.emission = Color("b75324")
	_coal.emission_energy_multiplier = 0.65
	_cold_window = _vertex_material(0.65)
	_cold_window.emission_enabled = true
	_cold_window.emission = _accent
	_cold_window.emission_energy_multiplier = 0.55


func _run_shell() -> void:
	_corner_clip = float({"cistern": 1.6, "garden": 1.4, "summit": 1.8, "pump_room": 1.6, "root_cellar": 1.4, "gauntlet": 1.8}.get(_theme, 0.0))
	var footprint := _room_footprint()
	var heights := PackedFloat32Array()
	heights.resize(footprint.size())
	heights.fill(0.0)
	# One mesh supplies both the visible slab and its triangle collision.
	# The clipped corners are genuinely absent, including the slab's sides.
	_prism("CombatFloor", footprint, heights, 0.38, Color.WHITE, _tile, true)
	var high := 1.1 if _theme == "summit" else (2.45 if _theme in ["spring", "archive"] else 2.95)
	var end := 7.0 - _corner_clip
	_run_wall("NorthWall", Vector2(-end,-7), Vector2(end,-7), high, 0.50)
	_run_wall("WestWall", Vector2(-7,end), Vector2(-7,-end), high, 0.50)
	_run_wall("EastLowWall", Vector2(7,-end), Vector2(7,end), 0.30, 0.28)
	_run_wall("SouthLowLeft", Vector2(-end,7), Vector2(-1.2,7), 0.30, 0.28)
	_run_wall("SouthLowRight", Vector2(1.2,7), Vector2(end,7), 0.30, 0.28)
	if _corner_clip > 0.0:
		_run_wall("NorthWestCut", Vector2(-7,-end), Vector2(-end,-7), high, 0.50)
		_run_wall("NorthEastCut", Vector2(end,-7), Vector2(7,-end), high, 0.50)
		_run_wall("SouthEastCut", Vector2(7,end), Vector2(end,7), 0.30, 0.28)
		_run_wall("SouthWestCut", Vector2(-end,7), Vector2(-7,end), 0.30, 0.28)
	var outer_buttress := 6.65 if _corner_clip == 0.0 else end - 0.42
	for x in [-outer_buttress,-1.95,1.95,outer_buttress]:
		_box("BackButtress",Vector3(x,high*0.5,-6.72),Vector3(0.47,high,0.55),TRIM,_stone,true,0.045)
		_box("BackCapital",Vector3(x,high-0.07,-6.69),Vector3(0.62,0.18,0.67),DARK,_stone)
	var first_pier := -6.4 if _corner_clip == 0.0 else -end + 0.45
	for z in [first_pier,-1.9,3.7]:
		_box("WestButtress",Vector3(-6.73,high*0.5,z),Vector3(0.54,high,0.47),TRIM,_stone,true,0.045)
	for index in footprint.size():
		var a := footprint[index] * 0.92
		var b := footprint[(index + 1) % footprint.size()] * 0.92
		_floor_line("BorderMosaic", a, b, 0.10, _accent.darkened(0.25))
	var front_x := 6.15 if _corner_clip == 0.0 else 5.70
	var front_z := 5.80 if _corner_clip == 0.0 else 5.55
	_candle_group(Vector3(-front_x,0,front_z),3)
	_candle_group(Vector3(front_x,0,front_z),3)
	if _theme in ["spring", "archive"]:
		_light(Vector3(0,2.1,-0.4),_lamp_tone,1.25,5.1,false)
		_light(Vector3(-5.1,1.7,-3.8),_lamp_tone,0.72,4.0,false)
	elif _theme in ["cinder_gallery", "pump_room", "barracks", "root_cellar", "gauntlet"]:
		_extension_lighting()
	else:
		_light(Vector3(-5.1,2.2,-4.0),_lamp_tone,1.35,7.0,false)
		_light(Vector3(4.8,2.3,-4.7),Color("d4bea0"),1.05,6.2,false)


func _room_footprint() -> PackedVector2Array:
	if _corner_clip == 0.0:
		return PackedVector2Array([Vector2(-7,-7),Vector2(7,-7),Vector2(7,7),Vector2(-7,7)])
	var end := 7.0 - _corner_clip
	return PackedVector2Array([Vector2(-end,-7),Vector2(end,-7),Vector2(7,-end),Vector2(7,end),Vector2(end,7),Vector2(-end,7),Vector2(-7,end),Vector2(-7,-end)])


func _floor_composition() -> void:
	# These are shallow inlays and covered grilles, all on the unbroken slab.
	# They have no collision, steps, holes, attack effects or gameplay states.
	var quiet := _accent.darkened(0.20)
	match _theme:
		"entry":
			for plank in 9:
				var x := -1.40 + float(plank) * 0.35
				for section in 4:
					var z := -3.75 + float(section) * 2.5
					_box("EntryBoardwalk",Vector3(x,0.009,z),Vector3(0.335,0.012,2.47),WOOD.lightened(0.025*(plank%3)),_wood,false,0.008)
					for end_z in [-1.12,1.12]:
						_box("BoardwalkNail",Vector3(x,0.016,z+end_z),Vector3(0.035,0.005,0.035),TRIM,_metal,false,0.0)
			for z in [-4.85,4.80]:
				_floor_line("EntryStoneSill",Vector2(-1.75,z),Vector2(1.75,z),0.14,quiet)
		"junction":
			_mosaic_ring(Vector2(0,0.30),2.65,0.13,quiet,24)
			for x in [-3.7,3.7]:
				_floor_line("OutletGuide",Vector2(x*0.38,-1.9),Vector2(x,-4.95),0.14,quiet)
				_floor_line("OutletGuideEdge",Vector2(x*0.38+0.21,-1.9),Vector2(x+0.21,-4.95),0.035,_floor_tone.lightened(0.16))
			_flush_drain(Vector2(-2.1,2.65),Vector2(2.1,2.65),0.32)
		"furnace":
			_floor_field(PackedVector2Array([Vector2(-2.8,-4.9),Vector2(2.8,-4.9),Vector2(2.8,4.9),Vector2(-2.8,4.9)]),_floor_tone.darkened(0.08))
			for x in [-2.85,2.85]:
				_floor_line("FurnaceRail",Vector2(x,-4.85),Vector2(x,4.85),0.10,quiet)
			for z in [-3.0,0.0,3.0]:
				_flush_drain(Vector2(-2.70,z),Vector2(2.70,z),0.24)
		"cistern":
			_floor_field(PackedVector2Array([Vector2(-2.75,-4.6),Vector2(2.75,-4.6),Vector2(3.8,-3.4),Vector2(3.8,3.4),Vector2(2.75,4.6),Vector2(-2.75,4.6),Vector2(-3.8,3.4),Vector2(-3.8,-3.4)]),_floor_tone.lightened(0.06))
			for x in [-2.75,2.75]:
				_flush_drain(Vector2(x,-4.40),Vector2(x,4.40),0.30)
			for z in [-3.0,0.0,3.0]:
				_floor_line("CisternCrossCourse",Vector2(-2.5,z),Vector2(2.5,z),0.09,quiet)
		"hub":
			_mosaic_ring(Vector2.ZERO,3.20,0.22,quiet,16)
			_mosaic_ring(Vector2.ZERO,2.81,0.055,_floor_tone.lightened(0.18),16)
			for index in 8:
				var direction := Vector2.from_angle(float(index)*TAU/8.0)
				_floor_line("ClockFloorTick",direction*2.43,direction*2.69,0.13,quiet)
			for x in [-3.7,3.7]:
				_floor_line("HubGuide",Vector2(x*0.54,-2.9),Vector2(x,-4.95),0.12,quiet)
		"armory":
			_floor_field(PackedVector2Array([Vector2(-3.15,-4.4),Vector2(3.15,-4.4),Vector2(3.15,4.4),Vector2(-3.15,4.4)]),_floor_tone.lightened(0.065))
			for x in [-3.25,3.25]:
				_floor_line("ArmoryFloorFrame",Vector2(x,-4.5),Vector2(x,4.5),0.13,quiet)
			for z in [-4.5,-2.25,0.0,2.25,4.5]:
				_floor_line("ArmoryCrossBand",Vector2(-3.25,z),Vector2(3.25,z),0.105,quiet)
		"garden":
			_flush_drain(Vector2(0,-4.6),Vector2(0,4.6),0.24)
			for side in [-1.0,1.0]:
				for row in 3:
					var z := -3.05+float(row)*2.5
					var leaf := PackedVector2Array([Vector2(side*0.42,z+0.58),Vector2(side*1.50,z-0.58),Vector2(side*3.22,z-0.62),Vector2(side*2.7,z+0.30),Vector2(side*1.6,z+0.70)])
					if side < 0.0:
						leaf.reverse()
					_floor_field(leaf,_floor_tone.lerp(_accent,0.21))
					_floor_line("GardenVein",Vector2(side*0.48,z+0.50),Vector2(side*2.9,z-0.35),0.055,quiet)
		"summit":
			var octagon := PackedVector2Array()
			for index in 8:
				octagon.append(Vector2.from_angle(float(index)*TAU/8.0+PI/8.0)*3.40)
			_floor_field(octagon,_floor_tone.lightened(0.075))
			_mosaic_ring(Vector2.ZERO,3.65,0.16,quiet,8,PI/8.0)
			for index in 8:
				var direction := Vector2.from_angle(float(index)*TAU/8.0+PI/8.0)
				_floor_line("SummitRadialMark",direction*2.48,direction*3.05,0.09,quiet)
			for x in [-0.7,0.7]:
				_floor_line("SummitApproach",Vector2(x,-4.88),Vector2(x,-3.83),0.12,quiet)
		"spring":
			_floor_field(PackedVector2Array([Vector2(-1.85,-5.0),Vector2(1.85,-5.0),Vector2(1.85,4.8),Vector2(-1.85,4.8)]),_floor_tone.lightened(0.065))
			_mosaic_ring(Vector2.ZERO,1.5,0.11,quiet,20)
			_flush_drain(Vector2(-5.20,-1.1),Vector2(-2.05,-1.1),0.24)
			for x in [-2.05,2.05]:
				_floor_line("SpringServiceBorder",Vector2(x,-4.95),Vector2(x,4.8),0.10,quiet)
		"archive":
			_surface_patch("ArchiveRunner",PackedVector2Array([Vector2(-1.55,-4.9),Vector2(1.55,-4.9),Vector2(1.55,4.8),Vector2(-1.55,4.8)]),Color("62463e"),0.008,_cloth)
			for x in [-1.42,1.42]:
				_floor_line("ArchiveRunnerHem",Vector2(x,-4.78),Vector2(x,4.66),0.045,_accent)
			for z in [-4.65,4.55]:
				_floor_line("ArchiveRunnerEnd",Vector2(-1.42,z),Vector2(1.42,z),0.045,_accent)
			var diamond := PackedVector2Array([Vector2(0,-1.2),Vector2(0.85,0),Vector2(0,1.2),Vector2(-0.85,0)])
			for index in 4:
				_floor_line("ArchiveRunnerDiamond",diamond[index],diamond[(index+1)%4],0.07,_accent)
		"cinder_gallery":
			_floor_field(PackedVector2Array([Vector2(-2.85,-4.6),Vector2(2.85,-4.6),Vector2(2.85,4.6),Vector2(-2.85,4.6)]),_floor_tone.darkened(0.055))
			for column in 7:
				var x := -2.70+float(column)*0.90
				_floor_line("CopperGalleryGrid",Vector2(x,-4.45),Vector2(x,4.45),0.055,quiet)
			for row in 11:
				var z := -4.45+float(row)*0.89
				_floor_line("CopperGalleryCrossbar",Vector2(-2.70,z),Vector2(2.70,z),0.055,quiet)
			for x in [-3.05,3.05]:
				_floor_line("CopperGalleryFrame",Vector2(x,-4.7),Vector2(x,4.7),0.14,_accent.darkened(0.10))
			for z in [-4.7,4.7]:
				_floor_line("CopperGalleryEnd",Vector2(-3.05,z),Vector2(3.05,z),0.14,_accent.darkened(0.10))
		"pump_room":
			var pump_field := PackedVector2Array()
			for index in 16:
				pump_field.append(Vector2.from_angle(float(index)*TAU/16.0)*3.05)
			_floor_field(pump_field,_floor_tone.lightened(0.065))
			_mosaic_ring(Vector2.ZERO,3.20,0.16,quiet,24)
			_mosaic_ring(Vector2.ZERO,2.18,0.06,_accent.darkened(0.28),24)
			for z in [-4.15,4.15]:
				_flush_drain(Vector2(-3.8,z),Vector2(3.8,z),0.28)
			for x in [-3.75,3.75]:
				_floor_line("PumpServiceLane",Vector2(x,-3.65),Vector2(x,3.65),0.13,_floor_tone.lightened(0.20))
		"barracks":
			for side in [-1.0,1.0]:
				var x: float = side*2.05
				_floor_field(PackedVector2Array([Vector2(x-0.86,-4.4),Vector2(x+0.86,-4.4),Vector2(x+0.86,4.4),Vector2(x-0.86,4.4)]),_floor_tone.lightened(0.085))
				for edge in [-0.96,0.96]:
					_floor_line("BarracksParadeBorder",Vector2(x+edge,-4.5),Vector2(x+edge,4.5),0.095,quiet)
				for z in [-3.8,0.0,3.8]:
					_floor_line("BarracksParadeMark",Vector2(x-0.54,z),Vector2(x+0.54,z),0.14,quiet)
			for z in [-4.55,4.55]:
				_floor_line("BarracksCrossSill",Vector2(-3.5,z),Vector2(3.5,z),0.18,_accent.darkened(0.27))
		"root_cellar":
			var root_course := PackedVector2Array([Vector2(-0.95,-4.6),Vector2(0.35,-4.6),Vector2(1.08,-2.8),Vector2(0.53,-0.45),Vector2(1.10,1.4),Vector2(0.36,4.6),Vector2(-0.94,4.6),Vector2(-0.20,1.4),Vector2(-0.77,-0.45),Vector2(-0.22,-2.8)])
			_floor_field(root_course,_floor_tone.lightened(0.11))
			for index in 4:
				var side := -1.0 if index%2 == 0 else 1.0
				var z := -2.85+float(index)*1.90
				var center := Vector2(side*2.47,z)
				_mosaic_ring(center,0.79,0.085,quiet,12)
				_floor_line("RootMosaicBranch",Vector2(side*0.92,z+0.43),center,0.065,quiet)
			for z in [-4.85,4.85]:
				_flush_drain(Vector2(-3.4,z),Vector2(3.4,z),0.22)
		"gauntlet":
			var round_field := PackedVector2Array()
			for index in 24:
				round_field.append(Vector2.from_angle(float(index)*TAU/24.0)*3.76)
			_floor_field(round_field,_floor_tone.lightened(0.065))
			_mosaic_ring(Vector2.ZERO,4.10,0.18,quiet,32)
			_mosaic_ring(Vector2.ZERO,3.84,0.045,_floor_tone.lightened(0.18),32)
			for index in 12:
				var direction := Vector2.from_angle(float(index)*TAU/12.0)
				_floor_line("GauntletRoundMark",direction*3.12,direction*3.48,0.105,quiet)
			for index in 4:
				var direction := Vector2.from_angle(float(index)*PI*0.5)
				var cross := Vector2(-direction.y,direction.x)
				var petal := PackedVector2Array([direction*0.16,direction*0.85-cross*0.32,direction*1.45,direction*0.85+cross*0.32])
				_surface_patch("GauntletCompass",petal,_accent.darkened(0.15 if index%2 == 0 else 0.26),0.012,_stone)


func _extension_lighting() -> void:
	# New route rooms reuse edge furniture, while local light and inlays give
	# each one its own read. Older rooms keep their established lighting.
	match _theme:
		"cinder_gallery":
			_light(Vector3(-5.1,2.2,-4.0),_lamp_tone,1.10,6.4,false)
			_light(Vector3(4.8,2.3,-4.7),Color("cebca1"),0.88,6.0,false)
		"pump_room":
			_light(Vector3(-4.6,2.4,-4.2),_lamp_tone,1.15,7.0,false)
			_light(Vector3(5.0,2.0,3.1),Color("c7c3a5"),0.80,5.6,false)
		"barracks":
			_light(Vector3(-5.0,2.2,-3.5),_lamp_tone,1.25,6.8,false)
			_light(Vector3(4.8,2.3,-4.7),Color("bcc9cb"),0.92,6.1,false)
		"root_cellar":
			_light(Vector3(-4.6,2.1,-3.8),_lamp_tone,0.96,6.3,false)
			_light(Vector3(4.8,1.8,2.8),Color("d5bd91"),0.90,5.7,false)
		"gauntlet":
			_light(Vector3(0,2.6,-4.1),_lamp_tone,1.28,7.5,false)
			_light(Vector3(-5.0,1.9,2.8),Color("ddb98a"),0.72,4.8,false)


func _floor_field(polygon: PackedVector2Array, color: Color) -> void:
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	material.set_shader_parameter("tile_color",color)
	_surface_patch("FloorPattern",polygon,Color.WHITE,0.007,material)


func _surface_patch(label: String, polygon: PackedVector2Array, color: Color, top: float, material: Material) -> void:
	var heights := PackedFloat32Array()
	heights.resize(polygon.size())
	heights.fill(top)
	_prism(label,polygon,heights,0.004,color,material,false)


func _floor_line(label: String, a: Vector2, b: Vector2, width: float, color: Color, elevation: float = 0.010) -> void:
	var middle := (a+b)*0.5
	_box(label,Vector3(middle.x,elevation,middle.y),Vector3(a.distance_to(b),0.008,width),color,_stone,false,0.0,-atan2(b.y-a.y,b.x-a.x))


func _mosaic_ring(center: Vector2, radius: float, width: float, color: Color, segments: int, phase: float = 0.0) -> void:
	for index in segments:
		var a := phase+float(index)*TAU/float(segments)
		var b := phase+float(index+1)*TAU/float(segments)
		var polygon := PackedVector2Array([center+Vector2.from_angle(a)*radius,center+Vector2.from_angle(b)*radius,center+Vector2.from_angle(b)*(radius-width),center+Vector2.from_angle(a)*(radius-width)])
		_surface_patch("MosaicRing",polygon,color,0.012,_stone)


func _flush_drain(a: Vector2, b: Vector2, width: float) -> void:
	var direction := (b-a).normalized()
	var cross := Vector2(-direction.y,direction.x)
	_floor_line("DrainRecess",a,b,width,Color("3c4944"),0.006)
	var count := maxi(2,int(ceil(a.distance_to(b)/0.21)))
	for index in count:
		var at := a.lerp(b,(float(index)+0.5)/float(count))
		_floor_line("DrainCoverBar",at-cross*width*0.5,at+cross*width*0.5,0.06,_accent.darkened(0.24))
	for side in [-1.0,1.0]:
		_floor_line("DrainFrame",a+cross*side*width*0.5,b+cross*side*width*0.5,0.035,TRIM,0.011)


func _run_wall(label: String, a: Vector2, b: Vector2, height: float, width: float) -> void:
	var length := a.distance_to(b)
	var yaw := -atan2(b.y-a.y,b.x-a.x)
	_collision_box(label,Vector3((a.x+b.x)*0.5,height*0.5,(a.y+b.y)*0.5),Vector3(length,height,width),yaw)
	var rows := maxi(1,int(round(height/0.48)))
	var columns := maxi(1,int(ceil(length/1.05)))
	var module := length/columns
	for row in rows:
		for column in columns:
			var start := float(column)*module
			var end := float(column+1)*module
			if row%2 == 1:
				start = maxf(0.0,start-module*0.5)
				end -= module*0.5
			var p := a.lerp(b,(start+end)*0.5/length)
			_box("MasonryBrick",Vector3(p.x,height/rows*(row+0.5),p.y),Vector3(end-start-0.028,height/rows-0.024,width),_wall_tone.lightened(0.026*((row+column*3)%4)),_stone,false,0.032,yaw)
		if row%2 == 1:
			var p := a.lerp(b,1.0-module*0.25/length)
			_box("MasonryEndBrick",Vector3(p.x,height/rows*(row+0.5),p.y),Vector3(module*0.5-0.028,height/rows-0.024,width),_wall_tone,_stone,false,0.032,yaw)
	var middle := (a+b)*0.5
	_box("DarkWallCoping",Vector3(middle.x,height-0.04,middle.y),Vector3(length,0.08,width+0.025),DARK,_stone,false,0.018,yaw)


func _run_portal(at: Vector3, index: int) -> void:
	_arch(at+Vector3(0,0,-0.43),0.82,1.35,0.29,_wall_tone.lightened(0.18))
	_box("DoorNiche",at+Vector3(0,1.12,-0.92),Vector3(1.50,2.15,0.07),DARK,_stone,false,0.025)
	for plank in 5:
		_box("DoorPlank",at+Vector3(-0.60+plank*0.30,0.93,-0.86),Vector3(0.27,1.78,0.08),WOOD.darkened(0.10*(plank%2)),_wood)
	for y in [0.40,1.32]:
		_box("DoorIronBand",at+Vector3(0,y,-0.79),Vector3(1.46,0.10,0.09),TRIM,_metal)
	_box("DoorThreshold",at+Vector3(0,0.018,0),Vector3(1.65,0.028,0.70),_accent.darkened(0.22),_stone,false,0.015)
	_candle_group(at+Vector3(-1.25,0,-0.06),3)
	_light(at+Vector3(0,1.85,0.3),Color("ffc983") if index == 0 else Color("b5d2c0"),0.85,4.2,false)


func _back_threshold() -> void:
	var at := get_back_position()
	_box("ReturnThreshold",at+Vector3(0,0.014,0.35),Vector3(1.85,0.025,0.65),_accent.darkened(0.38),_stone,false,0.01)
	for side in [-1.0,1.0]:
		_box("ReturnGateFoot",at+Vector3(side*1.12,0.16,0.65),Vector3(0.32,0.32,0.38),TRIM,_stone,true,0.045)
		_candle_group(at+Vector3(side*1.12,0.32,0.65),2)
	for stripe in 3:
		_box("ReturnInlay",at+Vector3(0,0.030,0.18+stripe*0.15),Vector3(0.44+stripe*0.17,0.006,0.032),_accent,_metal,false,0.0)


func _entry_dressing() -> void:
	_side_planks(2.45,6.0)
	_crate(Vector3(-6.05,0.43,4.55),Vector3(1.10,0.86,1.05))
	_barrel(Vector3(-6.08,0,2.87),0.43,1.05)
	_sack(Vector3(-5.88,0,5.85),0.35,0.61)
	_banner(Vector3(-6.46,2.55,-3.15),PI*0.5)
	_box("ArrivalBench",Vector3(6.05,0.42,0.7),Vector3(0.70,0.18,2.65),WOOD,_wood,true,0.035)
	for z in [-0.28,1.68]:
		_box("ArrivalBenchLeg",Vector3(6.05,0.17,z),Vector3(0.53,0.34,0.12),WOOD,_wood,true,0.025)
	_contact_patch(Vector3(-6.0,0.009,4.4),Vector2(1.75,3.5),0.25)


func _junction_dressing() -> void:
	# A worn copper distributor and two differently colored outlet pipes are
	# the visual counterpart of the first choice, not an interactive machine.
	var anchor := Vector3(0.0 if _exit_count >= 2 else 5.45,0,0)
	_box("DistributorPlinth",anchor+Vector3(0,0.24,-6.28),Vector3(2.0,0.48,0.85),TRIM,_stone,true,0.07)
	_cylinder("DistributorValve",anchor+Vector3(0,1.13,-6.28),0.43,0.53,1.28,COPPER,_metal,true,20)
	_pipe(anchor+Vector3(-0.30,1.52,-6.28),anchor+Vector3(-1.31,1.52,-6.28),0.115,COPPER)
	_pipe(anchor+Vector3(0.30,1.52,-6.28),anchor+Vector3(1.31,1.52,-6.28),0.115,Color("536d61"))
	for x in [-1.28,1.28]:
		_box("ValveDirectionPlate",anchor+Vector3(x,1.53,-6.10),Vector3(0.27,0.32,0.06),_accent,_metal)
	_side_trough(Vector3(-6.05,0,-3.45),2.50)
	_banner(Vector3(-6.46,2.50,4.85),PI*0.5)


func _furnace_dressing() -> void:
	_box("SideFurnace",Vector3(-6.08,1.20,-3.00),Vector3(1.40,2.40,3.10),_wall_tone,_stone,true,0.08)
	_box("SideFurnaceRoof",Vector3(-6.08,2.36,-3.00),Vector3(1.43,0.14,3.13),DARK,_metal)
	_side_firebox(Vector3(-5.34,0,-3.00))
	for z in [-3.86,-2.04]:
		_cylinder("FurnaceFlue",Vector3(-6.10,2.89,z),0.25,0.30,1.02,DARK,_metal)
		_cylinder("FurnaceFlueRim",Vector3(-6.10,3.33,z),0.34,0.34,0.12,TRIM,_metal)
	_pipe(Vector3(-6.43,1.2,3.0),Vector3(-6.43,2.75,3.0),0.16,COPPER)
	_barrel(Vector3(6.12,0,3.95),0.44,0.91)
	_bowl(Vector3(6.0,0,5.5),0.43)
	_contact_patch(Vector3(-5.78,0.011,-3.0),Vector2(2.12,3.4),0.34)


func _cistern_dressing() -> void:
	_side_trough(Vector3(-6.0,0,-2.8),3.7)
	for z in [-4.12,-2.8,-1.48]:
		_pipe(Vector3(-6.61,2.60,z),Vector3(-6.61,1.05,z),0.09,Color("647c69"))
		_pipe(Vector3(-6.61,1.05,z),Vector3(-5.79,1.05,z),0.09,Color("647c69"))
	_box("CisternServiceShelf",Vector3(6.04,0.83,3.60),Vector3(0.78,0.13,2.35),WOOD,_wood,true,0.04)
	_bowl(Vector3(6.05,0.90,3.15),0.26)
	_bowl(Vector3(6.08,0.90,4.10),0.19)
	_light(Vector3(-5.25,1.50,-2.6),Color("7ecccc"),0.95,5.6,false)


func _hub_dressing() -> void:
	var x := 0.0 if _exit_count >= 2 else 5.55
	_box("KeeperClockBack",Vector3(x,1.76,-6.64),Vector3(1.50,2.35,0.18),WOOD.darkened(0.28),_wood)
	_cylinder("KeeperClockRing",Vector3(x,2.20,-6.48),0.64,0.64,0.12,COPPER.lightened(0.22),_metal,false,28,Vector3(PI*0.5,0,0))
	_cylinder("KeeperClockFace",Vector3(x,2.20,-6.40),0.54,0.54,0.04,Color("b6ad82"),_stone,false,28,Vector3(PI*0.5,0,0))
	_box("ClockHourHand",Vector3(x+0.11,2.31,-6.365),Vector3(0.047,0.38,0.025),DARK,_metal,false,0.0,0.0,Vector3(0,0,-0.70))
	_box("ClockMinuteHand",Vector3(x,2.40,-6.34),Vector3(0.033,0.52,0.022),DARK,_metal,false,0.0)
	_box("ClockPendulum",Vector3(x,1.17,-6.39),Vector3(0.05,0.78,0.03),COPPER,_metal)
	_cylinder("PendulumDisc",Vector3(x,0.87,-6.38),0.19,0.19,0.05,COPPER.lightened(0.2),_metal,false,18,Vector3(PI*0.5,0,0))
	_crate(Vector3(6.03,0.43,3.45),Vector3(0.98,0.86,1.12))
	_barrel(Vector3(-6.0,0,-3.75),0.46,1.2)
	_banner(Vector3(-6.46,2.65,4.7),PI*0.5)
	_contact_patch(Vector3(x,0.013,-6.3),Vector2(2.0,0.90),0.23)


func _armory_dressing() -> void:
	_box("WeaponsRackBase",Vector3(-6.12,0.19,-2.95),Vector3(1.07,0.38,3.32),WOOD.darkened(0.15),_wood,true,0.035)
	for z in [-4.38,-1.52]:
		_box("WeaponsRackPost",Vector3(-6.26,1.24,z),Vector3(0.18,2.3,0.18),WOOD,_wood,true,0.02)
	_box("WeaponsRackCrossbar",Vector3(-6.26,1.78,-2.95),Vector3(0.16,0.15,2.93),WOOD,_wood)
	for i in 5:
		var z := -4.15+float(i)*0.56
		_box("SpearHaft",Vector3(-6.02,1.22,z),Vector3(0.055,2.14,0.055),WOOD.lightened(0.14),_wood)
		_cylinder("SpearHead",Vector3(-6.02,2.41,z),0.0,0.11,0.42,Color("9aada4"),_metal,false,4)
	for z in [3.20,4.58]:
		_cylinder("RoundShield",Vector3(-6.28,1.04,z),0.47,0.47,0.13,Color("696b4b"),_metal,false,20,Vector3(0,0,PI*0.5))
		_cylinder("ShieldBoss",Vector3(-6.18,1.04,z),0.12,0.19,0.16,TRIM,_metal,false,16,Vector3(0,0,PI*0.5))
	_crate(Vector3(6.05,0.47,4.40),Vector3(0.97,0.94,1.15))
	_sack(Vector3(5.96,0,5.65),0.34,0.62)


func _garden_dressing() -> void:
	_planter(Vector3(-6.10,0,-3.05),3.15)
	_planter(Vector3(6.10,0,3.6),2.60)
	for i in 6:
		var z := -4.18+float(i)*0.48
		_leaf_cluster(Vector3(-6.22,0.85+0.12*(i%3),z),0.29+0.03*(i%2))
	for z in [-3.90,-2.72,-1.60]:
		_box("GardenTrellis",Vector3(-6.58,1.76,z),Vector3(0.075,2.42,0.06),WOOD,_wood)
	for y in [0.98,1.56,2.16]:
		_box("TrellisCrossbar",Vector3(-6.58,y,-2.75),Vector3(0.07,0.055,2.62),WOOD,_wood)
	_leaf_cluster(Vector3(-6.43,2.22,-3.63),0.42)
	_leaf_cluster(Vector3(-6.43,1.96,-2.43),0.36)
	_light(Vector3(-5.65,1.8,-2.7),Color("afcc86"),0.70,5.6,false)
	_bowl(Vector3(6.0,0,5.6),0.33)


func _summit_dressing() -> void:
	# Pillars and overhanging capitals remain inside the 1.8 m corner cut.
	for x in [-5.65,5.65]:
		_box("SummitPillar",Vector3(x,1.74,-5.55),Vector3(0.72,3.48,0.76),_wall_tone,_stone,true,0.07)
		_box("SummitCapital",Vector3(x,3.37,-5.55),Vector3(0.97,0.24,0.98),TRIM,_stone)
		_candle_group(Vector3(x,3.50,-5.55),5)
	if _exit_count == 0:
		_arch(Vector3(0,0,-6.35),1.12,1.76,0.36,Color("8a9588"))
		_box("SummitLightNiche",Vector3(0,1.62,-6.85),Vector3(1.84,3.1,0.025),Color("62867d"),_cold_window)
		_light(Vector3(0,2.28,-5.87),Color("b8dcd1"),1.15,6.8,true)
	_box("SummitFloorSeal",Vector3(0,0.011,-5.54),Vector3(1.68,0.018,0.60),_accent,_stone,false,0.015)
	_banner(Vector3(-6.39,2.85,2.7),PI*0.5)
	_candle_group(Vector3(6.0,0,2.8),5)


func _spring_dressing() -> void:
	_side_trough(Vector3(-6.00,0,-2.65),3.25)
	_planter(Vector3(6.15,0,3.2),2.50)
	_planter(Vector3(6.15,0,-3.3),3.10)
	_box("SpringRestBench",Vector3(-6.05,0.28,3.45),Vector3(1.25,0.56,3.35),_wall_tone.darkened(0.10),_stone,true,0.055)
	_bowl(Vector3(-6.05,0.57,2.5),0.31)
	_candle_group(Vector3(-6.05,0.56,4.4),3)
	_box("SpringRearShelf",Vector3(0,0.32,-6.18),Vector3(5.8,0.64,0.85),_wall_tone.darkened(0.15),_stone,true,0.045)
	for x in [-2.0,0.0,2.0]:
		_bowl(Vector3(x,0.64,-6.18),0.32)
	_pipe(Vector3(-2.4,1.60,-6.66),Vector3(2.4,1.60,-6.66),0.10,Color("637e6e"))
	for z in [-3.80,-2.80,-1.72]:
		_leaf_cluster(Vector3(-6.46,1.42,z),0.36)
	_pipe(Vector3(-6.48,2.55,-2.65),Vector3(-6.48,1.10,-2.65),0.11,Color("697f69"))
	_pipe(Vector3(-6.48,1.10,-2.65),Vector3(-5.86,1.10,-2.65),0.11,Color("697f69"))
	_light(Vector3(-5.45,1.28,-2.65),Color("8acdb4"),1.12,6.1,false)
	for x in [-0.55,0.55]:
		_candle_group(Vector3(x,0,-6.38),3)


func _archive_dressing() -> void:
	_bookcase(Vector3(-6.13,0,-2.9),3.12)
	_bookcase(Vector3(6.14,0,2.2),2.60)
	_bookcase(Vector3(-6.13,0,1.00),3.05)
	_bookcase(Vector3(6.14,0,-2.5),3.85)
	_box("ArchiveReadingTable",Vector3(0,0.89,-6.10),Vector3(3.50,0.16,0.90),WOOD,_wood,true,0.025)
	for x in [-1.45,1.45]:
		for z in [-6.40,-5.80]:
			_box("ArchiveTableLeg",Vector3(x,0.40,z),Vector3(0.13,0.80,0.13),WOOD.darkened(0.2),_wood,true,0.015)
	_box("ArchiveOpenLedger",Vector3(0,0.987,-6.06),Vector3(0.88,0.035,0.57),Color("b4a681"),_cloth,false,0.0)
	_candle_group(Vector3(-1.10,0.97,-6.05),4)
	_side_planks(3.60,6.10)
	_crate(Vector3(-6.04,0.39,4.48),Vector3(1.1,0.78,1.05))
	_box("ArchivePaper",Vector3(-6.03,0.798,4.48),Vector3(0.78,0.025,0.66),Color("b6a87c"),_cloth,false,0.0)
	for z in [4.20,4.75]:
		_cylinder("ArchiveRoll",Vector3(-6.04,0.85,z),0.062,0.062,0.8,Color("c2b087"),_cloth,false,12,Vector3(0,0,PI*0.5))
	_candle_group(Vector3(-6.0,0,5.82),5)
	_light(Vector3(-5.30,1.75,-2.8),Color("efb971"),1.03,5.5,false)


func _side_firebox(at: Vector3) -> void:
	_box("FireboxOpening",at+Vector3(0,0.95,0),Vector3(0.07,1.70,1.72),DARK,_stone)
	for side in [-1.0,1.0]:
		_box("FireboxPier",at+Vector3(0.08,0.58,side*0.91),Vector3(0.25,1.16,0.23),_accent,_stone)
	for i in 9:
		var angle := PI*(float(i)+0.5)/9.0
		_box("FireboxArchStone",at+Vector3(0.08,1.15+sin(angle)*0.87,cos(angle)*0.87),Vector3(0.27,0.28,0.31),_accent.lightened(0.04*(i%2)),_stone,false,0.02,0,Vector3(PI*0.5-angle,0,0))
	for i in 6:
		var z := -0.60+float(i)*0.24
		_cylinder("FireTongue",at+Vector3(0.08,0.55,z),0.0,0.065,0.37+0.08*(i%3),Color("ffc369"),_flame,false,7)
		_box("FireboxGrate",at+Vector3(0.18,0.69,z),Vector3(0.045,0.88,0.055),DARK,_metal)
	_light(at+Vector3(0.65,1.05,0),Color("ffad66"),1.68,6.1,true)


func _side_trough(at: Vector3, length: float) -> void:
	_box("TroughBody",at+Vector3.UP*0.30,Vector3(1.25,0.60,length),TRIM,_stone,true,0.05)
	_box("TroughInner",at+Vector3.UP*0.606,Vector3(0.96,0.015,length-0.25),Color("264b45"),_stone)
	for x in [-0.59,0.59]:
		_box("TroughLip",at+Vector3(x,0.70,0),Vector3(0.18,0.20,length+0.06),_wall_tone.darkened(0.15),_stone,true,0.03)
	for z in [-length*0.5,length*0.5]:
		_box("TroughEnd",at+Vector3(0,0.70,z),Vector3(1.29,0.20,0.17),_wall_tone.darkened(0.15),_stone,true,0.03)
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
	_rect("TroughWater",at.x-0.46,at.x+0.46,at.z-length*0.5+0.16,at.z+length*0.5-0.16,at.y+0.64,0.003,_water,false)


func _side_planks(start_z: float, end_z: float) -> void:
	for plank in 7:
		_box("EdgeFloorPlank",Vector3(-6.66+float(plank)*0.20,0.014,(start_z+end_z)*0.5),Vector3(0.19,0.026,end_z-start_z),WOOD.darkened(0.03*(plank%3)),_wood,false,0.015)


func _planter(at: Vector3, length: float) -> void:
	_box("PlanterBox",at+Vector3.UP*0.20,Vector3(1.08,0.40,length),_wall_tone.darkened(0.12),_stone,true,0.055)
	_box("PlanterSoil",at+Vector3.UP*0.41,Vector3(0.86,0.025,length-0.18),Color("3c4230"),_stone)
	for i in 5:
		var z := -length*0.38+float(i)*length*0.19
		_leaf_cluster(at+Vector3(0,0.60+0.07*(i%2),z),0.25)
	_contact_patch(at+Vector3(0,0.010,0),Vector2(1.55,length+0.55),0.21)


func _leaf_cluster(at: Vector3, radius: float) -> void:
	for i in 4:
		var leaf := SphereMesh.new()
		leaf.radius = radius*(0.82+0.09*(i%2))
		leaf.height = radius*0.95
		leaf.radial_segments = 7
		leaf.rings = 3
		var offset := Vector3(sin(float(i)*2.2)*radius*0.30,float(i%2)*radius*0.36,cos(float(i)*2.2)*radius*0.35)
		_emit("GardenLeaves",_color_mesh(leaf,Color("567449").lightened(0.07*i)),Transform3D(Basis.from_euler(Vector3(0.25*i,0.6*i,0.1)),at+offset),_stone,false)


func _bookcase(at: Vector3, length: float) -> void:
	_box("BookcaseBack",at+Vector3(0,1.17,0),Vector3(0.66,2.34,length),WOOD.darkened(0.27),_wood,true,0.03)
	var face_x := 0.38 if at.x < 0 else -0.38
	for y in [0.32,1.0,1.69,2.35]:
		_box("BookcaseShelf",at+Vector3(face_x*0.43,y,0),Vector3(0.99,0.10,length+0.10),WOOD,_wood)
	for row in 3:
		for i in 9:
			var z := -length*0.43+float(i)*length*0.106
			var color: Color = [Color("715443"),Color("55614b"),Color("735c54"),Color("877448")][(i+row*2)%4]
			var height := 0.38+0.055*((i+row)%3)
			_box("ArchiveBook",at+Vector3(face_x,row*0.69+0.38+height*0.5,z),Vector3(0.32,height,length*0.083),color,_cloth,false,0.012)
	_contact_patch(at+Vector3(0,0.01,0),Vector2(1.5,length+0.40),0.27)


func _secret_masonry() -> void:
	# No sign or visible doorway: a misplaced course, narrow crack, copper
	# condensation and a few loose stones suggest a service void in B and E.
	var z := get_secret_position().z
	for row in 3:
		for column in 3:
			_box("OddMasonry",Vector3(-6.69,0.34+row*0.44,z-0.50+column*0.50),Vector3(0.15,0.40,0.46),_wall_tone.lightened(0.015*((row+column)%2)),_stone,false,0.024,0,Vector3(0.012*(column-1),0,0))
	for i in 5:
		_box("SecretHairline",Vector3(-6.602,0.32+i*0.21,z+0.06*sin(float(i)*1.8)),Vector3(0.012,0.24,0.019),DARK,_stone,false,0.002,0,Vector3(0.15*sin(float(i)),0,0))
	for i in 3:
		_box("LooseSecretStone",Vector3(-6.24+0.12*(i%2),0.065,z+0.32+0.23*i),Vector3(0.26,0.13,0.22),_wall_tone,_stone,false,0.045,float(i)*0.46)
	_contact_patch(Vector3(-6.24,0.008,z+0.22),Vector2(1.16,1.82),0.20)


func _build_reward_marker() -> void:
	secret_reward_marker = Node3D.new()
	secret_reward_marker.name = "SecretRewardMarker"
	add_child(secret_reward_marker)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.41
	ring.rings = 32
	ring.ring_segments = 8
	_reward_piece(_color_mesh(ring,_accent.lightened(0.15)),Vector3(0,0.075,0),_metal)
	var lower := CylinderMesh.new()
	lower.top_radius = 0.20
	lower.bottom_radius = 0.0
	lower.height = 0.26
	lower.radial_segments = 6
	_reward_piece(_color_mesh(lower,_accent),Vector3(0,0.32,0),_cold_window)
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.20
	upper.height = 0.38
	upper.radial_segments = 6
	_reward_piece(_color_mesh(upper,_accent.lightened(0.26)),Vector3(0,0.64,0),_cold_window)
	var light := OmniLight3D.new()
	light.position = Vector3(0,0.72,0)
	light.light_color = _lamp_tone
	light.light_energy = 0.36
	light.omni_range = 2.6
	secret_reward_marker.add_child(light)


func _reward_piece(mesh: ArrayMesh, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	secret_reward_marker.add_child(visual)

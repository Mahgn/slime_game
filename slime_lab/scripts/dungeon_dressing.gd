extends RefCounted

# Visual-only dressing for the editable Cyclops opening. All shapes are non-colliding.

const STONE := [
	Color(0.40, 0.39, 0.35),
	Color(0.35, 0.36, 0.34),
	Color(0.45, 0.42, 0.36),
]


static func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "DungeonDressing"
	parent.add_child(root)
	var stone: Array[StandardMaterial3D] = []
	for color in STONE:
		stone.append(_material(color))
	var dark_stone := _material(Color(0.26, 0.27, 0.25))
	var edge_stone := _material(Color(0.51, 0.46, 0.38))
	var iron := _material(Color(0.11, 0.13, 0.14), 0.54)
	var wood := _material(Color(0.28, 0.17, 0.11))
	var flame := _material(Color(1.0, 0.37, 0.08), 0.1)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.29, 0.04)
	flame.emission_energy_multiplier = 3.5
	var flame_core := _material(Color(1.0, 0.83, 0.35), 0.1)
	flame_core.emission_enabled = true
	flame_core.emission = Color(1.0, 0.68, 0.20)
	flame_core.emission_energy_multiplier = 4.0

	var walls := _group(root, "StoneCourses")
	_wall_courses(walls, -5.94, -0.5, 14.5, stone)
	_wall_courses(walls, 5.94, -0.5, 14.5, stone)
	_wall_courses(walls, -6.74, -26.0, 6.5, stone)
	_wall_courses(walls, 6.74, -26.0, 6.5, stone)
	for z in [2.5, -5.5, -13.5, -21.0]:
		var wall_x := 5.78 if z > -0.5 else 6.58
		for side in [-1.0, 1.0]:
			_box(walls, "Pier", Vector3(side * wall_x, 2.65, z), Vector3(0.42, 5.3, 0.85), dark_stone)
			_box(walls, "PierCap", Vector3(side * wall_x, 5.35, z), Vector3(0.61, 0.22, 1.08), edge_stone)
	for z in [-1.3, -10.0, -18.5]:
		_box(walls, "VaultRib", Vector3(0.0, 7.4, z), Vector3(12.6, 0.45, 0.72), dark_stone)
		for x in [-4.4, 4.4]:
			_box(walls, "VaultCorbel", Vector3(x, 6.78, z), Vector3(1.5, 0.85, 0.82), edge_stone)

	var floors := _group(root, "Flagstones")
	for row in range(6):
		for column in range(5):
			var x := -4.8 + float(column) * 2.4
			var z := 1.55 + float(row) * 2.0
			if absf(x) < 1.3 and z > 3.0 and z < 7.5:
				continue
			_box(floors, "BasinSlab", Vector3(x, 0.018, z), Vector3(2.25, 0.025, 1.84), stone[(row * 3 + column) % stone.size()])
	_tile_platform(floors, "First", -2.5, -0.3, 4.2, 3.0, 0.5, 2, 2, stone, edge_stone)
	_tile_platform(floors, "Second", -4.0, -3.0, 3.6, 2.8, 1.05, 2, 2, stone, edge_stone)
	_tile_platform(floors, "Third", -1.4, -5.5, 4.0, 2.8, 1.6, 2, 2, stone, edge_stone)
	_tile_platform(floors, "Fourth", 1.2, -8.2, 4.0, 3.0, 2.15, 2, 2, stone, edge_stone)
	_tile_platform(floors, "Overlook", 1.5, -11.5, 8.0, 4.0, 2.15, 4, 2, stone, edge_stone)
	_tile_platform(floors, "UpperPath", 0.0, -17.0, 6.0, 7.0, 2.6, 3, 3, stone, edge_stone)
	_tile_platform(floors, "ExitLanding", 0.0, -21.0, 8.0, 3.0, 2.6, 4, 2, stone, edge_stone)
	var upper_floors := _group(root, "UpperFlagstones")
	var upper_platforms := [
		["Gallery", 0.0, -30.0, 10.0, 12.0, 2.6, 5, 6],
		["Observation", 0.0, -40.0, 10.0, 8.0, 3.2, 5, 4],
		["EastWalk", 5.5, -40.0, 11.0, 4.0, 3.2, 5, 2],
		["HelmetNest", 16.0, -40.0, 14.0, 12.0, 3.2, 7, 6],
		["ApproachStep", 22.3, -35.0, 4.5, 4.5, 4.0, 2, 2],
		["CombatShelf", 28.0, -29.0, 12.0, 10.0, 4.8, 6, 5],
		["JumpShelf", 28.0, -19.0, 10.0, 6.0, 5.6, 5, 3],
		["UpperLedge", 27.0, -9.0, 12.0, 12.0, 6.2, 6, 6],
		["ReturnOverlook", 14.0, -2.0, 14.0, 8.0, 6.8, 7, 4],
		["Fork", 3.0, -8.0, 12.0, 6.0, 7.4, 6, 3],
		["LongWay", -3.5, -16.0, 3.5, 10.0, 7.4, 2, 5],
		["ShortStepA", 6.0, -14.0, 3.5, 3.5, 7.4, 2, 2],
		["ShortStepB", 6.0, -19.5, 3.5, 3.5, 7.4, 2, 2],
		["Merge", 0.0, -24.0, 12.0, 6.0, 7.4, 6, 3],
		["FinalArena", 0.0, -33.0, 12.0, 10.0, 7.4, 6, 5],
		["Exit", 0.0, -47.0, 10.0, 6.0, 7.4, 5, 3],
	]
	for data in upper_platforms:
		_tile_platform(upper_floors, data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7], stone, edge_stone)
	var exam_ruins := _group(root, "ExamRuins")
	for marker in [Vector3(-4.4, 3.25, -27), Vector3(4.4, 3.85, -41), Vector3(10.4, 3.85, -44), Vector3(33.0, 5.45, -27), Vector3(19.0, 6.85, -7), Vector3(-5.1, 8.05, -33)]:
		_box(exam_ruins, "BrokenExamPillar", marker, Vector3(0.55, 1.25, 0.55), dark_stone)
		_box(exam_ruins, "BrokenExamPillarCap", marker + Vector3(0, 0.68, 0), Vector3(0.78, 0.16, 0.78), edge_stone)

	var fixtures := _group(root, "TorchesAndIron")
	_torch(fixtures, -5.9, 4.5, -1.0, iron, flame, flame_core)
	_torch(fixtures, 5.9, 0.0, 1.0, iron, flame, flame_core)
	_torch(fixtures, -6.7, -7.0, -1.0, iron, flame, flame_core)
	_torch(fixtures, 6.7, -17.0, 1.0, iron, flame, flame_core)
	for z in [4.8, 7.0, 9.2]:
		_box(fixtures, "BrokenGrateLeft", Vector3(-1.86, 9.07, z), Vector3(1.22, 0.09, 0.11), iron)
		_box(fixtures, "BrokenGrateRight", Vector3(1.86, 9.07, z), Vector3(1.22, 0.09, 0.11), iron)
	for record in [[-5.48, 1.0], [5.48, 7.5], [-6.2, -12.0]]:
		_box(fixtures, "HangingChain", Vector3(record[0], 6.45, record[1]), Vector3(0.055, 2.9, 0.055), iron)
		_box(fixtures, "ChainWeight", Vector3(record[0], 4.88, record[1]), Vector3(0.3, 0.24, 0.26), iron)

	var exit_arch := _group(root, "ExitArch")
	for x in [-3.68, 3.68]:
		_box(exit_arch, "ArchPier", Vector3(x, 4.8, -22.76), Vector3(0.68, 4.4, 0.76), dark_stone)
		_box(exit_arch, "ArchCapital", Vector3(x, 6.82, -22.76), Vector3(0.92, 0.35, 0.95), edge_stone)
	_box(exit_arch, "ArchLintel", Vector3(0.0, 7.16, -22.76), Vector3(8.15, 0.6, 0.9), dark_stone)
	_box(exit_arch, "RouteNotice", Vector3(0.0, 6.05, -22.72), Vector3(4.4, 0.94, 0.15), wood)
	var notice := Label3D.new()
	notice.name = "RouteNoticeText"
	notice.text = "ДАЛЬШЕ ПО ПРОГРАММЕ"
	notice.font_size = 56
	notice.pixel_size = 0.006
	notice.modulate = Color(0.98, 0.87, 0.63)
	notice.position = Vector3(0.0, 6.03, -22.6)
	exit_arch.add_child(notice)


static func _group(parent: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node


static func _wall_courses(parent: Node3D, x: float, z_min: float, z_max: float, stone: Array[StandardMaterial3D]) -> void:
	for row in range(7):
		for column in range(int((z_max - z_min) / 2.55)):
			var offset := 1.25 if row % 2 == 1 else 0.0
			var z := z_min + 1.3 + float(column) * 2.55 + offset
			if z > z_max - 0.9:
				continue
			_box(parent, "WallStone", Vector3(x, 0.54 + float(row) * 0.77, z), Vector3(0.09, 0.67, 2.35), stone[(row + column * 2) % stone.size()])


static func _tile_platform(parent: Node3D, prefix: String, x: float, z: float, width: float, depth: float, top: float, columns: int, rows: int, stone: Array[StandardMaterial3D], edge: StandardMaterial3D) -> void:
	var tile_width := width / float(columns)
	var tile_depth := depth / float(rows)
	for row in range(rows):
		for column in range(columns):
			var tile_x := x - width * 0.5 + (float(column) + 0.5) * tile_width
			var tile_z := z - depth * 0.5 + (float(row) + 0.5) * tile_depth
			_box(parent, prefix + "Flag", Vector3(tile_x, top + 0.015, tile_z), Vector3(tile_width - 0.09, 0.025, tile_depth - 0.09), stone[(column + row * 2) % stone.size()])
	_box(parent, prefix + "FrontRim", Vector3(x, top - 0.025, z + depth * 0.5 + 0.015), Vector3(width, 0.10, 0.08), edge)


static func _torch(parent: Node3D, wall_x: float, z: float, side: float, iron: StandardMaterial3D, flame: StandardMaterial3D, core: StandardMaterial3D) -> void:
	var inset := -side
	_box(parent, "TorchPlate", Vector3(wall_x + inset * 0.05, 2.45, z), Vector3(0.15, 0.55, 0.48), iron)
	_box(parent, "TorchArm", Vector3(wall_x + inset * 0.32, 2.38, z), Vector3(0.55, 0.11, 0.11), iron)
	_box(parent, "TorchCup", Vector3(wall_x + inset * 0.63, 2.43, z), Vector3(0.30, 0.22, 0.30), iron)
	var glow := MeshInstance3D.new()
	glow.name = "TorchFlame"
	var outer := CylinderMesh.new()
	outer.top_radius = 0.015
	outer.bottom_radius = 0.20
	outer.height = 0.48
	glow.mesh = outer
	glow.material_override = flame
	glow.position = Vector3(wall_x + inset * 0.63, 2.74, z)
	parent.add_child(glow)
	var spark := MeshInstance3D.new()
	spark.name = "TorchCore"
	var inner := CylinderMesh.new()
	inner.top_radius = 0.01
	inner.bottom_radius = 0.085
	inner.height = 0.28
	spark.mesh = inner
	spark.material_override = core
	spark.position = glow.position + Vector3(0.0, 0.025, 0.0)
	parent.add_child(spark)
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.position = glow.position + Vector3(0.0, 0.1, 0.0)
	light.light_color = Color(1.0, 0.55, 0.27)
	light.light_energy = 2.5
	light.omni_range = 7.5
	parent.add_child(light)


static func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)


static func _material(color: Color, roughness: float = 0.92) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

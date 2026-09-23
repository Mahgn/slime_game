extends Node3D


func _ready() -> void:
	_build_space()
	_build_visuals()
	_build_light()


func _build_space() -> void:
	_add_block("Floor", Vector3(0.0, -0.2, 0.0), Vector3(14.0, 0.4, 20.0), Color(0.25, 0.31, 0.35))
	_add_block("WestWall", Vector3(-7.2, 1.6, 0.0), Vector3(0.4, 3.2, 20.4), Color(0.27, 0.34, 0.38))
	_add_block("EastWall", Vector3(7.2, 1.6, 0.0), Vector3(0.4, 3.2, 20.4), Color(0.27, 0.34, 0.38))
	_add_block("NorthWall", Vector3(0.0, 1.6, -10.2), Vector3(14.4, 3.2, 0.4), Color(0.27, 0.34, 0.38))
	_add_block("SouthWall", Vector3(0.0, 1.6, 10.2), Vector3(14.4, 3.2, 0.4), Color(0.27, 0.34, 0.38))
	_add_block("Column", Vector3(3.8, 1.4, 1.5), Vector3(1.0, 2.8, 1.0), Color(0.42, 0.47, 0.48))
	_add_block("CornerWall", Vector3(-4.2, 1.2, -2.0), Vector3(0.8, 2.4, 3.0), Color(0.38, 0.44, 0.46))
	_add_block("Ramp", Vector3(-4.6, 0.48, 4.1), Vector3(2.4, 0.24, 3.0), Color(0.44, 0.49, 0.47), -18.0)
	_add_block("Platform", Vector3(-4.6, 0.98, 1.6), Vector3(2.8, 0.3, 2.1), Color(0.46, 0.50, 0.48))
	_add_block("StepMarker", Vector3(0.0, 0.015, -2.8), Vector3(2.0, 0.03, 0.18), Color(0.83, 0.67, 0.31), 0.0, false)


func _add_block(block_name: String, center: Vector3, size: Vector3, tint: Color, angle_x: float = 0.0, solid: bool = true) -> void:
	var block: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		block = body
	else:
		block = Node3D.new()
	block.name = block_name
	block.position = center
	block.rotation_degrees.x = angle_x
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.93
	mesh.material_override = material
	block.add_child(mesh)
	add_child(block)


func _build_visuals() -> void:
	# Decoration has no collision. The existing solid blocks still own the room shape.
	var decor := Node3D.new()
	decor.name = "HallVisuals"
	add_child(decor)
	var stone_a := _stone(Color(0.34, 0.40, 0.43))
	var stone_b := _stone(Color(0.37, 0.43, 0.45))
	var stone_c := _stone(Color(0.40, 0.45, 0.46))
	var trim := _stone(Color(0.21, 0.29, 0.32))
	var edge := _stone(Color(0.53, 0.56, 0.53))

	# One repeated stone module ties the floor and walls together. Floor tile tops
	# sit only two centimeters above the existing collision floor.
	for row in range(10):
		for column in range(7):
			var tile_material: Material = stone_a
			if (row + column * 2) % 5 == 0:
				tile_material = stone_c
			elif (row + column) % 3 == 0:
				tile_material = stone_b
			_add_visual_box(decor, "FloorStone_%02d_%02d" % [row, column], Vector3(-6.0 + column * 2.0, 0.0075, -9.0 + row * 2.0), Vector3(1.94, 0.025, 1.94), tile_material)

	for section in range(7):
		var x := -6.0 + section * 2.0
		var face_material: Material = stone_b if section % 3 == 0 else stone_a
		_add_visual_box(decor, "NorthPanel_%02d" % section, Vector3(x, 1.55, -9.973), Vector3(1.84, 2.42, 0.035), face_material)
		_add_visual_box(decor, "SouthPanel_%02d" % section, Vector3(x, 1.55, 9.973), Vector3(1.84, 2.42, 0.035), face_material)
	for section in range(10):
		var z := -9.0 + section * 2.0
		var face_material: Material = stone_b if section % 3 == 1 else stone_a
		_add_visual_box(decor, "WestPanel_%02d" % section, Vector3(-6.973, 1.55, z), Vector3(0.035, 2.42, 1.84), face_material)
		_add_visual_box(decor, "EastPanel_%02d" % section, Vector3(6.973, 1.55, z), Vector3(0.035, 2.42, 1.84), face_material)

	for z in [-9.91, 9.91]:
		_add_visual_box(decor, "WallLowerZ_%s" % str(z), Vector3(0.0, 0.26, z), Vector3(13.95, 0.12, 0.08), trim)
		_add_visual_box(decor, "WallUpperZ_%s" % str(z), Vector3(0.0, 2.84, z), Vector3(13.95, 0.11, 0.08), edge)
	for x in [-6.91, 6.91]:
		_add_visual_box(decor, "WallLowerX_%s" % str(x), Vector3(x, 0.26, 0.0), Vector3(0.08, 0.12, 19.9), trim)
		_add_visual_box(decor, "WallUpperX_%s" % str(x), Vector3(x, 2.84, 0.0), Vector3(0.08, 0.11, 19.9), edge)

	for height in [0.33, 2.43]:
		_add_visual_box(decor, "ColumnBand_%s" % str(height), Vector3(3.8, height, 1.5), Vector3(1.015, 0.08, 1.015), trim)
	_add_visual_box(decor, "ColumnFace", Vector3(3.8, 1.38, 2.003), Vector3(0.31, 1.75, 0.012), stone_c)
	_add_visual_box(decor, "CornerFace", Vector3(-3.793, 1.2, -2.0), Vector3(0.012, 1.9, 2.72), stone_b)

	# Flush edging follows the existing ramp and platform without new ledges.
	var ramp := get_node("Ramp") as Node3D
	for side in [-1.0, 1.0]:
		_add_visual_box(ramp, "RampEdge_%s" % str(side), Vector3(side * 1.05, 0.127, 0.0), Vector3(0.10, 0.012, 2.75), trim)
	var platform := get_node("Platform") as Node3D
	for side in [-1.0, 1.0]:
		_add_visual_box(platform, "PlatformEdge_%s" % str(side), Vector3(side * 1.23, 0.155, 0.0), Vector3(0.10, 0.012, 2.03), trim)

	_add_visual_box(decor, "MarkerSurround", Vector3(0.0, 0.018, -2.8), Vector3(2.16, 0.012, 0.34), trim)
	_add_visual_box(decor, "MarkerCore", Vector3(0.0, 0.034, -2.8), Vector3(1.72, 0.010, 0.08), _stone(Color(1.0, 0.81, 0.42), true))
	_add_lamp(decor, Vector3(0.0, 2.52, -9.88), edge)
	_add_lamp(decor, Vector3(3.8, 2.19, 2.02), edge)


func _stone(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.84
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.65
	return material


func _add_visual_box(parent: Node3D, piece_name: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = piece_name
	piece.position = center
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = material
	parent.add_child(piece)
	return piece


func _add_lamp(parent: Node3D, at: Vector3, casing: Material) -> void:
	_add_visual_box(parent, "LampCasing", at, Vector3(0.62, 0.46, 0.12), casing)
	var lamp := _add_visual_box(parent, "LampGlow", at + Vector3(0.0, 0.0, 0.07), Vector3(0.32, 0.25, 0.065), _stone(Color(0.95, 0.65, 0.37), true))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.10, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.63, 0.68)
	environment.ambient_light_energy = 0.68
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -26.0, 0.0)
	sun.light_color = Color(1.0, 0.91, 0.80)
	sun.light_energy = 1.10
	sun.shadow_enabled = true
	add_child(sun)
	_add_omni_light(Vector3(2.6, 2.48, 1.1), Color(1.0, 0.71, 0.48), 0.75, 7.0)
	_add_omni_light(Vector3(0.0, 2.65, -8.35), Color(0.91, 0.74, 0.57), 0.65, 6.5)


func _add_omni_light(at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	add_child(light)

extends "res://scripts/levels/combat_lab.gd"


func _build_space() -> void:
	_add_block("Floor", Vector3(0.0, -0.2, 0.0), Vector3(16.0, 0.4, 16.0), Color(0.23, 0.29, 0.32))
	_add_block("WestWall", Vector3(-8.2, 1.6, 0.0), Vector3(0.4, 3.2, 16.4), Color(0.29, 0.35, 0.36))
	_add_block("EastWall", Vector3(8.2, 1.6, 0.0), Vector3(0.4, 3.2, 16.4), Color(0.29, 0.35, 0.36))
	_add_block("NorthWall", Vector3(0.0, 1.6, -8.2), Vector3(16.4, 3.2, 0.4), Color(0.29, 0.35, 0.36))
	_add_block("SouthWall", Vector3(0.0, 1.6, 8.2), Vector3(16.4, 3.2, 0.4), Color(0.29, 0.35, 0.36))
	_add_block("WestSupport", Vector3(-2.8, 1.55, -0.4), Vector3(1.5, 3.1, 1.5), Color(0.42, 0.46, 0.43))
	_add_block("EastSupport", Vector3(2.8, 1.55, -0.4), Vector3(1.5, 3.1, 1.5), Color(0.42, 0.46, 0.43))


func _build_visuals() -> void:
	var decor := Node3D.new()
	decor.name = "MixedHallVisuals"
	add_child(decor)
	var floor_a := _stone(Color(0.29, 0.36, 0.37))
	var floor_b := _stone(Color(0.32, 0.39, 0.39))
	var edge := _stone(Color(0.55, 0.59, 0.53))
	var glow := _stone(Color(0.91, 0.72, 0.39), true)
	for row in range(8):
		for column in range(8):
			var material: Material = floor_b if (row + column) % 3 == 0 else floor_a
			_add_visual_box(decor, "FloorStone_%02d_%02d" % [row, column], Vector3(-7.0 + column * 2.0, 0.008, -7.0 + row * 2.0), Vector3(1.94, 0.025, 1.94), material)
	for side in [-2.8, 2.8]:
		for height in [0.25, 2.9]:
			_add_visual_box(decor, "SupportBand", Vector3(side, height, -0.4), Vector3(1.53, 0.09, 1.53), edge)
		_add_visual_box(decor, "SupportLight", Vector3(side, 1.75, 0.36), Vector3(0.56, 0.18, 0.025), glow)
	for side in [-7.94, 7.94]:
		_add_visual_box(decor, "WallLine", Vector3(side, 1.9, 0.0), Vector3(0.035, 0.09, 15.6), edge)
	for depth in [-7.94, 7.94]:
		_add_visual_box(decor, "WallLine", Vector3(0.0, 1.9, depth), Vector3(15.6, 0.09, 0.035), edge)
	_add_visual_box(decor, "FarLight", Vector3(0.0, 2.7, -7.92), Vector3(3.2, 0.38, 0.05), glow)


func _build_light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.11, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.63, 0.60)
	environment.ambient_light_energy = 0.76
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -19.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.79)
	sun.light_energy = 1.07
	sun.shadow_enabled = true
	add_child(sun)
	_add_omni_light(Vector3(-2.8, 2.4, -0.4), Color(1.0, 0.77, 0.47), 0.65, 6.2)
	_add_omni_light(Vector3(2.8, 2.4, -0.4), Color(1.0, 0.77, 0.47), 0.65, 6.2)

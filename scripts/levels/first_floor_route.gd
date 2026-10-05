extends RefCounted

# Runtime landmarks for the baked colleague route; floor collisions live in first_floor_blockout.tscn.

const ZONES := [
	["R02", "ГАЛЕРЕЯ НАХОДОК", Vector3(0, 3.7, -30), Vector3(9, 3, 10)],
	["K1", "ПЕРВАЯ ОТМЕТКА", Vector3(0, 3.7, -35), Vector3(9, 3, 2)],
	["R03", "БАЛКОН НАБЛЮДЕНИЯ", Vector3(0, 4.2, -40), Vector3(9, 3, 7)],
	["R04", "ГНЕЗДО ШЛЕМОВ", Vector3(16, 4.2, -40), Vector3(13, 3, 11)],
	["R05", "ПРОХОД ПЛЕВКА", Vector3(28, 6, -29), Vector3(11, 3, 9)],
	["R06", "ВЕРХНИЙ КАРНИЗ", Vector3(27, 7.3, -9), Vector3(11, 3, 11)],
	["R07", "СМОТРОВАЯ ПЛОЩАДКА", Vector3(14, 8.1, -2), Vector3(13, 3, 7)],
	["R08", "ДВА ОБХОДА", Vector3(3, 8.7, -8), Vector3(11, 3, 5)],
	["K4", "ПЕРЕД ВЫХОДОМ", Vector3(0, 8.7, -24), Vector3(11, 3, 5)],
	["R09", "ВЫХОДНОЙ ПРОЛЁТ", Vector3(0, 8.7, -33), Vector3(11, 3, 9)],
	["EXIT", "ЭТАЖ 2", Vector3(0, 8.7, -47), Vector3(9, 3, 5)],
]


static func build(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "FirstFloorRoute"
	parent.add_child(root)
	var stone := _material(Color(0.48, 0.45, 0.38))
	var iron := _material(Color(0.13, 0.16, 0.17))
	var wood := _material(Color(0.30, 0.18, 0.10))
	var helmet := _material(Color(0.44, 0.47, 0.45))
	var mint := _material(Color(0.26, 0.83, 0.68), true)
	var gold := _material(Color(0.95, 0.69, 0.31), true)
	var areas: Array[Area3D] = []
	for record in ZONES:
		var area := Area3D.new()
		area.name = "Zone" + record[0]
		area.collision_layer = 0
		area.collision_mask = 2
		area.set_meta("zone_code", record[0])
		root.add_child(area)
		area.position = record[2]
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = record[3]
		collision.shape = box
		area.add_child(collision)
		areas.append(area)

	_sign(root, "R02 · НАХОДКИ", Vector3(0, 5.0, -25.5), wood)
	_sign(root, "R03 · СНАЧАЛА СМОТРИ", Vector3(0, 5.7, -37.0), wood)
	_sign(root, "R04 · ШЛЕМЫ НЕ ВОЗВРАЩАТЬ", Vector3(16, 5.7, -44.0), wood)
	_sign(root, "R05 · НЕ ПЛЕВАТЬ В КАНЦЕЛЯРИЮ", Vector3(28, 7.3, -33.8), wood)
	_sign(root, "R08 · ОБХОД ОБХОДА", Vector3(3, 9.8, -10.7), wood)
	for at in [Vector3(-3.5, 3.3, -35), Vector3(18, 3.9, -36), Vector3(11, 7.5, -1), Vector3(0, 8.1, -25)]:
		_checkpoint(root, at, mint)
	for at in [Vector3(3.6, 4.1, -30), Vector3(18, 4.2, -40), Vector3(30, 6.0, -18), Vector3(26, 7.0, -8), Vector3(1, 8.2, -32)]:
		_torch(root, at, iron, gold)
	for index in range(6):
		var x := 12.0 + float(index % 3) * 1.5
		var z := -42.5 + float(index / 3) * 1.3
		_box(root, "DiscardedHelmet", Vector3(x, 3.36, z), Vector3(0.9, 0.35, 0.8), helmet)
	_box(root, "LostPropertyCrate", Vector3(-3.2, 3.15, -31), Vector3(1.4, 1.1, 1.1), wood)
	_box(root, "LostPropertyLid", Vector3(-3.2, 3.74, -31), Vector3(1.55, 0.12, 1.25), iron)
	var core := _box(root, "AncientSlimeCore", Vector3(19.0, 4.25, -41.0), Vector3(0.7, 0.7, 0.7), mint)
	var low_passage := Area3D.new()
	low_passage.name = "R08LowPassage"
	low_passage.position = Vector3(-3.5, 7.4, -16.0)
	low_passage.collision_layer = 0
	low_passage.collision_mask = 2
	root.add_child(low_passage)
	var passage_collision := CollisionShape3D.new()
	var passage_box := BoxShape3D.new()
	passage_box.size = Vector3(2.24, 1.16, 6.0)
	passage_collision.shape = passage_box
	passage_collision.position.y = 0.3
	low_passage.add_child(passage_collision)
	_solid_box(low_passage, "LowRoof", Vector3(0, 0.75, 0), Vector3(2.8, 0.30, 3.6), stone)
	_solid_box(low_passage, "LowWestWall", Vector3(-1.50, 0.70, 0), Vector3(0.20, 1.40, 3.6), stone)
	_solid_box(low_passage, "LowEastWall", Vector3(1.50, 0.70, 0), Vector3(0.20, 1.40, 3.6), stone)
	_side_notice(root, "НИЗКИЙ ПРОХОД", Vector3(-6.6, 8.75, -13.0), wood)

	var bridge := StaticBody3D.new()
	bridge.name = "R09Bridge"
	bridge.position = Vector3(0, 7.15, -41)
	root.add_child(bridge)
	var bridge_shape := CollisionShape3D.new()
	var bridge_box := BoxShape3D.new()
	bridge_box.size = Vector3(4, 0.5, 7)
	bridge_shape.shape = bridge_box
	bridge_shape.disabled = true
	bridge.add_child(bridge_shape)
	var bridge_mesh := MeshInstance3D.new()
	var bridge_visual := BoxMesh.new()
	bridge_visual.size = bridge_box.size
	bridge_mesh.mesh = bridge_visual
	bridge_mesh.material_override = wood
	bridge_mesh.visible = false
	bridge.add_child(bridge_mesh)
	var rope := _box(root, "ReleaseRope", Vector3(0, 10.1, -37.5), Vector3(0.12, 3.6, 0.12), iron)
	_box(root, "RopeHandle", Vector3(0, 8.45, -37.5), Vector3(0.55, 0.25, 0.3), gold)
	_sign(root, "УДАРИТЬ ПО КАНАТУ", Vector3(0, 10.7, -36.8), wood)
	for x in [-4.2, 4.2]:
		_box(root, "FloorExitPier", Vector3(x, 9.35, -49), Vector3(0.7, 4.0, 0.8), stone)
	_box(root, "FloorExitLintel", Vector3(0, 11.5, -49), Vector3(9.0, 0.7, 0.9), stone)
	_sign(root, "ЭТАЖ 2 · ХОЗЯЙСТВЕННЫЙ", Vector3(0, 10.8, -48.5), wood)
	return {"core": core, "areas": areas, "bridge": bridge, "bridge_shape": bridge_shape, "bridge_mesh": bridge_mesh, "rope": rope, "low_passage": low_passage}


static func _sign(parent: Node3D, value: String, at: Vector3, wood: StandardMaterial3D) -> void:
	_box(parent, "NoticeBoard", at, Vector3(5.2, 0.7, 0.12), wood)
	var label := Label3D.new()
	label.name = "NoticeText"
	label.text = value
	label.font_size = 48
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.9, 0.68)
	label.position = at + Vector3(0, 0, 0.07)
	parent.add_child(label)


static func _checkpoint(parent: Node3D, at: Vector3, mint: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "CheckpointGlow"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.75
	cylinder.bottom_radius = 0.75
	cylinder.height = 0.04
	mesh.mesh = cylinder
	mesh.material_override = mint
	mesh.position = at
	parent.add_child(mesh)


static func _side_notice(parent: Node3D, value: String, at: Vector3, wood: StandardMaterial3D) -> void:
	_box(parent, "SideNotice", at, Vector3(2.5, 0.55, 0.12), wood)
	var label := Label3D.new()
	label.name = "SideNoticeText"
	label.text = value
	label.font_size = 42
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.9, 0.68)
	label.position = at + Vector3(0, 0, 0.07)
	parent.add_child(label)


static func _torch(parent: Node3D, at: Vector3, iron: StandardMaterial3D, flame: StandardMaterial3D) -> void:
	_box(parent, "BrazierCup", at, Vector3(0.75, 0.24, 0.75), iron)
	var fire := MeshInstance3D.new()
	fire.name = "BrazierFlame"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.30
	cone.height = 0.65
	fire.mesh = cone
	fire.material_override = flame
	fire.position = at + Vector3(0, 0.45, 0)
	parent.add_child(fire)
	var light := OmniLight3D.new()
	light.position = fire.position
	light.light_color = Color(1.0, 0.59, 0.31)
	light.light_energy = 2.0
	light.omni_range = 10.0
	parent.add_child(light)


static func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _solid_box(parent: Node3D, name: String, at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.name = "Stone"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	parent.add_child(body)


static func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.86
	if emission:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 1.7
	return result

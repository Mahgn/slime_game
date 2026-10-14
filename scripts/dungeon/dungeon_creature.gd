extends SlimeKeepersWorldSpitter

var _creature_art: Node3D
var _legs: Array[Node3D] = []
var _crawl_time: float = 0.0


func _ready() -> void:
	super._ready()
	model.hide()
	muzzle.position = Vector3(0.0, 0.7, -0.55)
	_creature_art = Node3D.new()
	_creature_art.name = "DungeonCreature"
	get_node("VisualRoot").add_child(_creature_art)
	var acid: bool = drop_ability_id == &"acid_spit"
	var shell: StandardMaterial3D = _material(Color("7c9149") if acid else Color("756479"))
	var legs: StandardMaterial3D = _material(Color("323c39"))
	var eyes: StandardMaterial3D = _material(Color("e2c889"))
	_ellipsoid(_creature_art, Vector3(0, 0.62, 0.1), Vector3(0.57, 0.46, 0.65) if acid else Vector3(0.5, 0.4, 0.57), shell)
	_ellipsoid(_creature_art, Vector3(0, 0.54, -0.42), Vector3(0.34, 0.3, 0.33), shell)
	for side: int in [-1, 1]:
		_ellipsoid(_creature_art, Vector3(float(side) * 0.16, 0.64, -0.69), Vector3(0.09, 0.09, 0.07), eyes)
		for index: int in range(3 if acid else 4):
			var leg: Node3D = Node3D.new()
			leg.position = Vector3(float(side) * 0.28, 0.42, -0.32 + float(index) * 0.24)
			_creature_art.add_child(leg)
			_ellipsoid(leg, Vector3(float(side) * 0.31, -0.12, 0), Vector3(0.36, 0.06, 0.07), legs)
			_ellipsoid(leg, Vector3(float(side) * 0.55, -0.31, 0.04), Vector3(0.075, 0.2, 0.08), legs)
			_legs.append(leg)


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_creature_art) or not is_alive():
		return
	_crawl_time += delta * (3.0 + Vector2(velocity.x, velocity.z).length() * 4.0)
	for index: int in _legs.size():
		_legs[index].rotation.y = sin(_crawl_time + float(index) * PI) * 0.19
	_creature_art.position.y = sin(_crawl_time * 2.0) * 0.018


func _die() -> void:
	if is_instance_valid(_creature_art):
		_creature_art.reparent(get_parent(), true)
		_creature_art.position.y = global_position.y + 0.02
		_creature_art.scale.y = 0.34
	super._die()


func _material(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.76
	return result


func _ellipsoid(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	part.mesh = sphere
	part.material_override = material
	part.position = at
	part.scale = size
	parent.add_child(part)

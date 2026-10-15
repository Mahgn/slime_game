extends Node3D

const RECEIVER: Script = preload("res://scripts/dungeon/dungeon_property_receiver.gd")
const PERIOD: float = 6.5
var phase_offset: float = 0.0
var width: float = 2.7
var elapsed: float = 0.0
var frozen_seconds: float = 0.0
var lift: float = 0.0
var moving_body: AnimatableBody3D
var gear: StaticBody3D
var gear_mesh: MeshInstance3D
var _hits: Dictionary = {}
var _was_low: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var steel: StandardMaterial3D = _material(Color("7f887d"))
	var dark: StandardMaterial3D = _material(Color("3d4947"))
	moving_body = AnimatableBody3D.new()
	moving_body.name = "MovingGate"
	moving_body.collision_layer = 1
	moving_body.collision_mask = 0
	moving_body.sync_to_physics = false
	add_child(moving_body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(width,1.65,0.24)
	shape.shape = box
	shape.position.y = 0.825
	moving_body.add_child(shape)
	for index: int in 9:
		_box(moving_body, Vector3(-width*0.5 + width*float(index)/8.0,0.85,0), Vector3(0.075,1.7,0.14), steel)
	for height: float in [0.12, 1.65]:
		_box(moving_body, Vector3(0,height,0), Vector3(width,0.14,0.16), steel)
	# The open gate must remain supported when the surrounding wall is cut away.
	var frame := Node3D.new()
	frame.name = "IndependentGateFrame"
	add_child(frame)
	for side: int in [-1,1]:
		_box(frame, Vector3(float(side)*(width*0.5+0.2),1.92,0), Vector3(0.25,3.84,0.32), dark)
	_box(frame, Vector3(0,3.84,0), Vector3(width+0.65,0.18,0.36), dark)
	gear = RECEIVER.new() as StaticBody3D
	gear.set("mechanism", self)
	gear.name = "ExposedDrive"
	gear.collision_layer = 1
	gear.collision_mask = 0
	gear.position = Vector3(width*0.5+0.57,0.7,0)
	add_child(gear)
	var receiver_shape: CollisionShape3D = CollisionShape3D.new()
	var receiver_sphere: SphereShape3D = SphereShape3D.new()
	receiver_sphere.radius = 0.42
	receiver_shape.shape = receiver_sphere
	gear.add_child(receiver_shape)
	gear_mesh = MeshInstance3D.new()
	var wheel: TorusMesh = TorusMesh.new()
	wheel.inner_radius = 0.18
	wheel.outer_radius = 0.35
	wheel.rings = 16
	wheel.ring_segments = 8
	gear_mesh.mesh = wheel
	gear_mesh.material_override = _material(Color("b0b879"))
	gear_mesh.rotation.x = PI*0.5
	gear.add_child(gear_mesh)
	# A visible bracket and spindle connect the wheel to the fixed post.
	_box(frame, Vector3(width*0.5+0.4,0.7,0.12), Vector3(0.5,0.14,0.14), dark)
	_box(frame, Vector3(width*0.5+0.57,0.7,0.04), Vector3(0.12,0.12,0.3), steel)
	_update_lift(0.0)


func _physics_process(delta: float) -> void:
	if frozen_seconds > 0.0:
		frozen_seconds = maxf(0.0, frozen_seconds-delta)
		return
	elapsed += delta
	_update_lift(delta)
	gear_mesh.rotation.y += delta*1.7


func _update_lift(_delta: float) -> void:
	var cycle: float = fposmod(elapsed+phase_offset, PERIOD)
	lift = 2.0 if cycle < 3.1 else (lerpf(2.0,0.0,(cycle-3.1)/0.6) if cycle < 3.7 else (0.0 if cycle < 5.5 else lerpf(0.0,2.0,(cycle-5.5)/1.0)))
	moving_body.position.y = lift
	var low: bool = lift < 0.7
	if low and not _was_low:
		_hits.clear()
		for actor: Node in get_tree().get_nodes_in_group(&"player"):
			_hurt_actor(actor)
		for actor: Node in get_tree().get_nodes_in_group(&"enemies"):
			_hurt_actor(actor)
	_was_low = low


func _hurt_actor(actor: Node) -> void:
	if not actor is Node3D or not actor.has_method("is_alive") or not actor.call("is_alive"):
		return
	var relative: Vector3 = to_local((actor as Node3D).global_position)
	if absf(relative.x) > width*0.5+0.15 or absf(relative.z) > 0.55 or absf(relative.y) > 0.9:
		return
	if _hits.has(actor.get_instance_id()):
		return
	_hits[actor.get_instance_id()] = true
	if actor is SlimeController:
		(actor as SlimeController).apply_environment_damage(10)
	elif actor.has_method("receive_environment_hit"):
		actor.call("receive_environment_hit",10,"gate:%d:%d" % [get_instance_id(),int(elapsed/PERIOD)])


func receive_dungeon_property(ability_id: StringName, rank: int) -> bool:
	if ability_id != &"sticky_spit":
		return false
	frozen_seconds = 3.0 + 0.5*float(maxi(1,rank)-1)
	return true


func is_open() -> bool:
	return lift > 1.1


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.4
	material.roughness = 0.55
	return material

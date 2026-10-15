extends StaticBody3D

var intact: bool = true
var strength: int = 2
var _visual: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var volume: BoxShape3D = BoxShape3D.new()
	volume.size = Vector3(0.27,1.7,3.3)
	_shape.shape = volume
	_shape.position.y = 0.85
	add_child(_shape)
	_visual = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = volume.size
	_visual.mesh = mesh
	_visual.position.y = 0.85
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("929867")
	material.roughness = 0.95
	_visual.material_override = material
	add_child(_visual)
	# This gameplay obstacle keeps its own rooted frame when nearby walls fade.
	var support := Node3D.new()
	support.name = "IndependentMembraneFrame"
	add_child(support)
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color("515b42")
	frame_material.roughness = 0.95
	for side in [-1.0, 1.0]:
		_support_part(support, Vector3(0,0.92,side*1.7), Vector3(0.4,1.84,0.14), frame_material)
	_support_part(support, Vector3(0,1.78,0), Vector3(0.4,0.14,3.54), frame_material)
	_support_part(support, Vector3(0,0.05,0), Vector3(0.4,0.1,3.54), frame_material)
	for row: int in 5:
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rib_mesh: CapsuleMesh = CapsuleMesh.new()
		rib_mesh.radius = 0.04
		rib_mesh.height = 3.25
		rib.mesh = rib_mesh
		rib.material_override = material
		rib.rotation.x = PI*0.5
		rib.position = Vector3(0.18,0.2+float(row)*0.32,0)
		add_child(rib)


func _support_part(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)


func receive_dungeon_property(ability_id: StringName, rank: int) -> bool:
	if not intact or ability_id != &"acid_spit":
		return false
	strength -= maxi(1,rank)
	if strength <= 0:
		intact = false
		_shape.set_deferred("disabled",true)
		collision_layer = 0
		hide()
	else:
		_visual.scale.y = 0.68
	return true

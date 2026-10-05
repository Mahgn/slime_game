extends StaticBody3D
class_name FragileWall

signal broken

const MAX_HEALTH := 30

var health := MAX_HEALTH
var _casts: Dictionary = {}
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(&"training_targets")
	collision_layer = 4
	collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.2, 2.2, 0.42)
	collider.shape = shape
	collider.position.y = 1.1
	add_child(collider)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	_mesh.mesh = box
	_mesh.position.y = 1.1
	add_child(_mesh)
	_refresh_visual()


func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if source_team != &"player" or not cast_key.contains("slime_whip") or amount <= 0 or _casts.has(cast_key):
		return false
	_casts[cast_key] = true
	health = maxi(0, health - amount)
	if health == 0:
		broken.emit()
		queue_free()
	else:
		_refresh_visual()
	return true


func _refresh_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.57, 0.72, 0.68).lerp(Color(0.88, 0.48, 0.36), 1.0 - float(health) / MAX_HEALTH)
	material.roughness = 0.94
	_mesh.material_override = material

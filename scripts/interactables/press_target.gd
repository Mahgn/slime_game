extends StaticBody3D
class_name PressTarget

signal sticky_applied

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.0, 0.3)
	collider.shape = shape
	add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.44, 0.52, 0.56)
	mesh.material_override = stone
	add_child(mesh)
	var symbol := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	symbol.mesh = sphere
	symbol.position.z = 0.17
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.18, 0.98, 0.77)
	glow.emission_enabled = true
	glow.emission = Color(0.1, 0.80, 0.62)
	symbol.material_override = glow
	add_child(symbol)

func receive_hit(_amount: int, cast_key: String, source_team: StringName) -> bool:
	return source_team == &"player" and not cast_key.is_empty() and cast_key.contains("sticky_spit")

func apply_sticky(_factor: float, _seconds: float) -> void:
	sticky_applied.emit()

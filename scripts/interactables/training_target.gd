extends StaticBody3D
class_name TrainingTarget

const MAX_HEALTH := 55
const RESPAWN_SECONDS := 2.0

var health := MAX_HEALTH
var _sticky_left := 0.0
var _respawn_left := 0.0
var _received_casts: Dictionary = {}
var _body: MeshInstance3D
var _sticky_mark: SlimeStickyMark
var _collider: CollisionShape3D

func _ready() -> void:
	add_to_group(&"training_targets")
	collision_layer = 4
	collision_mask = 0
	_collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.9, 0.6)
	_collider.shape = shape
	_collider.position.y = 0.55
	add_child(_collider)
	_body = MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = shape.size
	_body.mesh = block
	_body.position = _collider.position
	_body.material_override = _material(Color(0.50, 0.60, 0.62))
	add_child(_body)
	_sticky_mark = SlimeStickyMark.new()
	_sticky_mark.name = "StickyMark"
	add_child(_sticky_mark)

func _physics_process(delta: float) -> void:
	if _respawn_left > 0.0:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		if _respawn_left == 0.0:
			health = MAX_HEALTH
			_received_casts.clear()
			_body.visible = true
			_collider.disabled = false
			collision_layer = 4
		return
	_sticky_left = maxf(0.0, _sticky_left - delta)
	_sticky_mark.visible = _sticky_left > 0.0

func receive_hit(amount: int, cast_key: String, source_team: StringName) -> bool:
	if _respawn_left > 0.0 or source_team != &"player" or amount <= 0 or cast_key.is_empty() or _received_casts.has(cast_key):
		return false
	_received_casts[cast_key] = true
	health = maxi(0, health - amount)
	if health == 0:
		_respawn_left = RESPAWN_SECONDS
		_sticky_left = 0.0
		_body.visible = false
		_sticky_mark.visible = false
		collision_layer = 0
		_collider.set_deferred("disabled", true)
	return true

func apply_sticky(_factor: float, seconds: float) -> void:
	if _respawn_left <= 0.0:
		_sticky_left = maxf(0.0, seconds)
		if _sticky_mark.mesh == null:
			set_sticky_impact(to_global(Vector3(0.0, 0.62, 0.30)), global_basis.z)
		_sticky_mark.visible = _sticky_left > 0.0


func set_sticky_impact(hit_position: Vector3, hit_normal: Vector3) -> void:
	if _respawn_left > 0.0:
		return
	_sticky_mark.place_on_hit(hit_position, hit_normal, self)
	_sticky_mark.visible = _sticky_left > 0.0


func get_sticky_time_left() -> float:
	return _sticky_left

func clear_sticky() -> void:
	_sticky_left = 0.0
	_sticky_mark.visible = false

func _material(tint: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.8
	if glowing:
		material.emission_enabled = true
		material.emission = tint
	return material

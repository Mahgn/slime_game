extends SpitProjectile

var ability_id: StringName = &"sticky_spit"
var ability_level: int = 1


func _ready() -> void:
	super._ready()
	if ability_id == &"acid_spit" and _gel_material != null:
		_gel_material.set_shader_parameter("gel_tint", Color(1.6, 1.1, 0.3))


func _apply_environment_property(target: Object) -> bool:
	if not is_instance_valid(target) or not target.has_method("receive_dungeon_property"):
		return false
	return bool(target.call("receive_dungeon_property", ability_id, ability_level))

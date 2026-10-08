extends SlimeCombatRuntime

# The level owns persistent encounters. Distant living enemies do not make
# every previously cleared room unsafe, but nearby pursuers and shots do.
var route: Node3D


func _physics_process(delta: float) -> void:
	var threatened: bool = not route.alive_enemies().is_empty()
	for group in [&"enemy_projectiles", &"enemy_attacks"]:
		for effect in get_tree().get_nodes_in_group(group):
			if effect is Node3D and effect.global_position.distance_to(player.global_position) < 20.0:
				threatened = true
	_safe_left = 0.5 if threatened else maxf(0.0, _safe_left - delta)


func _on_enemy_died(enemy: Node3D, ability_id: StringName, at: Vector3) -> void:
	if not is_instance_valid(player) or player.has_learned(ability_id):
		return
	var source := SOURCE.instantiate() as AbsorbSource
	source.ability_id = ability_id
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	source.set_meta(&"home_room", enemy.get_meta(&"home_room", ""))
	add_child(source)
	source.global_position = at
	source_created.emit(source)

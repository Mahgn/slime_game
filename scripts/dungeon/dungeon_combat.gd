extends "res://scripts/keepers/keepers_world_combat.gd"

const DUNGEON_PROJECTILE: Script = preload("res://scripts/dungeon/dungeon_projectile.gd")


func _on_action_started(action_id: StringName) -> void:
	super._on_action_started(action_id)
	if action_id == &"acid_spit":
		_play_audio(&"cast",player.global_position)


func _on_enemy_died(enemy: Node3D, ability_id: StringName, at: Vector3) -> void:
	if not is_instance_valid(player) or not player.can_absorb_ability(ability_id):
		return
	var source: AbsorbSource = SOURCE.instantiate() as AbsorbSource
	source.ability_id = ability_id
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	source.set_meta(&"home_room", enemy.get_meta(&"home_room", ""))
	add_child(source)
	source.global_position = at
	source_created.emit(source)


func _on_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	_create_property_projectile(player, &"player", player._action, (player as SlimeDungeonPlayer).get_ability_level(player._action), origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds)
	_play_audio(&"player_spit", origin)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if not is_instance_valid(enemy):
		return
	var sticky: bool = enemy.drop_ability_id == &"sticky_spit"
	_create_property_projectile(enemy, &"enemy", enemy.drop_ability_id, 1, origin, direction, damage, speed, max_range, cast_key, 0.65 if sticky else 1.0, 1.2 if sticky else 0.0)
	_play_audio(&"enemy_spit", origin)


func _create_property_projectile(owner_body: CollisionObject3D, team: StringName, ability_id: StringName, rank: int, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	var projectile: SpitProjectile = PROJECTILE.instantiate() as SpitProjectile
	projectile.set_script(DUNGEON_PROJECTILE)
	projectile.set("ability_id", ability_id)
	projectile.set("ability_level", maxi(1, rank))
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	add_child(projectile)
	projectile.global_position = origin
	projectile.resolved.connect(_on_projectile_resolved)

extends Node3D
class_name SlimeCombatRuntime

# Attack and absorption wiring retained from the removed room scripts.
# Levels provide actors and geometry; this node owns only transient combat nodes.
signal source_created(source: AbsorbSource)

const PROJECTILE = preload("res://scenes/abilities/spit_projectile.tscn")
const SOURCE = preload("res://scenes/interactables/absorb_source.tscn")
const SOUNDS := {
	&"hit": preload("res://assets/audio/hit.wav"),
	&"absorb": preload("res://assets/audio/absorb.wav"),
	&"cast": preload("res://assets/audio/cast.wav"),
	&"whip": preload("res://assets/audio/whip.wav"),
	&"player_spit": preload("res://assets/audio/player_spit.wav"),
	&"enemy_spit": preload("res://assets/audio/enemy_spit.wav"),
	&"enemy_charge": preload("res://assets/audio/enemy_charge.wav"),
}

var player: SlimeController
var _safe_left := 0.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(delta: float) -> void:
	var threatened := false
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			threatened = true
			break
	threatened = threatened or not get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty() or not get_tree().get_nodes_in_group(&"enemy_attacks").is_empty()
	_safe_left = 0.5 if threatened else maxf(0.0, _safe_left - delta)


func can_change_loadout() -> bool:
	return is_instance_valid(player) and player.is_alive() and _safe_left <= 0.0


func equip_ability(slot: int, ability_id: StringName) -> bool:
	return can_change_loadout() and player.equip_ability(slot, ability_id)


func bind_player(hero: SlimeController) -> void:
	assert(not is_instance_valid(player) or player == hero)
	if player == hero:
		return
	player = hero
	player.projectile_requested.connect(_on_player_projectile)
	player.spikes_requested.connect(_on_player_spikes)
	player.action_started.connect(_on_action_started)
	player.whip_hit.connect(_on_whip_hit)
	player.ability_unlocked.connect(_on_ability_unlocked)


func bind_enemy(enemy: Node3D) -> void:
	if enemy is Spitter:
		enemy.player_target = player
		enemy.projectile_requested.connect(_on_enemy_projectile)
		enemy.died.connect(_on_enemy_died)
		enemy.phase_changed.connect(_on_enemy_phase_changed)
	elif enemy is BorrowableEnemy:
		enemy.player_target = player
		enemy.spikes_requested.connect(_on_enemy_spikes)
		enemy.died.connect(_on_enemy_died)
		enemy.phase_changed.connect(_on_enemy_phase_changed)
	elif enemy is ExitGuardian:
		enemy.player_target = player
		enemy.line_requested.connect(_on_guardian_line)
		enemy.phase_changed.connect(_on_enemy_phase_changed)
		enemy.died.connect(clear_enemy_attacks)


func _on_enemy_died(_enemy: Node3D, ability_id: StringName, at: Vector3) -> void:
	if not is_instance_valid(player) or player.has_learned(ability_id):
		return
	var source := SOURCE.instantiate() as AbsorbSource
	source.ability_id = ability_id
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(source)
	source.global_position = at
	source_created.emit(source)


func _on_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	_add_projectile(player, &"player", origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds)
	_play_audio(&"player_spit", origin)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if is_instance_valid(enemy):
		_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key, 1.0, 0.0)
		_play_audio(&"enemy_spit", origin)


func _add_projectile(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	if not is_instance_valid(owner_body):
		return
	var projectile := PROJECTILE.instantiate() as SpitProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	add_child(projectile)
	projectile.global_position = origin
	projectile.resolved.connect(_on_projectile_resolved)


func _on_player_spikes(origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(player, origin, direction, cast_key, &"player", 22)
	_play_audio(&"cast", origin)


func _on_enemy_spikes(enemy: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(enemy, origin, direction, cast_key, &"enemy", 14)
	_play_audio(&"cast", origin)


func _on_guardian_line(enemy: ExitGuardian, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(enemy, origin, direction, cast_key, &"enemy", 14)
	_play_audio(&"cast", origin)


func _add_spikes(owner_body: CollisionObject3D, origin: Vector3, direction: Vector3, cast_key: String, team: StringName, damage: int) -> void:
	if not is_instance_valid(owner_body):
		return
	var line := SpikeLine.new()
	line.process_mode = Node.PROCESS_MODE_PAUSABLE
	line.configure(owner_body, team, origin, direction, cast_key, damage)
	add_child(line)
	line.hit_target.connect(_on_spike_hit)


func _on_projectile_resolved(at: Vector3, hit: bool) -> void:
	if hit:
		_play_audio(&"hit", at)


func _on_spike_hit(at: Vector3, _empowered: bool) -> void:
	_play_audio(&"hit", at)


func _on_whip_hit(at: Vector3) -> void:
	_play_audio(&"hit", at)


func _on_action_started(action_id: StringName) -> void:
	if action_id == &"slime_whip":
		_play_audio(&"whip", player.global_position)
	elif action_id == &"elastic_shell" or action_id == &"sticky_spit":
		_play_audio(&"cast", player.global_position)


func _on_ability_unlocked(_ability_id: StringName) -> void:
	_play_audio(&"absorb", player.global_position)


func _on_enemy_phase_changed(enemy: Node3D, phase: StringName) -> void:
	if phase == &"windup" and is_instance_valid(enemy):
		_play_audio(&"enemy_charge", enemy.global_position)


func clear_enemy_attacks() -> void:
	for child in get_children():
		if child.is_in_group(&"enemy_projectiles") or child.is_in_group(&"enemy_attacks"):
			child.set_physics_process(false)
			child.queue_free()


func _play_audio(sound: StringName, at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var voice := AudioStreamPlayer3D.new()
	voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	voice.stream = SOUNDS[sound]
	voice.bus = SlimeGameSettings.EFFECTS_BUS
	voice.unit_size = 4.0
	add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()

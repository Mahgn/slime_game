extends Node3D
class_name SlimeCombatRuntime

# Attack and absorption wiring retained from the removed room scripts.
# Levels provide actors and geometry; this node owns only transient combat nodes.
signal source_created(source: AbsorbSource)

const PROJECTILE = preload("res://scenes/abilities/spit_projectile.tscn")
const SOURCE = preload("res://scenes/interactables/absorb_source.tscn")
const IMPACT_FEEDBACK = preload("res://scripts/combat/combat_impact_feedback.gd")
const SOUND_PLAYBACK = preload("res://scripts/audio/sound_playback.gd")
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
var feedback: Node3D


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
	feedback = IMPACT_FEEDBACK.new()
	feedback.name = "CombatImpactFeedback"
	feedback.player = hero
	add_child(feedback)
	player.attack_impact_received.connect(_on_attack_impact)
	player.projectile_requested.connect(_on_player_projectile)
	player.spikes_requested.connect(_on_player_spikes)
	player.action_started.connect(_on_action_started)
	player.attack_contact.connect(_on_attack_contact)
	player.ability_unlocked.connect(_on_ability_unlocked)


func bind_enemy(enemy: Node3D) -> void:
	if enemy.has_signal("attack_impact_received"):
		enemy.connect("attack_impact_received", _on_attack_impact)
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
	var profile := player.get_impact_profile(player._action)
	_add_projectile(player, &"player", origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds, profile)
	if profile.release_sound == null:
		_play_audio(&"player_spit", origin)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if is_instance_valid(enemy):
		_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key, 1.0, 0.0, enemy.get_attack_impact_profile())
		_play_spell_release(enemy.get_attack_impact_profile(), origin, &"enemy_spit")


func _add_projectile(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float, profile: SlimeImpactProfile = null) -> void:
	if not is_instance_valid(owner_body):
		return
	var projectile := PROJECTILE.instantiate() as SpitProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds, profile)
	projectile.attack_contact.connect(_on_attack_contact)
	add_child(projectile)
	projectile.global_position = origin


func _on_player_spikes(origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(player, origin, direction, cast_key, &"player", 22, player.get_impact_profile(&"slime_spikes"))
	if player.get_impact_profile(&"slime_spikes").release_sound == null:
		_play_audio(&"cast", origin)


func _on_enemy_spikes(enemy: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(enemy, origin, direction, cast_key, &"enemy", 14)
	_play_spell_release(SlimeImpactProfiles.SPIKES, origin, &"cast")


func _on_guardian_line(enemy: ExitGuardian, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(enemy, origin, direction, cast_key, &"enemy", 14)
	_play_spell_release(SlimeImpactProfiles.SPIKES, origin, &"cast")


func _add_spikes(owner_body: CollisionObject3D, origin: Vector3, direction: Vector3, cast_key: String, team: StringName, damage: int, profile: SlimeImpactProfile = null) -> void:
	if not is_instance_valid(owner_body):
		return
	var line := SpikeLine.new()
	line.process_mode = Node.PROCESS_MODE_PAUSABLE
	line.configure(owner_body, team, origin, direction, cast_key, damage, profile)
	line.attack_contact.connect(_on_attack_contact)
	add_child(line)


func _on_attack_impact(at: Vector3, lethal: bool, profile: SlimeImpactProfile, direction: Vector3) -> void:
	if not is_instance_valid(feedback):
		return
	feedback.play_impact(at, direction, lethal, profile)
	_play_impact_audio(profile, at)


func _on_attack_contact(at: Vector3, direction: Vector3, profile: SlimeImpactProfile, handled_by_actor: bool) -> void:
	# Actor HP events own damage presentation. Surface contacts never infer HP
	# loss, shake or hitstop, and never layer a second copy of the impact sound.
	if handled_by_actor or not is_instance_valid(feedback):
		return
	feedback.play_contact(at, direction, profile)
	_play_impact_audio(profile, at)


func _play_impact_audio(profile: SlimeImpactProfile, at: Vector3) -> void:
	var selected := profile if profile != null else SlimeImpactProfiles.GENERIC
	SOUND_PLAYBACK.play_3d(self, selected.impact_sound, at, {
		"pitch_variation": selected.pitch_variation,
		"pitch_base": selected.pitch_base,
		"volume_db": selected.volume_db,
	})


func _on_action_started(action_id: StringName) -> void:
	if player.get_impact_profile(action_id).charge_sound != null:
		return
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


func clear_transients(immediate: bool = false) -> void:
	if is_instance_valid(player) and is_instance_valid(player.spell_visual):
		player.spell_visual.reset()
	if is_instance_valid(feedback):
		feedback.reset()
	for child in get_children():
		if child == feedback:
			continue
		child.process_mode = Node.PROCESS_MODE_DISABLED
		if immediate:
			child.free()
		else:
			child.queue_free()


func _play_spell_release(profile: SlimeImpactProfile, at: Vector3, fallback: StringName) -> void:
	if profile != null and profile.release_sound != null:
		SOUND_PLAYBACK.play_3d(self, profile.release_sound, at, {
			"pitch_variation": profile.cast_pitch_variation, "volume_db": -4.0})
	else:
		_play_audio(fallback, at)


func _play_audio(sound: StringName, at: Vector3) -> void:
	var variation := 0.025 if sound in [&"whip", &"player_spit", &"enemy_spit"] else 0.0
	SOUND_PLAYBACK.play_3d(self, SOUNDS[sound], at, {"pitch_variation": variation})


func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()

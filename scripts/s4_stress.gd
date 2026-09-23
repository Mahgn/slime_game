extends Node3D

const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const ARMORER_SCENE = preload("res://scenes/enemies/armorer.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")
const SPIKE_SCRIPT = preload("res://scripts/combat/spike_line.gd")
const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const EFFECT_LIMIT := 40
const WARMUP_SECONDS := 3.0
const SAMPLE_SECONDS := 60.0

@onready var player: SlimeController = $SlimePlayer

var _start_usec := 0
var _last_frame_usec := 0
var _projectile_timer := 0.0
var _sequence := 0
var _frame_ms: Array[float] = []
var _peak_nodes := 0
var _peak_effects := 0
var _peak_enemies := 0


func _enter_tree() -> void:
	INPUT_SETUP.install()


func _ready() -> void:
	player.health = 1000000
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for position in [Vector3(-5, 0.05, -7), Vector3(-2.5, 0.05, -7), Vector3(2.5, 0.05, -7), Vector3(5, 0.05, -7)]:
		_spawn(SPITTER_SCENE, position)
	for position in [Vector3(-5, 0.05, 5), Vector3(0, 0.05, 6), Vector3(5, 0.05, 5)]:
		_spawn(ARMORER_SCENE, position)
	for position in [Vector3(-5.5, 0.05, -1.5), Vector3(5.5, 0.05, -1.5), Vector3(0, 0.05, -8)]:
		_spawn(SPROUT_SCENE, position)
	_start_usec = Time.get_ticks_usec()
	_last_frame_usec = _start_usec
	print("STRESS_START enemies=%d effect_limit=%d warmup_s=%.1f sample_s=%.1f renderer=%s" % [get_tree().get_nodes_in_group(&"enemies").size(), EFFECT_LIMIT, WARMUP_SECONDS, SAMPLE_SECONDS, str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))])


func _spawn(scene: PackedScene, at: Vector3) -> void:
	var enemy := scene.instantiate() as Node3D
	enemy.position = at
	enemy.set("player_target", player)
	add_child(enemy)
	if enemy is Spitter:
		(enemy as Spitter).projectile_requested.connect(_on_enemy_projectile)
	else:
		(enemy as BorrowableEnemy).spikes_requested.connect(_on_enemy_spikes)


func _physics_process(delta: float) -> void:
	_projectile_timer += delta
	if _projectile_timer < 0.35 or _effect_count() >= EFFECT_LIMIT:
		return
	_projectile_timer = 0.0
	_sequence += 1
	var angle := float(_sequence) * 2.39996
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	_add_projectile(player, &"player", player.global_position + Vector3.UP * 2.0, direction, 0, 0.13, 5.0, "stress_%d" % _sequence)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if is_instance_valid(enemy) and _effect_count() < EFFECT_LIMIT:
		_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key)


func _on_enemy_spikes(enemy: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	if not is_instance_valid(enemy) or _effect_count() >= EFFECT_LIMIT:
		return
	var line := SpikeLine.new()
	line.configure(enemy, &"enemy", origin, direction, cast_key, 14)
	add_child(line)


func _add_projectile(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as SpitProjectile
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key)
	add_child(projectile)
	projectile.global_position = origin


func _effect_count() -> int:
	return get_tree().get_nodes_in_group(&"projectiles").size() + get_tree().get_nodes_in_group(&"temporary_effects").size()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _start_usec) / 1000000.0
	if elapsed >= WARMUP_SECONDS and _last_frame_usec > 0:
		_frame_ms.append(float(now - _last_frame_usec) / 1000.0)
		_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		_peak_effects = maxi(_peak_effects, _effect_count())
		_peak_enemies = maxi(_peak_enemies, get_tree().get_nodes_in_group(&"enemies").size())
	_last_frame_usec = now
	if elapsed >= WARMUP_SECONDS + SAMPLE_SECONDS:
		_finish()


func _finish() -> void:
	_frame_ms.sort()
	var count := _frame_ms.size()
	var median := _frame_ms[count / 2] if count > 0 else 0.0
	var p95_index := mini(count - 1, ceili(float(count) * 0.95) - 1)
	var p95 := _frame_ms[p95_index] if count > 0 else 0.0
	print("STRESS_RESULT seconds=%.1f samples=%d median_frame_ms=%.3f p95_frame_ms=%.3f peak_nodes=%d peak_effects=%d peak_enemies=%d player_hp=%d" % [SAMPLE_SECONDS, count, median, p95, _peak_nodes, _peak_effects, _peak_enemies, player.health])
	get_tree().quit(0)

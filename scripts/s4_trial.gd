extends Node3D

@export_enum("trial", "r03", "r04", "r05", "r06", "r07") var room_mode := "trial"

const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")
const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const ARMORER_SCENE = preload("res://scenes/enemies/armorer.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const SOURCE_SCENE = preload("res://scenes/interactables/absorb_source.tscn")
const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")
const SPIKE_SCRIPT = preload("res://scripts/combat/spike_line.gd")
const TRAINING_TARGET_SCRIPT = preload("res://scripts/interactables/training_target.gd")
const HIT_SOUND = preload("res://assets/audio/hit.wav")
const ABSORB_SOUND = preload("res://assets/audio/absorb.wav")
const CAST_SOUND = preload("res://assets/audio/cast.wav")
const WHIP_SOUND = preload("res://assets/audio/whip.wav")
const PLAYER_SPIT_SOUND = preload("res://assets/audio/player_spit.wav")
const ENEMY_CHARGE_SOUND = preload("res://assets/audio/enemy_charge.wav")
const ENEMY_SPIT_SOUND = preload("res://assets/audio/enemy_spit.wav")
const ABILITIES: Array[StringName] = [&"sticky_spit", &"elastic_shell", &"slime_spikes"]
const NAMES := {&"sticky_spit": "Липкий плевок", &"elastic_shell": "Упругий панцирь", &"slime_spikes": "Слизевые шипы"}
const DESCRIPTIONS := {
	&"sticky_spit": "Дальний выстрел, замедляет цель",
	&"elastic_shell": "Поглощает 25 урона одного удара",
	&"slime_spikes": "Линия по земле, +11 по липкой цели",
}

@onready var player: SlimeController = $SlimePlayer

var stage: StringName = &"armorer"
var _sources: Array[AbsorbSource] = []
var _core: Node3D
var _core_hold := 0.0
var _core_requires_release := true
var _stage_delay := 0.0
var _save_retry_left := 0.0
var _safe_left := 0.5
var _card_left := 0.0
var _info_left := 0.0
var _info_text := ""
var _collection_open := false
var _underlying_pause := false
var _chosen_slot := 1
var _hud: CanvasLayer
var _health_label: Label
var _slot_labels: Array[Label] = []
var _hint_label: Label
var _card_label: Label
var _card_panel: ColorRect
var _progress: ProgressBar
var _collection_panel: ColorRect
var _collection_cards: Array[Button] = []
var _collection_slots: Array[Button] = []
var _pause_panel: ColorRect
var _end_panel: ColorRect
var _end_title: Label
var _continue_button: Button
var _route_label: Label
var _entry_slot_one: StringName = &"sticky_spit"
var _entry_slot_two: StringName = &""
var _exit_marker: Node3D


func _enter_tree() -> void:
	INPUT_SETUP.install()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_create_hud()
	var saved_entry := _saved_entry()
	if get_tree().get_meta(&"checkpoint_active", false) and saved_entry.is_empty():
		_show_end("Не удалось восстановить входной снимок")
		return
	if room_mode == "r04":
		_add_upper_light()
		_spawn_exit_marker()
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_player_damaged)
	player.shell_blocked.connect(func() -> void: _play_audio(HIT_SOUND, player.global_position))
	player.died.connect(_on_player_died)
	player.ability_unlocked.connect(_on_ability_unlocked)
	player.absorb_progress_changed.connect(_on_absorb_progress)
	player.projectile_requested.connect(_on_player_projectile)
	player.spikes_requested.connect(_on_player_spikes)
	player.info_requested.connect(_show_info)
	player.whip_hit.connect(func(at: Vector3) -> void: _play_audio(HIT_SOUND, at))
	player.action_started.connect(_on_action_started)
	player.loadout_changed.connect(_refresh_collection)
	player.grant_ability(&"sticky_spit")
	if room_mode == "r04":
		stage = &"core"
		player.grant_ability(&"elastic_shell")
		var slot_one := StringName(saved_entry["loadout"][0]) if not saved_entry.is_empty() else StringName(get_tree().get_meta(&"r03_slot_one", &"sticky_spit"))
		get_tree().remove_meta(&"r03_slot_one")
		if slot_one != &"sticky_spit" and slot_one != &"elastic_shell" and slot_one != &"":
			slot_one = &"sticky_spit"
		_entry_slot_one = slot_one
		if slot_one != &"sticky_spit":
			player.equip_ability(1, slot_one)
		_card_left = 0.0
		_spawn_core()
	elif room_mode == "r05":
		stage = &"mixed"
		player.grant_ability(&"elastic_shell")
		player.grant_ability(&"slime_spikes")
		player.unlock_second_slot()
		_restore_r05_entry(saved_entry)
		_card_left = 0.0
		_spawn_mixed_fight()
	elif room_mode == "r03":
		if not saved_entry.is_empty():
			player.equip_ability(1, StringName(saved_entry["loadout"][0]))
		_spawn_enemy(ARMORER_SCENE, Vector3(0.0, 0.05, 0.0))
	else:
		_spawn_enemy(ARMORER_SCENE, Vector3(0.0, 0.05, 0.0))
	_on_health_changed(player.health, player.MAX_HEALTH)
	if room_mode == "r03":
		_show_info("R03 · Панцирный проход: победи Панцирника")
	elif room_mode == "r04":
		_show_info("R04 · Зал ядра: открой вторую ячейку")
	elif room_mode == "r05":
		_show_info("R05 · Смешанный зал: выбери цель и обходи опоры")
	else:
		_show_info("Испытание навыков: победи Панцирника")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if stage == &"dead" or stage == &"complete":
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
			_restart()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"open_loadout") and not (event is InputEventKey and event.echo):
		if _collection_open:
			_close_collection()
		elif not _underlying_pause:
			_try_open_collection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") and not (event is InputEventKey and event.echo):
		if _collection_open:
			_close_collection()
		elif _underlying_pause:
			_underlying_pause = false
			_update_pause_state()
		else:
			_underlying_pause = true
			player.cancel_absorb_for_pause()
			player.clear_action_buffer()
			_update_pause_state()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and stage != &"dead" and stage != &"complete":
		_underlying_pause = true
		player.cancel_absorb_for_pause()
		player.clear_action_buffer()
		_update_pause_state()


func _physics_process(delta: float) -> void:
	_save_retry_left = maxf(0.0, _save_retry_left - delta)
	if get_tree().paused or stage == &"dead" or stage == &"complete" or stage == &"transition":
		return
	for source in _sources:
		if is_instance_valid(source):
			source.set_focused(player.get_nearest_absorb_source() == source)
	var threat := false
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.call("is_alive"):
			threat = true
			break
	threat = threat or not get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty() or not get_tree().get_nodes_in_group(&"enemy_attacks").is_empty()
	_safe_left = 0.5 if threat else maxf(0.0, _safe_left - delta)
	if stage == &"r03_exit" and _save_retry_left <= 0.0 and _safe_left <= 0.0 and _card_left <= 0.0 and player.global_position.z <= -3.2:
		stage = &"transition"
		get_tree().set_meta(&"r03_slot_one", player.get_slot_ability(1))
		call_deferred("_enter_r04")
	elif stage == &"r04_exit" and _safe_left <= 0.0 and _card_left <= 0.0 and player.global_position.distance_to(Vector3(0.0, 0.05, -8.2)) <= 1.6 and Input.is_action_just_pressed(&"interact"):
		stage = &"transition"
		get_tree().set_meta(&"r05_entry", {"slot_one": player.get_slot_ability(1), "slot_two": player.get_slot_ability(2)})
		call_deferred("_enter_r05")
	elif stage == &"core":
		_update_core_interaction(delta)
	elif stage == &"sprout_wait" or stage == &"mixed_wait":
		_stage_delay = maxf(0.0, _stage_delay - delta)
		if _stage_delay <= 0.0:
			if stage == &"sprout_wait":
				stage = &"sprout"
				_spawn_enemy(SPROUT_SCENE, Vector3(0.0, 0.05, -6.8))
				_show_info("Каменный росток: прыгай над низкими шипами")
			else:
				stage = &"mixed"
				_spawn_mixed_fight()
	elif stage == &"mixed" and not threat and _safe_left <= 0.0:
		stage = &"complete"
		_show_end("R05 пройден" if room_mode == "r05" else "Испытание S4 пройдено")


func _process(delta: float) -> void:
	if get_tree().paused or stage == &"dead" or stage == &"complete":
		return
	_card_left = maxf(0.0, _card_left - delta)
	_info_left = maxf(0.0, _info_left - delta)
	_card_panel.visible = _card_left > 0.0
	for index in 2:
		var slot := index + 1
		var ability_id := player.get_slot_ability(slot)
		var control_name := "ПКМ" if slot == 1 else "Q"
		if slot > player.unlocked_slots:
			_slot_labels[index].text = "%s · ЗАКРЫТО" % control_name
		elif ability_id == &"":
			_slot_labels[index].text = "%s · ПУСТО" % control_name
		elif player.cooldown_remaining(ability_id) > 0.05:
			_slot_labels[index].text = "%s · %s  %.1f с" % [control_name, NAMES[ability_id], player.cooldown_remaining(ability_id)]
		else:
			_slot_labels[index].text = "%s · %s  ГОТОВ" % [control_name, NAMES[ability_id]]
	if _info_left > 0.0:
		_hint_label.text = _info_text
	elif stage == &"absorb_shell" or stage == &"absorb_spikes":
		_hint_label.text = "Подойди к остатку и удерживай E"
	elif stage == &"core":
		_hint_label.text = "Ядро: подойди и удерживай E"
	elif stage == &"r03_exit":
		_hint_label.text = "Панцирь изучен. Tab — выбор навыка; иди к золотой линии"
	elif stage == &"r04_exit":
		_hint_label.text = "Выбери два навыка (Tab), затем у светлой отметки нажми E"
	elif stage == &"mixed_wait":
		_hint_label.text = "Tab — коллекция. Выбери два навыка перед боем"
	else:
		_hint_label.text = "ЛКМ — хлыст · ПКМ/Q — навыки · Tab — коллекция вне боя"


func _spawn_enemy(scene: PackedScene, at: Vector3) -> Node3D:
	var enemy := scene.instantiate() as Node3D
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.position = at
	enemy.set("player_target", player)
	enemy.set("attack_permission", Callable(self, "_attack_allowed"))
	add_child(enemy)
	if enemy is Spitter:
		(enemy as Spitter).projectile_requested.connect(_on_enemy_projectile)
		(enemy as Spitter).died.connect(_on_spitter_died)
		(enemy as Spitter).phase_changed.connect(_on_enemy_phase_changed)
	else:
		(enemy as BorrowableEnemy).spikes_requested.connect(_on_enemy_spikes)
		(enemy as BorrowableEnemy).died.connect(_on_borrowable_died)
		(enemy as BorrowableEnemy).phase_changed.connect(_on_enemy_phase_changed)
	return enemy


func _attack_allowed(requester: Node) -> bool:
	var active := 0
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if enemy != requester and is_instance_valid(enemy) and enemy.has_method("get_attack_phase") and enemy.call("get_attack_phase") == &"windup":
			active += 1
	return active < 2


func _on_spitter_died(_enemy: Spitter, ability_id: StringName, at: Vector3) -> void:
	_drop_source(ability_id, at)


func _on_borrowable_died(_enemy: BorrowableEnemy, ability_id: StringName, at: Vector3) -> void:
	if stage == &"armorer":
		stage = &"absorb_shell"
		_show_info("Удерживай E у остатка Панцирника")
	elif stage == &"sprout":
		stage = &"absorb_spikes"
		_show_info("Удерживай E у остатка Каменного ростка")
	_drop_source(ability_id, at)


func _drop_source(ability_id: StringName, at: Vector3) -> void:
	if player.has_learned(ability_id):
		return
	var source := SOURCE_SCENE.instantiate() as AbsorbSource
	source.ability_id = ability_id
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	source.position = at
	add_child(source)
	_sources.append(source)


func _on_ability_unlocked(ability_id: StringName) -> void:
	if ability_id == &"sticky_spit":
		return
	_play_audio(ABSORB_SOUND, player.global_position)
	_card_left = 1.8
	_card_label.text = "%s изучен\n%s" % [NAMES[ability_id], "Выбери вне боя (Tab)" if ability_id == &"slime_spikes" else "Навык в коллекции"]
	if ability_id == &"elastic_shell" and stage == &"absorb_shell":
		if room_mode == "r03":
			stage = &"r03_exit"
			_show_info("Панцирь изучен. Прогресс сохранится в следующем зале")
		else:
			stage = &"core"
			_spawn_core()
			_show_info("Найди золотое ядро впереди")
	elif ability_id == &"slime_spikes" and stage == &"absorb_spikes":
		if room_mode == "r04":
			stage = &"r04_exit"
			_exit_marker.visible = true
			_spawn_training_target()
			_show_info("Липкие цели получают больше урона от шипов")
		else:
			stage = &"mixed_wait"
			_stage_delay = 7.0
			_show_info("Навык изучен. Tab — выбери два для смешанного боя")


func _spawn_training_target() -> void:
	var target := StaticBody3D.new()
	target.set_script(TRAINING_TARGET_SCRIPT)
	target.name = "TrainingTarget"
	target.position = Vector3(-3.0, 0.0, -7.0)
	target.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(target)


func _spawn_core() -> void:
	_core = Node3D.new()
	_core.name = "TestCore"
	_core.position = Vector3(0.0, 0.0, -4.5)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.30
	sphere.height = 0.60
	mesh.mesh = sphere
	mesh.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.98, 0.78, 0.35)
	material.emission_enabled = true
	material.emission = Color(0.85, 0.49, 0.12)
	mesh.material_override = material
	_core.add_child(mesh)
	add_child(_core)


func _update_core_interaction(delta: float) -> void:
	if not Input.is_action_pressed(&"interact"):
		_core_requires_release = false
		_core_hold = 0.0
		_progress.visible = false
		return
	if _core_requires_release or not is_instance_valid(_core) or player.global_position.distance_to(_core.global_position) > 1.6 or not player.is_on_floor() or player.get("_action") != &"" or Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").length_squared() > 0.01:
		_core_hold = 0.0
		_progress.visible = false
		return
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.55, _core.global_position + Vector3.UP * 0.8, 1)
	query.exclude = [player.get_rid()]
	if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_core_hold = 0.0
		_progress.visible = false
		return
	_core_hold += delta
	_progress.value = minf(1.0, _core_hold / 0.55)
	_progress.visible = true
	if _core_hold >= 0.55 and player.unlock_second_slot():
		_core.queue_free()
		_core = null
		_core_requires_release = true
		_core_hold = 0.0
		_progress.visible = false
		stage = &"sprout_wait"
		_stage_delay = 2.2
		_card_left = 1.8
		_card_label.text = "Открыта вторая ячейка\nQ — второй навык"
		_show_info("Теперь можно сочетать два навыка")


func _on_absorb_progress(progress: float, _source: Node3D) -> void:
	if stage == &"core":
		return
	_progress.value = progress
	_progress.visible = progress > 0.0


func _on_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	_add_projectile(player, &"player", origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds)
	_play_audio(PLAYER_SPIT_SOUND, origin)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if is_instance_valid(enemy):
		_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key, 1.0, 0.0)
		_play_audio(ENEMY_SPIT_SOUND, origin)


func _add_projectile(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as SpitProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	add_child(projectile)
	projectile.global_position = origin
	projectile.resolved.connect(func(at: Vector3, hit: bool) -> void:
		if hit:
			_play_audio(HIT_SOUND, at)
	)


func _on_player_spikes(origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(player, &"player", origin, direction, cast_key, 22)
	_play_audio(CAST_SOUND, origin)


func _on_enemy_spikes(enemy: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	if is_instance_valid(enemy):
		_add_spikes(enemy, &"enemy", origin, direction, cast_key, 14)
		_play_audio(CAST_SOUND, origin)


func _add_spikes(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, cast_key: String, damage: int) -> void:
	var line := Node3D.new()
	line.set_script(SPIKE_SCRIPT)
	line.process_mode = Node.PROCESS_MODE_PAUSABLE
	line.configure(owner_body, team, origin, direction, cast_key, damage)
	add_child(line)
	line.hit_target.connect(func(at: Vector3, _empowered: bool) -> void: _play_audio(HIT_SOUND, at))


func _on_enemy_phase_changed(enemy: Node, phase: StringName) -> void:
	if phase == &"windup" and is_instance_valid(enemy) and enemy is Node3D:
		_play_audio(ENEMY_CHARGE_SOUND, (enemy as Node3D).global_position)


func _on_action_started(action_id: StringName) -> void:
	if action_id == &"slime_whip":
		_play_audio(WHIP_SOUND, player.global_position)
	elif action_id == &"elastic_shell":
		_play_audio(CAST_SOUND, player.global_position)


func _play_audio(stream: AudioStream, at: Vector3) -> void:
	var voice := AudioStreamPlayer3D.new()
	voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	voice.stream = stream
	voice.unit_size = 4.0
	add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


func _try_open_collection() -> void:
	if _safe_left > 0.0 or not get_tree().get_nodes_in_group(&"enemies").is_empty() or not get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty() or not get_tree().get_nodes_in_group(&"enemy_attacks").is_empty():
		_show_info("Сначала закончи бой")
		return
	_collection_open = true
	_card_panel.visible = false
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	_refresh_collection()
	_update_pause_state()


func _close_collection() -> void:
	_collection_open = false
	_card_panel.visible = _card_left > 0.0
	_update_pause_state()


func _update_pause_state() -> void:
	get_tree().paused = _underlying_pause or _collection_open
	_pause_panel.visible = _underlying_pause and not _collection_open
	_collection_panel.visible = _collection_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


func _refresh_collection() -> void:
	if not is_instance_valid(_collection_panel):
		return
	for index in 2:
		var slot := index + 1
		var id := player.get_slot_ability(slot)
		_collection_slots[index].text = "%d. %s%s" % [slot, NAMES.get(id, "Пусто") if slot <= player.unlocked_slots else "Закрыто", " ◀" if _chosen_slot == slot else ""]
		_collection_slots[index].disabled = slot > player.unlocked_slots
	for index in ABILITIES.size():
		var id := ABILITIES[index]
		_collection_cards[index].text = "%s\n%s" % [NAMES[id], DESCRIPTIONS[id]] if player.has_learned(id) else "? ? ?\nНе изучено"
		_collection_cards[index].disabled = not player.has_learned(id)


func _select_slot(slot: int) -> void:
	_chosen_slot = slot
	_refresh_collection()


func _equip_card(ability_id: StringName) -> void:
	if player.equip_ability(_chosen_slot, ability_id):
		_refresh_collection()
		_update_saved_loadout_if_eligible()
	else:
		_show_info("Навык уже стоит в другом слоте")


func _on_health_changed(current: int, maximum: int) -> void:
	_health_label.text = "СЛАЙМ  %d / %d HP" % [current, maximum]


func _on_player_died() -> void:
	stage = &"dead"
	_show_end("Слайм рассыпался")


func _on_player_damaged() -> void:
	_core_hold = 0.0
	_core_requires_release = true
	_progress.visible = false


func _show_end(title: String) -> void:
	_end_title.text = title
	_end_panel.visible = true
	if is_instance_valid(_continue_button):
		_continue_button.visible = (room_mode == "r05" or room_mode == "r06") and stage == &"complete"
	_collection_open = false
	_underlying_pause = true
	_update_pause_state()


func _restart() -> void:
	if not get_tree().get_meta(&"checkpoint_active", false) and room_mode == "r04":
		get_tree().set_meta(&"r03_slot_one", _entry_slot_one)
	elif not get_tree().get_meta(&"checkpoint_active", false) and room_mode == "r05":
		get_tree().set_meta(&"r05_entry", {"slot_one": _entry_slot_one, "slot_two": _entry_slot_two})
	get_tree().paused = false
	get_tree().reload_current_scene()


func _enter_r07() -> void:
	if room_mode != "r06" or stage != &"complete":
		return
	if not _write_next_entry("R07"):
		_end_title.text = "Не удалось сохранить вход в R07"
		return
	get_tree().paused = false
	var result := get_tree().change_scene_to_file("res://scenes/r07_guardian.tscn")
	if result != OK:
		_show_end("Не удалось открыть R07")
		push_error("R06: переход в R07 не удался: %d" % result)


func _enter_r06() -> void:
	if room_mode != "r05" or stage != &"complete":
		return
	if not _write_next_entry("R06"):
		_end_title.text = "Не удалось сохранить вход в R06"
		return
	get_tree().paused = false
	var result := get_tree().change_scene_to_file("res://scenes/r06_press.tscn")
	if result != OK:
		_show_end("Не удалось открыть R06")
		push_error("R05: переход в R06 не удался: %d" % result)


func _enter_r04() -> void:
	if not _write_next_entry("R04"):
		get_tree().remove_meta(&"r03_slot_one")
		stage = &"r03_exit"
		_save_retry_left = 3.0
		return
	var result := get_tree().change_scene_to_file("res://scenes/r04_core_trial.tscn")
	if result != OK:
		get_tree().remove_meta(&"r03_slot_one")
		stage = &"r03_exit"
		push_error("R03: переход в R04 не удался: %d" % result)


func _enter_r05() -> void:
	if not _write_next_entry("R05"):
		get_tree().remove_meta(&"r05_entry")
		stage = &"r04_exit"
		return
	var result := get_tree().change_scene_to_file("res://scenes/r05_mixed.tscn")
	if result != OK:
		get_tree().remove_meta(&"r05_entry")
		stage = &"r04_exit"
		push_error("R04: переход в R05 не удался: %d" % result)


func _restore_r05_entry(saved_entry: Dictionary = {}) -> void:
	var raw_entry: Variant = get_tree().get_meta(&"r05_entry", {})
	get_tree().remove_meta(&"r05_entry")
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	if not saved_entry.is_empty():
		entry = {"slot_one": saved_entry["loadout"][0], "slot_two": saved_entry["loadout"][1]}
	var slot_one := StringName(entry.get("slot_one", &"sticky_spit"))
	var slot_two := StringName(entry.get("slot_two", &"elastic_shell"))
	if slot_one != &"" and not ABILITIES.has(slot_one):
		slot_one = &"sticky_spit"
	if slot_two != &"" and not ABILITIES.has(slot_two):
		slot_two = &"elastic_shell"
	if slot_one != &"" and slot_one == slot_two:
		slot_two = &""
	_entry_slot_one = slot_one
	_entry_slot_two = slot_two
	player.equip_ability(1, &"")
	player.equip_ability(2, &"")
	player.equip_ability(1, slot_one)
	player.equip_ability(2, slot_two)


func _saved_entry() -> Dictionary:
	if room_mode == "trial" or not get_tree().get_meta(&"checkpoint_active", false):
		return {}
	var store: CheckpointStore = STORE_SCRIPT.new()
	var result := store.read_checkpoint()
	if result["status"] != "ok":
		return {}
	var entry: Dictionary = result["snapshot"]
	return entry if entry["checkpoint_room_id"] == room_mode.to_upper() else {}


func _write_next_entry(room_id: String) -> bool:
	if not get_tree().get_meta(&"checkpoint_active", false):
		return true
	var store: CheckpointStore = STORE_SCRIPT.new()
	var written := store.write_checkpoint(store.snapshot_for_room(room_id, player))
	if not written["ok"]:
		_show_info("Не удалось сохранить вход: %s" % written["error"])
		return false
	return true


func _update_saved_loadout_if_eligible() -> void:
	if room_mode == "trial" or not get_tree().get_meta(&"checkpoint_active", false):
		return
	var store: CheckpointStore = STORE_SCRIPT.new()
	var result := store.read_checkpoint()
	if result["status"] != "ok" or result["snapshot"]["checkpoint_room_id"] != room_mode.to_upper():
		return
	var learned: Array = result["snapshot"]["learned_abilities"]
	if player.unlocked_slots != result["snapshot"]["unlocked_slots"]:
		return
	for ability: Variant in player.learned_abilities.keys():
		if not learned.has(String(ability)):
			return
	var first := String(player.get_slot_ability(1))
	var second := String(player.get_slot_ability(2))
	if (first != "" and not learned.has(first)) or (second != "" and not learned.has(second)):
		return
	if not store.update_saved_loadout(room_mode.to_upper(), player):
		_show_info("Не удалось сохранить сборку")


func _spawn_mixed_fight() -> void:
	if room_mode == "r05":
		_spawn_enemy(SPITTER_SCENE, Vector3(-5.7, 0.05, -2.0))
		_spawn_enemy(ARMORER_SCENE, Vector3(5.7, 0.05, -2.0))
		_spawn_enemy(SPROUT_SCENE, Vector3(0.0, 0.05, -2.7))
	else:
		_spawn_enemy(SPITTER_SCENE, Vector3(-4.8, 0.05, -6.5))
		_spawn_enemy(ARMORER_SCENE, Vector3(3.7, 0.05, -4.5))
		_spawn_enemy(SPROUT_SCENE, Vector3(0.0, 0.05, 0.3))
	_show_info("Смешанный бой: три врага, выбирай два навыка")


func _spawn_exit_marker() -> void:
	_exit_marker = Node3D.new()
	_exit_marker.name = "R05Exit"
	_exit_marker.position = Vector3(0.0, 0.0, -8.2)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.05, 0.3)
	mesh.mesh = box
	mesh.position.y = 0.045
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.93, 0.86, 0.57)
	material.emission_enabled = true
	material.emission = Color(0.96, 0.65, 0.23)
	mesh.material_override = material
	_exit_marker.add_child(mesh)
	add_child(_exit_marker)
	_exit_marker.visible = false


func _add_upper_light() -> void:
	var glow := MeshInstance3D.new()
	glow.name = "UpperLight"
	glow.position = Vector3(0.0, 2.62, -9.78)
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 0.48, 0.08)
	glow.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.53)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.72, 0.36)
	material.emission_energy_multiplier = 1.1
	glow.material_override = material
	add_child(glow)
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 2.6, -8.7)
	light.light_color = Color(1.0, 0.78, 0.48)
	light.light_energy = 1.0
	light.omni_range = 6.5
	add_child(light)


func _show_info(message: String) -> void:
	_info_text = message
	_info_left = 2.0
	if is_instance_valid(_hint_label):
		_hint_label.text = message


func _make_label(parent: Control, text_value: String, size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.95, 0.98, 0.96))
	parent.add_child(label)
	return label


func _create_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	if room_mode != "trial":
		var room_title := "R03 · ПАНЦИРНЫЙ ПРОХОД" if room_mode == "r03" else ("R04 · ЗАЛ ЯДРА" if room_mode == "r04" else ("R06 · КАМЕННЫЙ ПРЕСС" if room_mode == "r06" else ("R07 · СТРАЖ ВЫХОДА" if room_mode == "r07" else "R05 · СМЕШАННЫЙ ЗАЛ")))
		_route_label = _make_label(root, room_title, 23)
		_route_label.anchor_left = 1.0
		_route_label.anchor_right = 1.0
		_route_label.offset_left = -340
		_route_label.offset_right = -18
		_route_label.offset_top = 24
	var status := ColorRect.new()
	status.color = Color(0.025, 0.08, 0.10, 0.82)
	status.position = Vector2(18, 16)
	status.size = Vector2(455, 128)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	_health_label = _make_label(status, "", 24)
	_health_label.position = Vector2(12, 6)
	for index in 2:
		var slot_label := _make_label(status, "", 18)
		slot_label.position = Vector2(12, 42 + index * 33)
		_slot_labels.append(slot_label)
	var crosshair := _make_label(root, "+", 26)
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -8
	crosshair.offset_top = -16
	var hint_back := ColorRect.new()
	hint_back.color = Color(0.025, 0.08, 0.10, 0.78)
	hint_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_back.anchor_left = 0.11
	hint_back.anchor_right = 0.89
	hint_back.anchor_top = 1.0
	hint_back.anchor_bottom = 1.0
	hint_back.offset_top = -77
	hint_back.offset_bottom = -15
	root.add_child(hint_back)
	_hint_label = _make_label(root, "", 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.12
	_hint_label.anchor_right = 0.88
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -70
	_hint_label.offset_bottom = -20
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.anchor_left = 0.5
	_progress.anchor_right = 0.5
	_progress.anchor_top = 1.0
	_progress.anchor_bottom = 1.0
	_progress.offset_left = -150
	_progress.offset_right = 150
	_progress.offset_top = -98
	_progress.offset_bottom = -82
	_progress.visible = false
	root.add_child(_progress)
	_card_panel = ColorRect.new()
	_card_panel.color = Color(0.05, 0.14, 0.16, 0.86)
	_card_panel.anchor_left = 0.5
	_card_panel.anchor_right = 0.5
	_card_panel.offset_left = -250
	_card_panel.offset_right = 250
	_card_panel.offset_top = 105
	_card_panel.offset_bottom = 185
	_card_panel.visible = false
	_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card_panel)
	_card_label = _make_label(_card_panel, "", 20)
	_card_label.position = Vector2(12, 10)
	_card_label.size = Vector2(476, 68)
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_panel = _overlay(root, "ПАУЗА\nEscape — продолжить")
	_pause_panel.visible = false
	_collection_panel = _overlay(root, "КОЛЛЕКЦИЯ\nВыбери слот, затем изученный навык")
	_collection_panel.visible = false
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -265
	box.offset_right = 265
	box.offset_top = -135
	box.offset_bottom = 245
	_collection_panel.add_child(box)
	for slot in [1, 2]:
		var button := Button.new()
		button.custom_minimum_size.y = 38
		button.pressed.connect(_select_slot.bind(slot))
		box.add_child(button)
		_collection_slots.append(button)
	for id: StringName in ABILITIES:
		var card := Button.new()
		card.custom_minimum_size.y = 62
		card.pressed.connect(_equip_card.bind(id))
		box.add_child(card)
		_collection_cards.append(card)
	var clear_button := Button.new()
	clear_button.text = "Очистить выбранный слот"
	clear_button.pressed.connect(_equip_card.bind(&""))
	box.add_child(clear_button)
	var close_button := Button.new()
	close_button.text = "Закрыть (Tab / Escape)"
	close_button.pressed.connect(_close_collection)
	box.add_child(close_button)
	_end_panel = _overlay(root, "")
	_end_panel.visible = false
	var end_box := VBoxContainer.new()
	end_box.anchor_left = 0.5
	end_box.anchor_right = 0.5
	end_box.anchor_top = 0.5
	end_box.anchor_bottom = 0.5
	end_box.offset_left = -200
	end_box.offset_right = 200
	end_box.offset_top = -55
	end_box.offset_bottom = 110
	_end_panel.add_child(end_box)
	_end_title = _make_label(end_box, "", 28)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var restart_button := Button.new()
	restart_button.text = "Повторить испытание (R)" if room_mode == "trial" else "Повторить зал (R)"
	restart_button.custom_minimum_size.y = 48
	restart_button.pressed.connect(_restart)
	end_box.add_child(restart_button)
	if room_mode == "r05" or room_mode == "r06":
		_continue_button = Button.new()
		_continue_button.text = "Дальше: Каменный пресс" if room_mode == "r05" else "Дальше: Страж выхода"
		_continue_button.custom_minimum_size.y = 48
		_continue_button.pressed.connect(_enter_r06 if room_mode == "r05" else _enter_r07)
		end_box.add_child(_continue_button)


func _overlay(root: Control, heading: String) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.04, 0.07, 0.96)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	if not heading.is_empty():
		var title := _make_label(panel, heading, 26)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.anchor_left = 0.2
		title.anchor_right = 0.8
		title.anchor_top = 0.5
		title.anchor_bottom = 0.5
		title.offset_top = -240
		title.offset_bottom = -160
	return panel

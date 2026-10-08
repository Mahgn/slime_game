extends SlimeLevelWorkspace
class_name SlimeKeepersRun

const LAYOUT = preload("res://scripts/keepers/keepers_run_layout.gd")
const ROOM_GEOMETRY = preload("res://scripts/keepers/keepers_run_geometry.gd")
const RUN_HUD = preload("res://scripts/keepers/keepers_run_hud.gd")
const PLAYER_SCENE = preload("res://scenes/player/slime_player.tscn")
const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const ARMORER_SCENE = preload("res://scenes/enemies/armorer.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const SOURCE_SCENE = preload("res://scenes/interactables/absorb_source.tscn")
const RUN_SCENE := "res://scenes/keepers/keepers_run.tscn"
const SPAWN_POINT := Vector3(0, 0.045, 4.8)
const CAMERA_SIZE := 14.3
const SPAWN_POINTS := [Vector3(-3.4, 0.05, -2.5), Vector3(3.4, 0.05, -2.5), Vector3(0, 0.05, -3.6)]

var rooms := LAYOUT.rooms()
var room_id := "entry"
var room_root: Node3D
var geometry: Node3D
var hud: SlimeKeepersRunHUD
var cleared: Dictionary = {}
var visited: Dictionary = {}
var secrets_found: Dictionary = {}
var rewards_claimed: Dictionary = {}
var room_sources: Dictionary = {}
var came_from: Dictionary = {}
var elapsed_seconds := 0.0
var finished := false
var victory := false
var wave_index := 0
var interaction_hint := ""
var _wave_delay := -1.0
var _entry_snapshot: Dictionary = {}
var _transitioning := false
var _door_labels: Array[Label3D] = []
var _wave_markers: Node3D
var _door_release := true
var _room_clock := 0.0
var room_seconds: Dictionary = {}
var kills := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_meta(&"isometric_dressing_owned", true)
	_create_combat()
	_build_ui()
	get_node("HUD").get_child(0).hide()
	get_node("HUD").get_child(1).hide()
	hud = RUN_HUD.new()
	add_child(hud)
	hud.setup(self)
	player.died.connect(_on_player_died)
	player.info_requested.connect(hud.show_notice)
	_enter_room("entry", "", false)


func _create_combat() -> void:
	combat = SlimeCombatRuntime.new()
	combat.name = "CombatRuntime"
	add_child(combat)
	combat.bind_player(player)


func current_room() -> Dictionary:
	return rooms[room_id]


func alive_enemies() -> Array:
	var result: Array = []
	if not is_instance_valid(room_root):
		return result
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if room_root.is_ancestor_of(enemy) and enemy.is_alive():
			result.append(enemy)
	return result


func room_is_safe() -> bool:
	return cleared.has(room_id) and combat.can_change_loadout() and player.is_alive() and player._action == &""


func _physics_process(delta: float) -> void:
	if get_tree().paused or finished or _transitioning:
		return
	elapsed_seconds += delta
	_room_clock += delta
	_update_camera_center()
	if not Input.is_action_pressed(&"interact"):
		_door_release = false
	if player.position.y < -3.5:
		# Low visible front parapets can be jumped; no invisible tall blockers.
		player.apply_environment_damage(10)
		if player.is_alive():
			_reset_position(SPAWN_POINT)
	if not player.is_alive():
		return
	for enemy in alive_enemies():
		if enemy.position.y < -3.5:
			enemy.position = Vector3(0, 0.05, -2.5)
			enemy.velocity = Vector3.ZERO
	if not cleared.has(room_id):
		_update_encounter(delta)
	_update_door_labels()
	_update_interaction()
	if not _door_release and Input.is_action_just_pressed(&"interact"):
		try_interact()


func _update_encounter(delta: float) -> void:
	var waves: Array = current_room().get("waves", [])
	if wave_index == 0 and _wave_delay < 0.0:
		# Entry apron gives a moment to read the room; approaching starts combat.
		if player.position.z < 3.6:
			_prepare_wave()
		return
	if _wave_delay >= 0.0:
		_wave_delay -= delta
		if _wave_delay <= 0.0:
			_spawn_wave(waves[wave_index])
		return
	if alive_enemies().is_empty():
		if wave_index < waves.size():
			_prepare_wave()
		else:
			cleared[room_id] = true
			hud.show_notice("Комната очищена. Можно поглотить следы и выбрать путь.")


func _prepare_wave() -> void:
	_wave_delay = 1.2
	_wave_markers = Node3D.new()
	_wave_markers.name = "EnemyArrivalWarnings"
	room_root.add_child(_wave_markers)
	var count: int = current_room().waves[wave_index].size()
	for i in count:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.62
		mesh.outer_radius = 0.68
		mesh.rings = 16
		mesh.ring_segments = 6
		ring.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("e9a975")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
		ring.position = SPAWN_POINTS[i]
		ring.position.y = 0.06
		_wave_markers.add_child(ring)


func _spawn_wave(kinds: Array) -> void:
	_wave_delay = -1.0
	if is_instance_valid(_wave_markers):
		_wave_markers.queue_free()
	for i in kinds.size():
		var enemy: Node3D
		match String(kinds[i]):
			"spitter": enemy = SPITTER_SCENE.instantiate()
			"armorer": enemy = ARMORER_SCENE.instantiate()
			"sprout": enemy = SPROUT_SCENE.instantiate()
			"guardian": enemy = ExitGuardian.new()
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		enemy.position = SPAWN_POINTS[i]
		room_root.add_child(enemy)
		combat.bind_enemy(enemy)
		if enemy is ExitGuardian:
			enemy.died.connect(_count_kill)
		else:
			enemy.died.connect(func(_actor: Node3D, _ability: StringName, _at: Vector3) -> void: _count_kill())
	wave_index += 1


func _count_kill() -> void:
	kills += 1


func _near(at: Vector3, distance: float = 1.1) -> bool:
	var offset := player.position - at
	return player.is_on_floor() and Vector2(offset.x, offset.z).length() < distance and absf(offset.y) < 0.25


func _update_interaction() -> void:
	interaction_hint = "Подойди к арке, чтобы выбрать путь" if room_is_safe() else "Держись свободного центра и уходи с линии атаки"
	if is_instance_valid(player.get_nearest_absorb_source()):
		interaction_hint = "Удерживай E — поглотить навык · Стой на месте"
		return
	if _near(Vector3.ZERO) and current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id):
		interaction_hint = "E — принять ядро · Откроется второй слот (Q)"
		return
	var exits: Array = current_room().exits
	for i in exits.size():
		if _near(geometry.get_door_position(i, exits.size())):
			interaction_hint = "E — " + String(rooms[exits[i]].title) if room_is_safe() else "Путь запечатан, пока в комнате остаются враги"
	if room_id == "summit" and _near(geometry.get_door_position(0, 1)):
		interaction_hint = "E — подняться к своим" if room_is_safe() else "Путь откроется после победы над Стражем"
	if came_from.has(room_id) and _near(geometry.get_back_position()):
		interaction_hint = "E — вернуться: " + String(rooms[came_from[room_id]].title) if room_is_safe() else "Сначала закончи бой в этой комнате"
	if current_room().has("secret_exit") and _near(geometry.get_secret_position(), 1.25):
		interaction_hint = "E — проверить щель в кладке" if room_is_safe() else "Из щели тянет холодом. Исследуй её после боя"


func try_interact() -> bool:
	if finished or _transitioning or get_tree().paused or not room_is_safe():
		return false
	# E near an absorb source belongs to the existing hold-to-absorb action.
	if is_instance_valid(player.get_nearest_absorb_source()):
		return false
	if current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id) and _near(Vector3.ZERO):
		if player.unlock_second_slot():
			rewards_claimed[room_id] = true
			geometry.set_reward_visible(false)
			hud.show_notice("Ядро принято. Второй навык — Q. Выбрать пару можно по Tab.")
			return true
	var exits: Array = current_room().exits
	for i in exits.size():
		if _near(geometry.get_door_position(i, exits.size())):
			request_travel(exits[i])
			return true
	if room_id == "summit" and _near(geometry.get_door_position(0, 1)):
		_finish_run()
		return true
	if current_room().has("secret_exit") and _near(geometry.get_secret_position(), 1.25):
		request_travel(current_room().secret_exit)
		return true
	if came_from.has(room_id) and _near(geometry.get_back_position()):
		request_travel(came_from[room_id])
		return true
	return false


func request_travel(destination: String) -> bool:
	if _transitioning or finished or get_tree().paused or not room_is_safe() or not rooms.has(destination):
		return false
	var allowed: Array = current_room().exits.duplicate()
	if current_room().has("secret_exit"):
		allowed.append(current_room().secret_exit)
	if came_from.has(room_id):
		allowed.append(came_from[room_id])
	if not allowed.has(destination):
		return false
	_transitioning = true
	# Prevent a same-tick mouse action from starting after the travel request.
	player.set_physics_process(false)
	_save_sources()
	room_seconds[room_id] = float(room_seconds.get(room_id, 0.0)) + _room_clock
	_enter_room.call_deferred(destination, room_id, false)
	return true


func _save_sources() -> void:
	var sources: Array = []
	var seen: Dictionary = {}
	for source in combat.get_children():
		if source is AbsorbSource and not source.is_claimed() and not player.has_learned(source.ability_id) and not seen.has(source.ability_id):
			sources.append({"ability": source.ability_id, "position": source.position})
			seen[source.ability_id] = true
	room_sources[room_id] = sources


func _enter_room(destination: String, origin: String, retry: bool) -> void:
	_transitioning = true
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	player.presentation.room_cutaway = null
	for node in combat.get_children():
		node.free()
	if is_instance_valid(room_root):
		room_root.free()
	room_id = destination
	_room_clock = 0.0
	wave_index = 0
	_wave_delay = -1.0
	_door_release = true
	if origin != "" and not came_from.has(room_id):
		came_from[room_id] = origin
	visited[room_id] = true
	if current_room().get("secret", false):
		secrets_found[room_id] = true
	if current_room().waves.is_empty():
		cleared[room_id] = true
	room_root = Node3D.new()
	room_root.name = "ActiveRoom"
	room_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(room_root)
	geometry = ROOM_GEOMETRY.new()
	room_root.add_child(geometry)
	geometry.build_room(current_room().merged({"id": room_id}, true))
	player.presentation.room_cutaway = geometry.cutaway
	_build_door_labels()
	player.health = SlimeController.MAX_HEALTH
	player._cooldowns.clear()
	player._hurt_protection_left = 0.0
	player.health_changed.emit(player.health, SlimeController.MAX_HEALTH)
	if not retry:
		_entry_snapshot = {"learned": player.learned_abilities.duplicate(), "slots": player.unlocked_slots, "first": player.equipped_ability, "second": player.second_slot_ability, "rewards": rewards_claimed.duplicate(), "kills": kills, "cleared": cleared.has(room_id), "sources": room_sources.get(room_id, []).duplicate(true)}
	for source_data: Dictionary in room_sources.get(room_id, []):
		if not player.has_learned(source_data.ability):
			_add_source(source_data.ability, source_data.position)
	if current_room().get("reward", "") == "shell" and not player.has_learned(&"elastic_shell") and room_sources.get(room_id, []).is_empty():
		_add_source(&"elastic_shell", Vector3.ZERO)
	geometry.set_reward_visible(current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id))
	var spawn := SPAWN_POINT
	# Returning from a secret puts the player at its entrance, never in the wall.
	if current_room().get("secret_exit", "") == origin:
		spawn = geometry.get_secret_position() + Vector3(1.2, 0.045, 0)
	elif current_room().exits.has(origin):
		spawn = geometry.get_door_position(current_room().exits.find(origin), current_room().exits.size()) + Vector3(0, 0.045, 1.4)
	_reset_position(spawn)
	combat._safe_left = 0.5
	player.set_physics_process(true)
	_transitioning = false
	if current_room().get("secret", false):
		hud.show_notice("Тайное место найдено. " + String(current_room().lore))


func _add_source(ability: StringName, at: Vector3) -> void:
	var source := SOURCE_SCENE.instantiate() as AbsorbSource
	source.ability_id = ability
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	combat.add_child(source)
	source.position = at


func _reset_position(at: Vector3) -> void:
	player.position = at
	player.velocity = Vector3.ZERO
	player.clear_action_buffer()
	player._ground_trail.clear_for_room_change()
	player._whip_visual._clear_contact()
	_update_camera_center()
	player.presentation.zoom_target = CAMERA_SIZE
	player.presentation.camera.size = CAMERA_SIZE
	player.presentation._update_camera(0.0)


func _update_camera_center() -> void:
	set_meta(&"isometric_camera_center", Vector3(clampf(player.position.x * 0.5, -2.5, 2.5), 0.6, clampf(player.position.z * 0.5, -2.4, 2.4)))


func _build_door_labels() -> void:
	_door_labels.clear()
	var exits: Array = current_room().exits
	for i in exits.size():
		var next: Dictionary = rooms[exits[i]]
		var caption: String = next.get("route_hint", next.title)
		_door_label(caption, geometry.get_door_position(i, exits.size()))
	if room_id == "summit":
		_door_label("К свету", geometry.get_door_position(0, 1))
	if came_from.has(room_id):
		_door_label("Назад", geometry.get_back_position())


func _door_label(caption: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = caption
	label.position = at + Vector3(0, 1.5, 0.2)
	label.font_size = 32
	label.pixel_size = 0.010
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	room_root.add_child(label)
	_door_labels.append(label)


func _update_door_labels() -> void:
	var safe := room_is_safe()
	for label in _door_labels:
		label.modulate = Color("c5e0bc") if safe else Color("bf9690")


func _on_player_died() -> void:
	finished = true
	victory = false
	player.clear_action_buffer()
	get_tree().paused = true
	hud.show_ending(false)


func _finish_run() -> void:
	finished = true
	victory = true
	room_seconds[room_id] = float(room_seconds.get(room_id, 0.0)) + _room_clock
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	get_tree().paused = true
	hud.show_ending(true)


func retry_room() -> void:
	if not finished or victory or _transitioning:
		return
	_transitioning = true
	_retry_room_deferred.call_deferred()


func _retry_room_deferred() -> void:
	var snapshot := _entry_snapshot.duplicate(true)
	combat.free()
	player.free()
	player = PLAYER_SCENE.instantiate() as SlimeController
	player.name = "SlimePlayer"
	player.learned_abilities = snapshot.learned.duplicate()
	player.unlocked_slots = snapshot.slots
	player.equipped_ability = snapshot.first
	player.second_slot_ability = snapshot.second
	add_child(player)
	player.died.connect(_on_player_died)
	player.info_requested.connect(hud.show_notice)
	_create_combat()
	hud.rebind_runtime()
	rewards_claimed = snapshot.rewards.duplicate()
	kills = snapshot.kills
	if snapshot.cleared:
		cleared[room_id] = true
	else:
		cleared.erase(room_id)
	room_sources[room_id] = snapshot.sources.duplicate(true)
	finished = false
	victory = false
	_pause_panel.hide()
	hud.hide_ending()
	get_tree().paused = false
	_enter_room(room_id, "", true)


func restart_run() -> void:
	get_tree().paused = false
	var result := get_tree().change_scene_to_file(RUN_SCENE)
	if result != OK:
		hud.show_notice("Не удалось начать заново: %d" % result)


func return_to_menu() -> void:
	_pause_panel._go_to_menu()


func _input(event: InputEvent) -> void:
	if finished or not is_instance_valid(hud):
		return
	if (event.is_action_pressed(&"pause") or event.is_action_pressed(&"open_loadout")) and hud.loadout_open:
		hud.close_loadout()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"open_loadout") and not get_tree().paused:
		hud.toggle_loadout()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _notification(what: int) -> void:
	if finished:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud) and hud.loadout_open:
		hud.close_loadout()
	super._notification(what)

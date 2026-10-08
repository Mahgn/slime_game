extends SlimeLevelWorkspace
class_name SlimeKeepersWorld

const LAYOUT = preload("res://scripts/keepers/keepers_world_layout.gd")
const WORLD_GEOMETRY = preload("res://scripts/keepers/keepers_world_geometry.gd")
const WORLD_COMBAT = preload("res://scripts/keepers/keepers_world_combat.gd")
const WORLD_HUD = preload("res://scripts/keepers/keepers_world_hud.gd")
const PLAYER_SCENE = preload("res://scenes/player/slime_player.tscn")
const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const ARMORER_SCENE = preload("res://scenes/enemies/armorer.tscn")
const SPROUT_SCENE = preload("res://scenes/enemies/stone_sprout.tscn")
const SOURCE_SCENE = preload("res://scenes/interactables/absorb_source.tscn")
const WORLD_SPITTER = preload("res://scripts/keepers/keepers_world_spitter.gd")
const WORLD_ENEMY = preload("res://scripts/keepers/keepers_world_enemy.gd")
const WORLD_GUARDIAN = preload("res://scripts/keepers/keepers_world_guardian.gd")
const WORLD_NAVIGATION = preload("res://scripts/keepers/keepers_world_navigation.gd")
const RUN_SCENE := "res://scenes/keepers/keepers_world.tscn"
const CAMERA_SIZE := 16.0

@export var layout_script: Script = LAYOUT
@export var geometry_script: Script = WORLD_GEOMETRY

var rooms: Dictionary = LAYOUT.rooms()
var connections: Array = LAYOUT.connections()
var room_id := "entry"
var room_roots: Dictionary = {}
var geometry: Node3D
var navigation: Node
var hud: SlimeKeepersRunHUD
var cleared: Dictionary = {}
var visited: Dictionary = {}
var secrets_found: Dictionary = {}
var rewards_claimed: Dictionary = {}
var encounters: Dictionary = {}
var entry_snapshots: Dictionary = {}
var elapsed_seconds := 0.0
var finished := false
var victory := false
var wave_index := 0
var interaction_hint := ""
var kills := 0
var _transitioning := false
var _ground_y := 0.0
var _last_supported := Vector3.ZERO
var _visibility_clock := 0.0
var _markers: Dictionary = {}


func _ready() -> void:
	_transitioning = true
	rooms = layout_script.rooms()
	connections = layout_script.connections()
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_meta(&"isometric_dressing_owned", true)
	geometry = geometry_script.new()
	geometry.name = "ConnectedArchitecture"
	add_child(geometry)
	geometry.build_world(rooms, connections)
	for id: String in rooms:
		var actors := Node3D.new()
		actors.name = "Encounter_" + id
		actors.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(actors)
		room_roots[id] = actors
		encounters[id] = {"wave": 0, "delay": -1.0, "kills": 0}
		if rooms[id].waves.is_empty():
			cleared[id] = true
	combat = WORLD_COMBAT.new()
	combat.name = "CombatRuntime"
	combat.route = self
	add_child(combat)
	combat.bind_player(player)
	_build_ui()
	get_node("HUD").get_child(0).hide()
	get_node("HUD").get_child(1).hide()
	hud = WORLD_HUD.new()
	add_child(hud)
	hud.setup(self)
	_bind_player()
	for id: String in rooms:
		if rooms[id].get("reward", "") == "shell":
			_add_source(id, &"elastic_shell", rooms[id].get("reward_position", rooms[id].center))
	player.presentation.room_cutaway = geometry.cutaway
	_reset_position(rooms.entry.spawn)
	_visit_room("entry")
	_update_interaction()
	_update_visibility()
	navigation = WORLD_NAVIGATION.new()
	navigation.name = "AuthoredWalkRoutes"
	add_child(navigation)
	# Static collision must have reached the physics server before ray checks.
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation.build(rooms, connections, get_world_3d())
	_transitioning = false


func _bind_player() -> void:
	player.died.connect(_on_player_died)
	player.info_requested.connect(hud.show_notice)


func current_room() -> Dictionary:
	return rooms[room_id]


func alive_enemies(id: String = "") -> Array:
	var result: Array = []
	var keys: Array = [id] if not id.is_empty() else room_roots.keys()
	for key: String in keys:
		for actor in room_roots[key].get_children():
			if actor.has_method("is_alive") and actor.is_alive():
				if not id.is_empty() or actor.global_position.distance_to(player.global_position) < 16.0:
					result.append(actor)
	return result


func room_is_safe() -> bool:
	return cleared.has(room_id) and combat.can_change_loadout() and player.is_alive() and player._action == &""


func _physics_process(delta: float) -> void:
	if get_tree().paused or finished or _transitioning:
		return
	elapsed_seconds += delta
	if player.is_on_floor():
		_ground_y = player.global_position.y
		_last_supported = player.global_position
	_update_camera_center()
	if player.global_position.y < -4.0:
		player.apply_environment_damage(10)
		if player.is_alive():
			_reset_position(rooms[room_id].spawn)
	if not player.is_alive():
		return
	var located := _locate_room(player.global_position)
	if not located.is_empty() and (located != room_id or not visited.has(located)):
		_visit_room(located)
	for id: String in room_roots:
		for enemy in alive_enemies(id):
			# Sleeping actors keep their instance, HP, phase and status durations.
			var awake: bool = enemy.global_position.distance_to(player.global_position) < 24.0
			enemy.process_mode = Node.PROCESS_MODE_PAUSABLE if awake else Node.PROCESS_MODE_DISABLED
			if enemy.global_position.y < -4.0:
				enemy.global_position = rooms[id].enemy_spawns[0]
				enemy.velocity = Vector3.ZERO
		if not cleared.has(id) and visited.has(id):
			_update_encounter(id, delta, located == id)
	wave_index = int(encounters[room_id].wave)
	_update_interaction()
	if Input.is_action_just_pressed(&"interact"):
		try_interact()
	_visibility_clock -= delta
	if _visibility_clock <= 0.0:
		_visibility_clock = 0.3
		_update_visibility()


func _visit_room(id: String) -> void:
	room_id = id
	visited[id] = true
	wave_index = int(encounters[id].wave)
	entry_snapshots[id] = {
		"learned": player.learned_abilities.duplicate(), "slots": player.unlocked_slots,
		"first": player.equipped_ability, "second": player.second_slot_ability,
		"claimed": rewards_claimed.has(id), "cleared": cleared.has(id),
		"sources": _sources_for(id), "kills": int(encounters[id].kills)
	}
	if rooms[id].get("secret", false) and not secrets_found.has(id):
		secrets_found[id] = true
		hud.show_notice("Тайное место найдено. " + String(rooms[id].get("lore", "")))
	# No position, velocity, health, cooldown, scene or actor mutation here.


func _locate_room(at: Vector3) -> String:
	for id: String in rooms:
		var relative: Vector3 = at - rooms[id].center
		if Geometry2D.is_point_in_polygon(Vector2(relative.x, relative.z), rooms[id].footprint):
			return id
	return ""


func _update_encounter(id: String, delta: float, inside: bool) -> void:
	var state: Dictionary = encounters[id]
	var waves: Array = rooms[id].waves
	if not alive_enemies(id).is_empty():
		return
	if int(state.wave) >= waves.size():
		cleared[id] = true
		if room_id == id:
			hud.show_notice("Здесь стало тихо. Можно осмотреть закоулки или вернуться назад.")
		return
	if not inside:
		return
	if float(state.delay) < 0.0:
		_prepare_wave(id)
	else:
		state.delay = float(state.delay) - delta
		if float(state.delay) <= 0.0:
			_spawn_wave(id)


func _prepare_wave(id: String) -> void:
	encounters[id].delay = 1.2
	var markers := Node3D.new()
	markers.name = "ArrivalWarnings"
	room_roots[id].add_child(markers)
	_markers[id] = markers
	var count: int = rooms[id].waves[int(encounters[id].wave)].size()
	for index in count:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.62
		mesh.outer_radius = 0.68
		mesh.rings = 16
		mesh.ring_segments = 6
		ring.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("e9a975")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		markers.add_child(ring)
		ring.global_position = rooms[id].enemy_spawns[index] + Vector3.UP * 0.025


func _spawn_wave(id: String) -> void:
	var state: Dictionary = encounters[id]
	state.delay = -1.0
	if _markers.has(id) and is_instance_valid(_markers[id]):
		_markers[id].queue_free()
	_markers.erase(id)
	var kinds: Array = rooms[id].waves[int(state.wave)]
	for index in kinds.size():
		var enemy: Node3D
		match String(kinds[index]):
			"spitter":
				enemy = SPITTER_SCENE.instantiate()
				enemy.set_script(WORLD_SPITTER)
			"armorer", "sprout":
				enemy = ARMORER_SCENE.instantiate() if kinds[index] == "armorer" else SPROUT_SCENE.instantiate()
				enemy.set_script(WORLD_ENEMY)
				enemy.kind = String(kinds[index])
			"guardian": enemy = WORLD_GUARDIAN.new()
		enemy.movement_guide = navigation.steer
		enemy.set_meta(&"home_room", id)
		room_roots[id].add_child(enemy)
		enemy.global_position = rooms[id].enemy_spawns[index]
		combat.bind_enemy(enemy)
		if enemy is ExitGuardian:
			enemy.died.connect(_count_kill.bind(id))
		else:
			enemy.died.connect(func(_actor: Node3D, _ability: StringName, _at: Vector3) -> void: _count_kill(id))
	state.wave = int(state.wave) + 1


func _count_kill(id: String) -> void:
	kills += 1
	encounters[id].kills = int(encounters[id].kills) + 1


func _update_camera_center() -> void:
	set_meta(&"isometric_camera_center", Vector3(player.global_position.x, _ground_y + 0.6, player.global_position.z))


func _update_visibility() -> void:
	# Frustum/distance culling only. Physics, encounter state and identity persist.
	for id: String in geometry.room_nodes:
		geometry.room_nodes[id].visible = player.global_position.distance_to(rooms[id].center) < 44.0


func _update_interaction() -> void:
	interaction_hint = "Проходы открыты — иди дальше или возвращайся назад" if room_is_safe() else "Можно отступить в коридор. Препятствия защищают от плевков"
	if is_instance_valid(player.get_nearest_absorb_source()):
		interaction_hint = "Удерживай E — поглотить навык · Стой на месте"
		return
	var reward_at: Vector3 = current_room().get("reward_position", current_room().center)
	if current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id) and _near(reward_at, 1.4):
		interaction_hint = "E — принять ядро · Откроется второй слот (Q)"
	if room_id == "summit" and _near(current_room().exit_point, 1.5):
		interaction_hint = "E — подняться к своим" if cleared.has("summit") else "Путь к своим откроется после победы над Стражем"


func _near(at: Vector3, radius: float) -> bool:
	return player.is_on_floor() and player.global_position.distance_to(at) < radius


func try_interact() -> bool:
	if finished or _transitioning or get_tree().paused or not player.is_alive():
		return false
	if is_instance_valid(player.get_nearest_absorb_source()):
		return false
	var reward_at: Vector3 = current_room().get("reward_position", current_room().center)
	if current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id) and _near(reward_at, 1.4):
		if player.unlock_second_slot():
			rewards_claimed[room_id] = true
			geometry.set_world_reward_visible(room_id, false)
			hud.show_notice("Ядро принято. Второй навык — Q. Выбрать пару можно по Tab.")
			return true
	if room_id == "summit" and cleared.has("summit") and _near(current_room().exit_point, 1.5):
		finished = true
		victory = true
		player.cancel_absorb_for_pause()
		player.clear_action_buffer()
		hud.show_ending(true)
		return true
	return false


func _sources_for(id: String) -> Array:
	var result: Array = []
	for source in combat.get_children():
		if source is AbsorbSource and source.get_meta(&"home_room", "") == id and not source.is_claimed():
			result.append({"ability": source.ability_id, "position": source.global_position})
	return result


func _add_source(id: String, ability: StringName, at: Vector3) -> void:
	var source := SOURCE_SCENE.instantiate() as AbsorbSource
	source.ability_id = ability
	source.set_meta(&"home_room", id)
	combat.add_child(source)
	source.global_position = at


func _on_player_died() -> void:
	finished = true
	victory = false
	player.clear_action_buffer()
	hud.show_ending(false)


func retry_room() -> void:
	if not finished or victory or _transitioning:
		return
	_transitioning = true
	_retry_room_deferred.call_deferred()


func _retry_room_deferred() -> void:
	var snapshot: Dictionary = entry_snapshots[room_id]
	for node in combat.get_children():
		if not node is AbsorbSource or node.get_meta(&"home_room", "") == room_id:
			node.free()
	for node in room_roots[room_id].get_children():
		node.free()
	_markers.erase(room_id)
	kills -= int(encounters[room_id].kills)
	encounters[room_id] = {"wave": 0, "delay": -1.0, "kills": 0}
	if bool(snapshot.cleared):
		cleared[room_id] = true
		encounters[room_id].kills = int(snapshot.kills)
		kills += int(snapshot.kills)
	else:
		cleared.erase(room_id)
	if bool(snapshot.claimed):
		rewards_claimed[room_id] = true
	else:
		rewards_claimed.erase(room_id)
	geometry.set_world_reward_visible(room_id, current_room().get("reward", "") == "core" and not rewards_claimed.has(room_id))
	player.free()
	player = PLAYER_SCENE.instantiate() as SlimeController
	player.name = "SlimePlayer"
	player.learned_abilities = snapshot.learned.duplicate()
	player.unlocked_slots = snapshot.slots
	player.equipped_ability = snapshot.first
	player.second_slot_ability = snapshot.second
	add_child(player)
	combat.player = null
	combat.bind_player(player)
	combat._safe_left = 0.5
	for id: String in room_roots:
		for enemy in alive_enemies(id):
			enemy.player_target = player
	hud.rebind_runtime()
	_bind_player()
	for source: Dictionary in snapshot.sources:
		_add_source(room_id, source.ability, source.position)
	# A pursuer can die outside its home room. If its source was claimed after
	# this entry snapshot, rolling back the skill must also restore that source.
	for source in combat.get_children():
		if source is AbsorbSource and source.is_claimed() and not player.has_learned(source.ability_id):
			source._claimed = false
			source._focused = false
			source.visible = true
			source.add_to_group(&"absorb_sources")
			source.set_process(true)
	player.presentation.room_cutaway = geometry.cutaway
	finished = false
	victory = false
	_pause_panel.hide()
	hud.hide_ending()
	_reset_position(current_room().spawn)
	get_tree().paused = false
	_transitioning = false


func _reset_position(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	_ground_y = at.y
	_last_supported = at
	player.clear_action_buffer()
	player._ground_trail.clear_for_room_change()
	player._whip_visual._clear_contact()
	_update_camera_center()
	player.presentation.zoom_target = CAMERA_SIZE
	player.presentation.camera.size = CAMERA_SIZE
	player.presentation._update_camera(0.0)


func restart_run() -> void:
	get_tree().paused = false
	var result := get_tree().change_scene_to_file(scene_file_path)
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

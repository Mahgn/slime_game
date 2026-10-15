extends SlimeKeepersWorld

const DUNGEON_LAYOUT: Script = preload("res://scripts/dungeon/dungeon_layout.gd")
const DUNGEON_GEOMETRY: Script = preload("res://scripts/dungeon/dungeon_geometry.gd")
const DUNGEON_COMBAT: Script = preload("res://scripts/dungeon/dungeon_combat.gd")
const DUNGEON_HUD: Script = preload("res://scripts/dungeon/dungeon_hud.gd")
const CREATURE: Script = preload("res://scripts/dungeon/dungeon_creature.gd")
const GATE: Script = preload("res://scripts/dungeon/dungeon_gate.gd")
const MEMBRANE: Script = preload("res://scripts/dungeon/dungeon_membrane.gd")
const INK_STYLE: Script = preload("res://scripts/keepers/keepers_ink_style.gd")
const RENDER_WARMUP: Script = preload("res://scripts/keepers/keepers_render_warmup.gd")
const DUNGEON_SCENE: String = "res://scenes/dungeon/dungeon_route.tscn"

var attempt_index: int = 0
var gates: Array[Node3D] = []
var membrane: StaticBody3D
var ink_style: SlimeKeepersInkStyle
var known_regions: Array = []


func _enter_tree() -> void:
	# The authored player is a scene child: its _ready runs before this root's.
	set_meta(&"camera_quarter_turns", true)


func _ready() -> void:
	attempt_index = int(get_tree().get_meta(&"dungeon_attempt_index",0))
	known_regions = get_tree().get_meta(&"dungeon_known_regions",[]).duplicate()
	layout_script = DUNGEON_LAYOUT
	geometry_script = _geometry_for_route()
	combat_script = DUNGEON_COMBAT
	hud_script = DUNGEON_HUD
	await super._ready()
	rooms.cistern.subtitle = "Вода питает гряды и гнёзда. Течение %s; сухие мостки безопасны. Клей удержит привод." % ["вправо" if attempt_index%2==0 else "влево"]
	_transitioning = true
	for id: String in rooms:
		if not rooms[id].waves.is_empty():
			cleared.erase(id)
			encounters[id].wave = 0
			_spawn_wave(id)
	var release_gate: Node3D = _add_gate(Vector3(0,0,-0.8 if attempt_index%2==0 else 1.2),0.0)
	var water_gate: Node3D = _add_gate(Vector3(12,0,-13.3),1.4)
	_add_gate(Vector3(-4.3 if attempt_index%2==0 else 4.3,0,-45),2.2)
	release_gate.name = "ReleaseGate"
	water_gate.name = "WaterDrive"
	membrane = MEMBRANE.new() as StaticBody3D
	membrane.name = "ServiceMembrane"
	membrane.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(membrane)
	membrane.global_position = Vector3(0.5,0,-18)
	ink_style = INK_STYLE.new() as SlimeKeepersInkStyle
	ink_style.name = "InkStyle"
	ink_style.route = self
	add_child(ink_style)
	var original_mode: int = player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await RENDER_WARMUP.prepare(self)
	player.process_mode = original_mode
	_transitioning = false
	print("DUNGEON_READY attempt=%d rooms=%d regions=5" % [attempt_index+1,rooms.size()])
	hud.show_notice("Испытание началось. Найди дорогу к своим.\nПосле смерти слуги восстановят препятствия." if attempt_index==0 else "Попытка %d. Слуги восстановили подземелье.\nПриводы переставлены, приёмы собираются заново." % [attempt_index+1])


func _geometry_for_route() -> Script:
	return DUNGEON_GEOMETRY


func _add_gate(at: Vector3, offset: float) -> Node3D:
	var gate: Node3D = GATE.new() as Node3D
	gate.set("phase_offset",offset)
	add_child(gate)
	gate.global_position = at
	gates.append(gate)
	return gate


func _spawn_wave(id: String) -> void:
	var state: Dictionary = encounters[id]
	var kinds: Array = rooms[id].waves[int(state.wave)]
	state.delay = -1.0
	for index: int in kinds.size():
		var enemy: Node3D
		if String(kinds[index]) == "guardian":
			enemy = WORLD_GUARDIAN.new()
		else:
			var creature: Spitter = SPITTER_SCENE.instantiate() as Spitter
			creature.set_script(CREATURE)
			creature.drop_ability_id = &"acid_spit" if String(kinds[index])=="acid" else &"sticky_spit"
			enemy = creature
		enemy.set("movement_guide",navigation.steer)
		enemy.set_meta(&"home_room",id)
		room_roots[id].add_child(enemy)
		enemy.global_position = rooms[id].enemy_spawns[index]
		combat.bind_enemy(enemy)
		if enemy is ExitGuardian:
			(enemy as ExitGuardian).died.connect(_count_kill.bind(id))
		else:
			(enemy as Spitter).died.connect(func(_actor: Node3D,_ability: StringName,_at: Vector3) -> void: _count_kill(id))
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	state.wave = int(state.wave)+1


func _update_encounter(id: String, _delta: float, _inside: bool) -> void:
	if int(encounters[id].wave)>0 and alive_enemies(id).is_empty():
		cleared[id] = true


func _visit_room(id: String) -> void:
	super._visit_room(id)
	var region: String = String(rooms[id].get("region",""))
	if not region.is_empty() and not known_regions.has(region):
		known_regions.append(region)
		get_tree().set_meta(&"dungeon_known_regions",known_regions.duplicate())


func _update_visibility() -> void:
	for shell: Node3D in geometry.room_nodes.values():
		shell.visible = true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	(player as SlimeDungeonPlayer).water_flow = Vector3.ZERO
	if get_tree().paused or finished or _transitioning or gates.size()<2 or not player.is_alive():
		return
	var relative: Vector3 = player.global_position-rooms.cistern.center
	if absf(relative.x)<1.8 and absf(relative.z)<2.2 and relative.y< -0.25 and float(gates[1].get("frozen_seconds"))<=0:
		(player as SlimeDungeonPlayer).water_flow = Vector3(3.8 if attempt_index%2==0 else -3.8,0,0)


func _update_interaction() -> void:
	super._update_interaction()
	var source: Node3D = player.get_nearest_absorb_source()
	if is_instance_valid(source):
		var ability_id: StringName = source.get("ability_id")
		var hero: SlimeDungeonPlayer = player as SlimeDungeonPlayer
		interaction_hint = "Удерживай E — %s, ур. %d · Можно пройти мимо" % [hero.get_ability_definition(ability_id).display_name,hero.get_ability_level(ability_id)+1]
		return
	for gate: Node3D in gates:
		if player.global_position.distance_to(gate.global_position)<4.0:
			interaction_hint = "Клей удержит открытый привод · Решётка %s" % ["поднята" if gate.call("is_open") else "опущена"]
			return
	if is_instance_valid(membrane) and bool(membrane.get("intact")) and player.global_position.distance_to(membrane.global_position)<3.2:
		interaction_hint = "Органическая перепонка · Кислота откроет служебный проход между ветками"


func room_is_safe() -> bool:
	return combat.can_change_loadout() and player.is_alive() and player._action==&""


func retry_room() -> void:
	if finished and not victory:
		restart_run()


func restart_run() -> void:
	get_tree().set_meta(&"dungeon_attempt_index",attempt_index+1)
	get_tree().set_meta(&"dungeon_known_regions",known_regions.duplicate())
	get_tree().paused = false
	var result: Error = get_tree().change_scene_to_file(DUNGEON_SCENE)
	if result!=OK:
		hud.show_notice("Не удалось восстановить подземелье: %d" % result)


func _input(event: InputEvent) -> void:
	var dungeon_hud: Node = hud
	if is_instance_valid(dungeon_hud):
		var map_pressed: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_M
		if map_pressed:
			dungeon_hud.call("toggle_map")
			get_viewport().set_input_as_handled()
			return
		if bool(dungeon_hud.get("map_open")) and event.is_action_pressed(&"pause"):
			dungeon_hud.call("close_map")
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud) and bool(hud.get("map_open")):
		hud.call("close_map")
	super._notification(what)

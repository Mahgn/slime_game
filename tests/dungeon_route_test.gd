extends SceneTree

const SCENE: String = "res://scenes/dungeon/dungeon_route.tscn"
const OUT: String = "res://output/dungeon_ecosystem_2026_10_12/"
const MOVE_ACTIONS: Array[StringName] = [&"move_right",&"move_left",&"move_back",&"move_forward"]
var level: SlimeKeepersWorld
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var capture: bool = false


func _initialize() -> void:
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless"
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+"images"))
	SlimeGameSettings.current().load_settings(OUT+"test-settings.cfg")
	var watchdog: Timer = Timer.new()
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.wait_time = 180.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(func() -> void: _check(false,"watchdog");_finish())
	watchdog.start()
	change_scene_to_file(SCENE)
	await _frames(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_check(is_instance_valid(level) and level.player is SlimeDungeonPlayer,"real dungeon and ranked player initialize")
	if not is_instance_valid(level):
		_finish()
		return
	_disable_enemies()
	_check(level.player.is_on_floor() and level.player.health==100,"fresh grounded slime starts healthy")
	_check(level.rooms.size()==11,"four brood rooms and connected five-area dungeon")
	_check(level.navigation.build_stats.isolated_points.is_empty(),"all authored navigation points have physical support")
	_check(level.alive_enemies("barracks").size()==1 and level.alive_enemies("spring").size()==1,"both initial ability species are present before visiting their rooms")
	await _shot("01-brood")
	await _absorb_enemy("barracks",&"acid_spit")
	await _absorb_enemy("furnace",&"acid_spit")
	var hero: SlimeDungeonPlayer = level.player as SlimeDungeonPlayer
	_check(hero.get_ability_level(&"acid_spit")==2,"repeated real absorption raises current-attempt ability rank")
	_check(hero.get_ability_definition(&"acid_spit").player_damage==21,"rank affects this owner's attack")
	_check(SlimeController.ABILITY.player_damage==12 and SlimeController.ABILITY.slow_seconds==3.0,"rank leaves shared legacy resources immutable")
	await _absorb_enemy("spring",&"sticky_spit")
	_check(hero.has_learned(&"sticky_spit"),"sticky species grants its property")
	await _frames(35)
	_check(level.combat.equip_ability(1,&"acid_spit"),"known ability can be selected outside nearby combat")
	var membrane: Node3D = level.get("membrane")
	_check(bool(membrane.get("intact")),"organic service passage starts closed")
	level._reset_position(Vector3(-1.8,0,-18))
	await _frames(5)
	_check(await _cast_at(&"acid_spit",membrane.global_position+Vector3.UP*0.65),"real acid cast releases a projectile")
	await _frames(30)
	_check(not bool(membrane.get("intact")) and (membrane as StaticBody3D).collision_layer==0,"acid projectile physically opens organic shortcut")
	level._reset_position(level.rooms.entry.spawn)
	await _frames(35)
	_check(level.combat.equip_ability(1,&"sticky_spit"),"sticky can replace acid without duplicate slots")
	var gate: Node3D = (level.get("gates") as Array)[0]
	gate.set("elapsed",4.2)
	gate.call("_update_lift",0.0)
	level._reset_position(gate.global_position+Vector3(2.0,0,2.0))
	await _frames(5)
	var gear: Node3D = gate.get("gear")
	_check(await _cast_at(&"sticky_spit",gear.global_position),"real sticky cast aims at exposed drive")
	await _frames(20)
	var frozen_lift: float = float(gate.get("lift"))
	_check(float(gate.get("frozen_seconds"))>0.0 and frozen_lift<0.7,"sticky holds current closed position rather than opening a gate")
	var remaining: float = float(gate.get("frozen_seconds"))
	paused = true
	await _frames(30,false)
	_check(is_equal_approx(float(gate.get("frozen_seconds")),remaining),"pause freezes mechanism and property duration")
	paused = false
	await _frames(300)
	_check(float(gate.get("frozen_seconds"))==0 and not is_equal_approx(float(gate.get("lift")),frozen_lift),"wrong-position glue expires and machinery resumes")
	level.player.equip_ability(1,&"")
	_check(not level.player.request_action(&"acid_spit"),"discarded equipped ability cannot be used")
	level._reset_position(level.rooms.cistern.center+Vector3(0,-0.5,0))
	await _frames(5)
	var flow_start: Vector3 = level.player.global_position
	await _frames(20)
	_check(level.player.global_position.x-flow_start.x>0.5,"reservoir current physically moves an idle slime")
	(level.get("gates") as Array)[1].receive_dungeon_property(&"sticky_spit",1)
	level._reset_position(level.rooms.cistern.center+Vector3(0,-0.5,0))
	await _frames(5)
	var stopped_start: Vector3 = level.player.global_position
	await _frames(20)
	_check(level.player.global_position.distance_to(stopped_start)<0.08,"holding the water drive stops current displacement")
	level._reset_position(level.rooms.entry.spawn)
	await _frames(5)
	for id: String in ["junction","furnace","hub","armory","summit"]:
		_check(await _walk(level.rooms[id].spawn),"physical garden branch to "+id+" without equipped abilities")
		if not failures.is_empty():
			_finish()
			return
		await _shot("garden-path-"+id)
		if id == "armory":
			_check(await _walk(level.rooms.archive.reward_position),"optional core is physically reachable from workshop")
			_check(level.try_interact() and level.player.unlocked_slots==2,"optional core opens second slot in this attempt")
			level.player.grant_ability(&"sticky_spit")
			_check(level.player.get_slot_ability(1)==&"" and level.player.get_slot_ability(2)==&"sticky_spit","repeat upgrade cannot duplicate a skill already equipped in second slot")
			level.player.equip_ability(1,&"")
			level.player.equip_ability(2,&"")
	level._reset_position(level.rooms.junction.spawn)
	await _frames(5)
	for id: String in ["cistern","hub","garden","summit"]:
		_check(await _walk(level.rooms[id].spawn),"physical water branch to "+id+" without equipped abilities")
		if not failures.is_empty():
			_finish()
			return
		await _shot("water-path-"+id)
	# The final existing guardian stands for the provisional main trial.
	for actor: Node3D in level.alive_enemies("summit"):
		actor.call("receive_hit",9999,"trial-fixture",&"player")
	await _frames(4)
	level._reset_position(level.rooms.summit.exit_point)
	await _frames(8)
	_check(level.try_interact() and level.victory,"completed main trial releases the exit")
	_check(paused,"ending pauses all gameplay")
	await _shot("exit",false)
	level.restart_run()
	paused = false
	await _frames(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_disable_enemies()
	_check(level.player.learned_abilities.is_empty() and level.player.unlocked_slots==1,"fresh attempt clears abilities, ranks and extra slot")
	_check(bool(level.get("membrane").get("intact")),"new population accompanies restored organic barrier")
	var gate_position: Vector3 = ((level.get("gates") as Array)[0] as Node3D).global_position
	_check(is_equal_approx(gate_position.z,1.2),"servants change obstacle mount while rooms stay fixed")
	var remembered: Array = level.get("known_regions")
	_check(remembered.has("garden") and remembered.has("water"),"visited-region knowledge survives return")
	level._reset_position(level.rooms.cistern.spawn)
	await _frames(4)
	var previous_actor_id: int = level.player.get_instance_id()
	level.player.apply_environment_damage(9999)
	await _frames(2,false)
	_check(level.finished and not level.victory,"death ends this whole attempt")
	level.retry_room()
	paused = false
	await _frames(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_disable_enemies()
	_check(level.player.get_instance_id()!=previous_actor_id and level.room_id=="entry","death returns to initial room rather than current-room checkpoint")
	_check(level.player.learned_abilities.is_empty() and level.player.health==100,"death restores body and clears run-built powers")
	_check(bool(level.get("membrane").get("intact")),"death restores consumed obstacle")
	_check(is_equal_approx(((level.get("gates") as Array)[0] as Node3D).global_position.z,-0.8),"second reconstruction uses other authored obstacle configuration")
	var dungeon_hud: Node = level.hud
	dungeon_hud.call("toggle_map")
	_check(bool(dungeon_hud.get("map_open")) and paused,"map opens as a paused readable view")
	dungeon_hud.call("close_map")
	_check(not paused,"closing map resumes the same attempt")
	await _shot("reset-brood")
	_finish()


func _disable_enemies() -> void:
	for id: String in level.rooms:
		for actor: Node3D in level.alive_enemies(id):
			actor.set_physics_process(false)
			# Structural traversal isolates furniture/doors from combat bodies.
			(actor as CollisionObject3D).collision_layer = 0


func _wait_ready() -> void:
	for tick: int in 750:
		if is_instance_valid(level) and not bool(level.get("_transitioning")):
			level._pause_panel.hide()
			paused = false
			return
		await _frames(1)
	_check(false,"scene completes navigation and render warmup before accepting input")


func _absorb_enemy(room: String, ability_id: StringName) -> void:
	var candidates: Array = level.alive_enemies(room)
	if candidates.is_empty():
		_check(false,"available species in "+room)
		return
	var enemy: Spitter = candidates[0] as Spitter
	if room == "barracks":
		var death_seen: Array[bool] = [false]
		enemy.died.connect(func(_actor: Node3D,_ability: StringName,_at: Vector3) -> void: death_seen[0]=true)
		level._reset_position(enemy.global_position+Vector3(1.2,0.05,0))
		await _frames(6)
		for strike: int in 3:
			if death_seen[0]:
				break
			var direction: Vector3 = enemy.global_position-level.player.global_position
			direction.y = 0.0
			level.player.request_action(&"slime_whip")
			level.player._action_direction = direction.normalized()
			level.player._action_aim_point = enemy.global_position+Vector3.UP*0.6
			await _frames(40)
		_check(death_seen[0],"ordinary unboosted whip kills initial creature through combat pipeline")
	else:
		enemy.receive_hit(9999,"absorb-fixture-"+room,&"player")
	await _frames(3)
	var source: Node3D
	for node: Node in level.combat.get_children():
		if node is AbsorbSource and node.ability_id==ability_id and not node.is_claimed() and node.get_meta(&"home_room","")==room:
			source = node as Node3D
			break
	_check(is_instance_valid(source),"species produces absorbable source in "+room)
	if not is_instance_valid(source):
		return
	level._reset_position(source.global_position+Vector3(0.85,0.05,0))
	await _frames(6)
	Input.action_release(&"interact")
	await _frames(2)
	Input.action_press(&"interact")
	for tick: int in 160:
		await _frames(1)
		if source.call("is_claimed"):
			break
		# A desktop focus change cancels an E hold; resume like a new press.
		if not Input.is_action_pressed(&"interact") or level.player._absorb_requires_release:
			Input.action_release(&"interact")
			await _frames(1)
			Input.action_press(&"interact")
	Input.action_release(&"interact")
	await _frames(3)
	if not source.call("is_claimed"):
		print("ABSORB_DIAGNOSTIC room=",room," floor=",level.player.is_on_floor()," action=",level.player._action," hero=",level.player.global_position," source=",source.global_position," nearest=",level.player.get_nearest_absorb_source()," paused=",paused)
	_check(source.call("is_claimed"),"holding E physically absorbs source in "+room)


func _cast_at(ability: StringName, target: Vector3) -> bool:
	var hero: SlimeController = level.player
	hero._cooldowns[ability] = 0.0
	if not hero.request_action(ability):
		return false
	hero._action_aim_point = target
	hero._action_direction = (target-hero.global_position).normalized()
	await _frames(14)
	return hero._action!=&"" or level.combat.get_child_count()>0


func _walk(target: Vector3) -> bool:
	var path: PackedVector3Array
	for retry: int in 450:
		path = level.navigation.path_between(level.player.global_position,target,0.34)
		if not path.is_empty():
			break
		await _frames(1)
	if path.is_empty():
		print("DUNGEON_NO_PATH ",level.player.global_position," -> ",target)
		return false
	for point: Vector3 in path:
		var reached: bool = false
		for tick: int in 650:
			var wish: Vector3 = point-level.player.global_position
			wish.y = 0.0
			if wish.length()<0.28:
				reached = true
				break
			var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(wish.normalized())
			Input.action_press(&"move_right",maxf(axes.x,0))
			Input.action_press(&"move_left",maxf(-axes.x,0))
			Input.action_press(&"move_back",maxf(axes.y,0))
			Input.action_press(&"move_forward",maxf(-axes.y,0))
			await _frames(1)
		for action: StringName in MOVE_ACTIONS:
			Input.action_release(action)
		if not reached:
			print("DUNGEON_BLOCKED ",level.player.global_position," -> ",point)
			return false
	await _frames(10)
	return level.player.global_position.distance_to(target)<0.65


func _frames(count: int, resume: bool = true) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame
		if resume and paused:
			paused = false
			if is_instance_valid(level) and is_instance_valid(level._pause_panel):
				level._pause_panel.hide()


func _shot(label: String, resume: bool = true) -> void:
	if not capture:
		return
	await _frames(4,resume)
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+"images/"+label+".png")


func _check(condition: bool, label: String) -> void:
	checks.append({"check":label,"pass":condition})
	if not condition:
		failures.append(label)
	print("PASS " if condition else "FAIL ",label)


func _finish() -> void:
	var file: FileAccess = FileAccess.open(OUT+"dungeon-checks.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("DUNGEON_RESULT checks=%d failures=%d" % [checks.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

# Geometry/lifecycle fixtures. Combat pacing is a separate unmodified-HP run.
const SCENE := "res://scenes/keepers/keepers_facility.tscn"
var output_folder := "res://output/keepers_finalization_2026_10_08/"
var level
var failures: Array[String] = []
var records: Array[Dictionary] = []
var capture := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			output_folder = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder+"images"))
	SlimeGameSettings.current().load_settings(output_folder+"facility_fixture.cfg")
	change_scene_to_file(SCENE)
	await _ticks(15)
	level = current_scene
	if not is_instance_valid(level) or not is_instance_valid(level.navigation):
		_check(false,"Facility initialized")
		_finish()
		return
	_check(level.rooms.size()==10 and level.connections.size()==11,"Eight main rooms, two secrets, two loops")
	print("ISOLATED ",level.navigation.build_stats.isolated_points)
	_check(level.navigation.build_stats.isolated_points.is_empty(),"No isolated authored navigation points")
	_check(level.hazards.size()==4,"Four authored mechanisms installed")
	_check(not level.hazards[0].introduced and not level.hazards[1].introduced,"Remote new mechanisms do not begin unseen")
	level._reset_position(level.rooms.furnace.spawn)
	await _ticks(130)
	_check(level.alive_enemies("furnace").is_empty() and level.encounters.furnace.wave==0,"Furnace approach teaches steam before combat")
	level._reset_position(level.encounter_focus("furnace"))
	await _ticks(80)
	_check(level.alive_enemies("furnace").is_empty(),"Advancing early cannot skip the first isolated mechanism cycle")
	await _ticks(180)
	_check(level.hazards[0].demonstrated and level.alive_enemies("furnace").size()==2,"Combat follows demonstrated hazard")
	for actor: Node3D in level.alive_enemies("furnace"):
		actor.receive_hit(9999,"intro-fixture-clear",&"player")
	level.encounters.furnace = {"wave":0,"delay":-1.0,"kills":0}
	level._reset_position(level.rooms.entry.spawn)
	await _ticks(10)
	# Suppress encounter fixtures and hazard damage during structural traversal.
	for id: String in level.rooms:
		level.cleared[id] = true
	for hazard in level.hazards:
		hazard.set_physics_process(false)
	var player_id: int = level.player.get_instance_id()
	var geometry_id: int = level.geometry.get_instance_id()
	await _shot("entry")
	for edge: Dictionary in level.connections:
		for id: String in [edge.a,edge.b,edge.a]:
			if not await _walk(level.rooms[id].spawn):
				_check(false,"Physical path to "+id)
				await _shot("blocked-"+id)
				_finish()
				return
			_check(level.room_id==id,"Continuous entry "+id)
			_check(level.player.get_instance_id()==player_id and level.geometry.get_instance_id()==geometry_id,"Actors and world persist in "+id)
			await _shot(id)
	_check(level.visited.size()==10 and level.secrets_found.size()==2,"All rooms and both secrets physically reached")
	for walk: Dictionary in [
		{"at":Vector3(11,0,-9),"name":"North settling maintenance walk"},
		{"at":Vector3(15.5,0,-7),"name":"East settling bypass"},
		{"at":Vector3(14.6,0,-43),"name":"North collector return"},
		{"at":Vector3(14.6,0,-33),"name":"Collector crossing beside the lowered pipe"}
	]:
		_check(await _walk(walk.at),walk.name+" stays physically clear after dressing")
	# Big visual upper surfaces also participate in physics when a charged jump
	# reaches them; the new hood and chimney must not be ghost geometry.
	for surface: Dictionary in [
		{"at":Vector3(-18.5,6,-9.1),"y":3.70,"name":"Furnace hood"},
		{"at":Vector3(-17.4,6,-9.15),"y":4.93,"name":"Furnace flue"},
		{"at":Vector3(-12.0,6,-24),"y":3.29,"name":"Boiler shoulder"},
		{"at":Vector3(9.7,6,-22.1),"y":1.77,"name":"Pump housing"},
		{"at":Vector3(4.15,6,-44.52),"y":2.045,"name":"Collapsed collector masonry"},
		{"at":Vector3(-30.5,6,-43),"y":2.4,"name":"Records cabinet"},
		{"at":Vector3(-2,6,-68.7),"y":5.18,"name":"Sluice stone arch"}
	]:
		var roof_query := PhysicsRayQueryParameters3D.create(surface.at,surface.at-Vector3.UP*7,1)
		var roof_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(roof_query)
		_check(not roof_hit.is_empty() and absf(roof_hit.position.y-float(surface.y))<0.16,surface.name+" physical surface matches the visible profile")
	var walls: Array=level.geometry.find_children("FullStructuralWall*","StaticBody3D",true,false)
	_check(not walls.is_empty(),"Full structural walls exist")
	var wall: StaticBody3D=walls[0]
	var sample := Vector3(wall.global_position.x,2.0,wall.global_position.z)
	_check(not level.geometry.cutaway.is_point_cut(wall,sample),"Full visible wall blocks aim without a cut exception")
	var normal: Vector3=wall.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(sample-normal,sample+normal,1)
	_check(not level.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Full wall blocks physical attacks")
	await _hazard_checks()
	# The building uses a fixed architectural section; changing sides, rooms or
	# jump height cannot turn a complete wall into a different silhouette.
	var section: Dictionary = level.geometry.cutaway.structural_sections[0]
	level.player.global_position = section.point+section.normal*2
	level.geometry.cutaway.update_view(level.player,level.player.presentation.camera)
	_check(section.node.is_visible_in_tree(),"Every wall retains full height and visibility")
	level.player.global_position = section.point+section.normal*0.1
	level.geometry.cutaway.update_view(level.player,level.player.presentation.camera)
	_check(section.node.is_visible_in_tree(),"Door threshold cannot toggle a wall")
	level.player.global_position = section.point-section.normal*2
	level.geometry.cutaway.update_view(level.player,level.player.presentation.camera)
	_check(not section.body.has_meta(&"architectural_cut_height") and section.node.is_visible_in_tree(),"Returning preserves the fixed wall and aiming state")
	# The F04 vault has a shared visual owner and a single compound body. Test
	# both sides: hidden geometry must still block physical attacks overhead.
	var portal: Node3D = level.geometry.get_node("FurnaceServicePortal")
	var portal_body: StaticBody3D = portal.get_node("VaultedServicePortal")
	level._reset_position(Vector3(-9,0,-12))
	await _ticks(12)
	_check(portal.visible and not portal_body.has_meta(&"architectural_cut_height"),"Furnace side shows the complete service vault")
	var arch_point := Vector3(-9,3.66,-13.5)
	var arch_query := PhysicsRayQueryParameters3D.create(arch_point+Vector3(0,0,1.5),arch_point-Vector3(0,0,1.5),1)
	var arch_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(arch_query)
	_check(not arch_hit.is_empty() and arch_hit.collider==portal_body,"Visible stone arch blocks overhead physical rays")
	level._reset_position(Vector3(-9,0,-15))
	await _ticks(12)
	_check(portal.visible and not level.geometry.cutaway.is_point_cut(portal_body,arch_point),"Boiler side retains the same visible arch and aiming obstruction")
	arch_hit = level.get_world_3d().direct_space_state.intersect_ray(arch_query)
	_check(not arch_hit.is_empty() and arch_hit.collider==portal_body,"Permanent vault retains physical attack obstruction")
	await _walk(Vector3(-9,0,-12))
	_check(portal.visible and level.player.global_position.distance_to(Vector3(-9,0,-12))<0.85,"Walking back under the permanent vault has no snagging")
	level._reset_position(level.rooms.armory.spawn)
	await _ticks(12)
	await _walk(level.rooms.archive.reward_position)
	_check(level.try_interact() and level.player.unlocked_slots==2,"Core remains obtainable")
	await _walk(level.rooms.summit.exit_point)
	_check(level.try_interact() and level.victory,"Gate exit remains obtainable")
	level.restart_run()
	await _ticks(20)
	level = current_scene
	_check(level.scene_file_path==SCENE and level.room_roots.size()==10 and level.player.unlocked_slots==1,"Restart retains facility configuration and resets state")
	var baseline_nodes := get_node_count()
	for restart in 10:
		level.restart_run()
		await _ticks(20)
		level = current_scene
		_check(level.hazards.size()==4 and level.room_roots.size()==10 and get_node_count()<=baseline_nodes+2,"Repeated restart %d keeps stable world and mechanism count" % (restart+1))
	_finish()

func _hazard_checks() -> void:
	var hazard: Node3D = level.hazards[0]
	level._reset_position(hazard.global_position)
	await _ticks(15)
	hazard.reset_cycle()
	hazard.set_physics_process(true)
	var hp: int = level.player.health
	await _ticks(200)
	_check(hazard.phase=="warning" and level.player.health==hp,"Steam warning precedes damage")
	var before: float = hazard.clock
	paused = true
	for i in 20:
		await process_frame
	_check(is_equal_approx(hazard.clock,before),"Pause freezes hazard clock")
	paused = false
	await _ticks(90)
	_check(level.player.health==hp-10,"Steam deals one readable burst hit")
	var hit_hp: int = level.player.health
	await _ticks(12)
	_check(level.player.health==hit_hp,"No repeated hit in same burst")
	hazard.reset_cycle()
	level._reset_position(hazard.spec.valve)
	await _ticks(10)
	_check(level.try_interact() and hazard.disabled,"Valve disables steam through normal interaction")
	level._reset_position(hazard.global_position)
	await _ticks(330)
	_check(level.player.health==hit_hp,"Disabled mechanism stays safe")
	# Enemy source/death semantics use normal hit handling, not silent HP edits.
	level._spawn_wave("furnace")
	var enemy: Node3D = level.alive_enemies("furnace")[1]
	enemy.set_physics_process(false)
	var enemy_hp: int = enemy.health
	_check(enemy.receive_environment_hit(10,"fixture-trap") and enemy.health==enemy_hp-10,"Trap damages enemy through hit pipeline")
	_check(not enemy.receive_environment_hit(10,"fixture-trap") and enemy.health==enemy_hp-10,"Enemy deduplicates same trap hit")
	var press: Node3D = level.hazards[1]
	level._reset_position(press.global_position)
	enemy.global_position = press.global_position+Vector3(0.3,0,0)
	enemy_hp = enemy.health
	for actor: Node3D in level.alive_enemies("furnace"):
		actor.set_physics_process(false)
	await _ticks(15)
	press.reset_cycle()
	var weight: Node3D = press.head.get_node("MovingPressArt")
	_check(is_equal_approx(weight.global_position.y,press.global_position.y+2.2),"Detailed press weight begins above its marked footprint")
	press.set_physics_process(true)
	hp = level.player.health
	await _ticks(290)
	_check(is_equal_approx(weight.global_position.y,press.global_position.y+0.3) and is_equal_approx(press.piston.scale.y,2.1),"Detailed weight and piston follow the damaging phase")
	_check(level.player.health==hp-14,"Press has distinct damage and active footprint")
	_check(enemy.health==maxi(0,enemy_hp-14),"Active press damages nearby enemy in physical scene")
	for actor: Node3D in level.alive_enemies("furnace"):
		actor.receive_hit(9999,"fixture-clear",&"player")
	await _shot("press-active")
	press.disable()
	_check(is_equal_approx(weight.global_position.y,press.global_position.y+2.2),"Disabling press lifts the detailed weight out of the lane")
	level._visit_room("pump_room")
	level.player.apply_environment_damage(9999)
	level.retry_room()
	await _ticks(20)
	_check(level.player.is_alive() and press.disabled and hazard.disabled,"Local death preserves stopped machinery")
	_check(press.phase=="safe" and press.clock==0,"Retry clears active mechanism and starts safe")
	for mechanism in level.hazards:
		mechanism.disable()

func _walk(target: Vector3) -> bool:
	var path: PackedVector3Array = level.navigation.path_between(level.player.global_position,target,0.34)
	if path.is_empty():
		print("NO PATH ",level.player.global_position," -> ",target)
		return false
	for point: Vector3 in path:
		var arrived := false
		for i in 700:
			var offset: Vector3 = point-level.player.global_position
			offset.y = 0
			if offset.length()<0.28:
				arrived = true
				break
			var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(offset.normalized())
			Input.action_press(&"move_right",maxf(axes.x,0))
			Input.action_press(&"move_left",maxf(-axes.x,0))
			Input.action_press(&"move_back",maxf(axes.y,0))
			Input.action_press(&"move_forward",maxf(-axes.y,0))
			await _ticks(1)
		for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]:
			Input.action_release(action)
		if not arrived:
			print("BLOCKED ",level.player.global_position," -> ",point)
			return false
	await _ticks(12)
	return level.player.global_position.distance_to(target)<0.6

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		if paused:
			paused = false

func _shot(label: String) -> void:
	if not capture:
		return
	await _ticks(4)
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(output_folder+"images/"+label+".png")

func _check(condition: bool, label: String) -> void:
	records.append({"check":label,"pass":condition})
	if not condition:
		failures.append(label)
	print("PASS " if condition else "FAIL ",label)

func _finish() -> void:
	var file := FileAccess.open(output_folder+"facility_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":records,"failures":failures},"\t"))
	quit(0 if failures.is_empty() else 1)

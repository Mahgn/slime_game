extends "res://tests/dungeon_wall_fade_test.gd"

# Matched views of the two-room pilot; the measured paths use physical input.
var reference := false

func _initialize() -> void:
	out = "res://output/room_wall_hybrid_2026_10_14/candidate/"
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg == "--reference": reference = true
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	seed(4873)
	create_timer(180.0, true).timeout.connect(func() -> void: _check(false, "bounded watchdog"); _finish())
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1600, 900)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.frame_post_draw.connect(_sample_frame)
	change_scene_to_file(SCENE)
	await _ticks(25)
	level = current_scene as SlimeKeepersWorld
	await _wait_ready()
	_check(is_instance_valid(level) and not level._transitioning, "real dungeon ready")
	if not is_instance_valid(level): _finish(); return
	_freeze_enemies()
	geometry_before = _geometry_signature()
	for spot: Dictionary in [
		{"id":"entry", "at":Vector3(-3.4,0,14)},
		{"id":"threshold", "at":Vector3(-8.5,0,14)},
		{"id":"spring", "at":Vector3(-13.6,0,14)},
		{"id":"spring-front", "at":Vector3(-13,0,16.5)},
		{"id":"entry-front", "at":Vector3(-3,0,18.5)}]:
		level._reset_position(spot.at)
		await _ticks(85)
		await _shot(spot.id)
		if spot.id == "threshold":
			level.player.presentation.set_process(false)
			var cam: Camera3D = level.player.presentation.camera
			var original_size := cam.size
			var original_transform := cam.global_transform
			cam.size = 10.5
			cam.global_position = Vector3(-8.5,0.7,12.8) + Vector3(12,13.9,12)
			await _shot("portal-close")
			if not reference:
				level.geometry.cutaway.set_enabled(false)
				await _shot("portal-closed")
				level.geometry.cutaway.set_enabled(true)
				level.geometry.cutaway.advance(Vector3(-8.5,0,14), 0.15)
				await _shot("portal-half")
			cam.size = original_size
			cam.global_transform = original_transform
			level.player.presentation.set_process(true)
	if not reference:
		_check(level.geometry.has_node("HybridRoomArchitecture"), "pilot architecture exists only in dungeon")
		_pilot_contract()
	await _fade_approach()
	await _cross(Vector3(-6.2,0,14), Vector3(-10.8,0,14), "entry-spring-forward")
	await _cross(Vector3(-10.8,0,14), Vector3(-6.2,0,14), "entry-spring-return")
	_check(_geometry_signature() == geometry_before, "all physics unchanged by transitions")
	if not reference: await _candidate_checks()
	_finish()

func _pilot_contract() -> void:
	var current: Node = level.geometry.cutaway
	level.player.presentation.set_process(false)
	var portals: Array[Dictionary] = []
	var fronts: Array[Dictionary] = []
	var scoped := true
	for section: Dictionary in current.structural_sections:
		if section.get("hybrid_role", "") == "portal": portals.append(section)
		if section.get("hybrid_role", "") == "fixed_front_cut": fronts.append(section)
		if section.get("hybrid_pair", false):
			scoped = scoped and section.room_ids.all(func(id: String) -> bool: return id in ["entry","spring"])
	_check(scoped and portals.size() >= 6 and not fronts.is_empty(), "hybrid rules are confined to the selected two rooms and their shared passage")
	current.set_enabled(false)
	current.set_enabled(true)
	var synchronized := true
	var permanent := true
	var bounded := true
	var previous := 0.0
	# Real section renderer, including both sides and the corridor rails.
	# Repeated threshold crossings must not close a piece of the common portal.
	for frame: int in 240:
		var point := Vector3(-8.5 + sin(frame * 0.35)*2.0, 0, 14)
		current.advance(point, 1.0/60.0)
		var amount: float = portals[0].reveal_amount
		synchronized = synchronized and portals.all(func(s: Dictionary) -> bool: return is_equal_approx(s.reveal_amount, amount))
		bounded = bounded and amount >= previous and amount-previous <= 0.056
		permanent = permanent and fronts.all(func(s: Dictionary) -> bool: return s.reveal_amount > 0.999 and not s.node.visible)
		previous = amount
	_check(synchronized and bounded and previous > 0.99, "all portal pieces fade together without reversal during repeated threshold crossings")
	_check(permanent, "front cut remains fixed throughout room switching")
	for frame: int in 120: current.advance(level.rooms.summit.center, 1.0/60.0)
	_check(portals.all(func(s: Dictionary) -> bool: return s.reveal_amount < 0.001 and s.node.visible), "shared portal restores completely after leaving both rooms")
	_check(fronts.all(func(s: Dictionary) -> bool: return s.reveal_amount > 0.999 and not s.node.visible), "authored low front silhouette does not grow back in distant rooms")
	var spine: Node = level.geometry.find_child("ConnectedRearReturn",true,false)
	_check(spine != null and spine.is_visible_in_tree(), "connected rear return survives portal restoration")
	for frame: int in 60: current.advance(Vector3(-8.5,0,14),1.0/60.0)
	_check(spine != null and spine.is_visible_in_tree(), "rear return remains connected while portal is fully hidden")
	level.player.presentation.set_process(true)

func _finish() -> void:
	if finished: return
	finished = true
	_release()
	var failed: bool = checks.any(func(item: Dictionary) -> bool: return not item.pass)
	var report := {"status":"FAIL" if failed else "PASS", "reference":reference,
		"checks":checks, "records":records, "engine":Engine.get_version_info(),
		"renderer":RenderingServer.get_current_rendering_method(), "device":RenderingServer.get_video_adapter_name(),
		"scope":"Entry/spring two-room pilot; physical crossings, fixed close view, enemies frozen; inter-draw timing, not GPU or full combat."}
	FileAccess.open(out + "results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HYBRID_PAIR_RESULT checks=", checks.size(), " failures=", checks.filter(func(item: Dictionary) -> bool: return not item.pass).size())
	quit(1 if failed else 0)

extends "res://tests/keepers_ink_style_test.gd"

# Native movement and live-effect workload. PNG readback and fixture relocation
# are outside samples; first spawns/attacks are measured separately, not hidden.
var reference_script := ""
var records: Array[Dictionary] = []
var raw_frames: Array[float] = []
var active_label := ""
var previous_draw := 0
var combat_only := false

func _initialize() -> void:
	out = "res://output/keepers_ink_performance_2026_10_08/candidate/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"): out = arg.trim_prefix("--output=").trim_suffix("/")+"/"
		if arg.begins_with("--reference=res://output/"): reference_script = arg.trim_prefix("--reference=")
		if arg == "--combat-only": combat_only = true
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BLOCKED native frame pacing requires a window")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	seed(4873)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280,720)
	create_timer(600,true).timeout.connect(func(): printerr("FAIL pacing timeout"); quit(2))
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(35)
	level = current_scene
	level.ink_style.set_mode(4)
	_check(level.ink_style.mode==4,"Ink is selected during timing")
	_check(not level.has_node("RenderPreparation") and not level.has_node("BuildingRenderPreparation") and not level._transitioning,"Render preparation is removed before gameplay")
	if not reference_script.is_empty():
		var old: SlimeGroundTrail = level.player._ground_trail
		old.get_parent().remove_child(old)
		old.free()
		var reference: SlimeGroundTrail = load(reference_script).new()
		reference.name = "GroundTrail"
		reference.setup(level.player)
		level.player.add_child(reference)
		level.player._ground_trail = reference
	for id in level.rooms: level.cleared[id] = true
	for actor in level.alive_enemies(): actor.queue_free()
	for hazard in level.hazards: hazard.disable()
	await _ticks(5)
	RenderingServer.frame_post_draw.connect(_sample_frame)
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if combat_only: break
		root.size = size
		DisplayServer.window_set_size(size)
		for link: Dictionary in level.connections:
			var direction: Vector3 = (link.path[1]-link.path[0]).normalized()
			var a: Vector3 = link.path[0]-direction*1.8
			var b: Vector3 = link.path[1]+direction*1.8
			await _crossing(a,b,"%dp-%s-%s" % [size.y,link.a,link.b])
			await _crossing(b,a,"%dp-%s-%s" % [size.y,link.b,link.a])
	# First visible construction and activity of each enemy family, projectiles,
	# whip, both trap types and landing splashes. Hero is invulnerable only here.
	root.size = Vector2i(1920,1080)
	for id: String in ["furnace","hub","summit"]:
		for actor in level.alive_enemies(): actor.queue_free()
		level._reset_position(level.encounter_focus(id))
		await _ticks(12)
		level.encounters[id].wave = 0
		await _begin("combat-"+id)
		var spawn_start := Time.get_ticks_usec()
		level._spawn_wave(id)
		var spawn_ms := float(Time.get_ticks_usec()-spawn_start)/1000.0
		for hazard in level.hazards:
			if hazard.spec.room==id: hazard.disabled=false; hazard.reset_cycle()
		for tick in 420:
			level.player._hurt_protection_left=60.0
			if tick % 40 == 0: level.player.request_action(&"slime_whip")
			if tick % 90 == 0: level.player._ground_trail.add_landing_splash(8.0)
			var target: Vector3 = level.encounter_focus(id)+Vector3(sin(tick*0.023)*2,0,cos(tick*0.023)*2)
			_walk_towards(target)
			await _ticks(1)
		_release()
		_end()
		records[-1].spawn_cpu_ms=spawn_ms
		records[-1].enemies=level.alive_enemies().size()
		await _shot("combat-"+id)
	await _equivalence()
	if level.player._ground_trail.has_method("save_profile"):
		level.player._ground_trail.save_profile(out)
	var bad95 := records.filter(func(r:Dictionary)->bool:return r.p95_ms>16.67).size()
	var bad99 := records.filter(func(r:Dictionary)->bool:return r.p99_ms>16.67).size()
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"records":records,"checks":checks,"reference":reference_script,"p95_failures":bad95,"p99_failures":bad99,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"scope":("3 live encounter fixtures at 1080p" if combat_only else "44 bidirectional crossings at 720p/1080p; 3 live encounter fixtures at 1080p")+"; PNG and relocation excluded; uncapped inter-draw wall times"},"\t"))
	print("PACING_RESULT functional_failures=",checks.filter(func(c:Dictionary)->bool:return not c.pass).size()," p95_failures=",bad95," p99_failures=",bad99)
	quit(1 if checks.any(func(c:Dictionary)->bool:return not c.pass) else 0)

func _crossing(a:Vector3,b:Vector3,label:String) -> void:
	level._reset_position(a)
	await _ticks(20)
	await _begin(label)
	var arrived := false
	for tick in 240:
		var offset: Vector3 = b-level.player.global_position
		offset.y=0
		if offset.length()<0.24: arrived=true; break
		_walk_towards(b)
		await _ticks(1)
	_release()
	_end()
	_check(arrived,label+" physically reached")
	if label in ["1080p-entry-furnace","1080p-garden-summit"]: await _shot(label)

func _begin(label:String) -> void:
	await RenderingServer.frame_post_draw
	raw_frames.clear()
	previous_draw=Time.get_ticks_usec()
	active_label=label

func _end() -> void:
	var label := active_label
	active_label=""
	var sorted := raw_frames.duplicate()
	sorted.sort()
	records.append({"label":label,"frames":sorted.size(),"median_ms":sorted[sorted.size()/2],"p95_ms":sorted[int(sorted.size()*0.95)],"p99_ms":sorted[int(sorted.size()*0.99)],"max_ms":sorted[-1],"over_16_ms":sorted.filter(func(v:float)->bool:return v>16.67).size(),"over_33_ms":sorted.filter(func(v:float)->bool:return v>33.33).size(),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
	FileAccess.open(out+label+".frames.json",FileAccess.WRITE).store_string(JSON.stringify(raw_frames))
	print("FRAME_METRIC ",JSON.stringify(records[-1]))

func _sample_frame() -> void:
	var now := Time.get_ticks_usec()
	if not active_label.is_empty(): raw_frames.append(float(now-previous_draw)/1000.0)
	previous_draw=now

func _equivalence() -> void:
	# Compare identical trail data against the saved pre-optimization assembler.
	# This optional local reference is never loaded by the ordinary game.
	if not reference_script.is_empty(): return
	var path := "res://output/keepers_ink_performance_2026_10_08/trail_baseline.gd"
	if not ResourceLoader.exists(path): return
	for actor in level.alive_enemies(): actor.queue_free()
	for hazard in level.hazards: hazard.disable()
	level._reset_position(Vector3(-6.3,0,13))
	await _ticks(20)
	for tick in 55:
		_walk_towards(Vector3(-10.5,0,13))
		await _ticks(1)
	_release()
	_freeze()
	var trail: SlimeGroundTrail = level.player._ground_trail
	var old: SlimeGroundTrail = load(path).new()
	old.setup(level.player)
	level.add_child(old)
	old.set_physics_process(false)
	old._samples=trail._samples.duplicate(true)
	old._splashes=trail._splashes.duplicate(true)
	old._age=trail._age
	# Both assemblers need the same physics snapshot too. Re-querying a flat
	# floor with a cold cache can differ by 1.5e-8 m from an earlier ray hit.
	old._support_cache=trail._support_cache.duplicate(true)
	old._draw_effect()
	trail._draw_effect()
	_check(_triangles(old)==_triangles(trail),"Optimized trail has exactly the same triangle positions and colors")
	FileAccess.open(out+"triangle-bits.json",FileAccess.WRITE).store_string(JSON.stringify({"old":_triangles(old),"new":_triangles(trail)}))
	var costs: Dictionary={}
	for pair: Array in [["reference",old],["candidate",trail]]:
		var times: Array[float]=[]
		for repeat in 12:
			var start := Time.get_ticks_usec()
			pair[1]._draw_effect()
			times.append(float(Time.get_ticks_usec()-start)/1000.0)
		costs[pair[0]]=times
	FileAccess.open(out+"trail_cost.json",FileAccess.WRITE).store_string(JSON.stringify(costs,"\t"))
	trail.visible=false
	var before := await _shot("trail-before")
	old.visible=false
	trail.visible=true
	var after := await _shot("trail-after")
	_check(before.get_data()==after.get_data(),"Frozen native image matches the original trail pixel-for-pixel")
	old.queue_free()
	_unfreeze()

func _triangles(trail:SlimeGroundTrail) -> Array[String]:
	var result: Array[String]=[]
	for triangle in range(0,trail._indices.size(),3):
		var data := PackedFloat32Array()
		for k in 3:
			var index := trail._indices[triangle+k]
			var p := trail._vertices[index]
			var c := trail._colors[index]
			data.append_array(PackedFloat32Array([p.x,p.y,p.z,c.r,c.g,c.b,c.a]))
		result.append(data.to_byte_array().hex_encode())
	result.sort()
	return result

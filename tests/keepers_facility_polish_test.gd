extends SceneTree

# Native behaviour checks, bus capture and physical doorway traversal. Fixture
# relocation chooses each start; movement across the doorway uses normal input.
var out := "res://output/keepers_f06_2026_10_08/polish/"
var level
var checks: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var frame_times: Array[float] = []
var sampling := false
var last_frame := 0
var checking_blend := false
var previous_gains: Array = []
var max_gain_step := 0.0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			out = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("BLOCKED native rendering and audio required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	SlimeGameSettings.current().load_settings(out+"settings.cfg")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
	await _ticks(25)
	level = current_scene
	var mounted: Array[Node] = level.geometry.find_children("WallSconce","Node3D",true,false)
	mounted.append_array(level.geometry.find_children("ServiceLantern","Node3D",true,false))
	_check(mounted.size()==17,"All seven work lamps and ten candle brackets exist")
	for fixture: Node3D in mounted:
		# Duplicate section names are auto-renamed by Godot; check actual ownership.
		var bound: bool = level.geometry.cutaway.structural_sections.any(func(section: Dictionary) -> bool: return section.node==fixture.get_parent())
		_check(bound,"Wall-mounted %s in %s shares its wall section" % [fixture.name,fixture.get_parent().get_parent().name])
	for id: String in level.rooms:
		level.cleared[id] = true
	for actor in level.alive_enemies():
		actor.queue_free()
	for hazard in level.hazards:
		hazard.set_physics_process(false)
		hazard.reset_cycle()
	await _ticks(5)
	await _mechanisms()
	await _soundscape()
	for hazard in level.hazards:
		hazard.disable()
	RenderingServer.frame_post_draw.connect(_drawn)
	physics_frame.connect(_audio_step)
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		DisplayServer.window_set_size(size)
		for id: String in level.rooms:
			level._reset_position(level.rooms[id].spawn)
			await _ticks(4)
			var objective: Rect2 = level.hud._objective.get_global_rect()
			var navigation: Rect2 = level.hud._navigation.get_global_rect()
			var title: Rect2 = level.hud._title.get_global_rect()
			_check(title.end.y+5<=objective.position.y and objective.end.y+5<=navigation.position.y,"Room copy has visible gaps: %s at %dp" % [id,size.y])
			_check(navigation.end.x<level.hud._time.get_global_rect().position.x,"Room copy stays clear of status: %s at %dp" % [id,size.y])
			if id in ["entry","pump_room","hub"]:
				await _shot("hud-%s-%d" % [id,size.y])
		for route: Dictionary in [
			{"id":"furnace-hub","a":Vector3(-9,0,-11),"b":Vector3(-9,0,-16)},
			{"id":"cistern-pump","a":Vector3(11,0,-9),"b":Vector3(11,0,-14)},
			{"id":"armory-gate","a":Vector3(-12,0,-47),"b":Vector3(-12,0,-52)},
			{"id":"collector-gate","a":Vector3(8.5,0,-45),"b":Vector3(8.5,0,-52)}
		]:
			await _cross(route.a,route.b,"%d-%s-forward" % [size.y,route.id])
			await _cross(route.b,route.a,"%d-%s-return" % [size.y,route.id])
	var failed := checks.any(func(item: Dictionary) -> bool: return not item.pass)
	FileAccess.open(out+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"transitions":transitions,"status":"FAIL" if failed else "PASS"},"\t"))
	quit(1 if failed else 0)

func _mechanisms() -> void:
	var press = level.hazards[1]
	level._reset_position(press.global_position)
	await _ticks(8)
	press.introduced = true
	press.reset_cycle()
	press.set_physics_process(true)
	var hp: int = level.player.health
	await _ticks(260)
	_check(press.phase=="warning" and level.player.health==hp,"Press warns before any damage")
	await _shot("press-warning")
	# Step through the fall in the physical simulation and keep intermediate poses.
	var intermediate := 0
	var warning_damage := false
	while press.phase=="warning":
		if press.head.position.y<2.20 and press.head.position.y>0.40:
			intermediate += 1
		await _ticks(1)
		if press.phase=="warning" and level.player.health!=hp:
			warning_damage = true
	_check(intermediate>=3 and not warning_damage,"Visible falling weight stays harmless until impact")
	_check(level.player.health==hp-14 and is_equal_approx(press.head.position.y,0.3),"Impact and the 14 HP hit coincide")
	await _shot("press-impact")
	var impact_hp: int = level.player.health
	await _ticks(12)
	_check(level.player.health==impact_hp,"Held weight does not deal repeated damage")
	while press.phase=="active":
		await _ticks(1)
	await _ticks(12)
	_check(press.head.position.y>0.4 and press.head.position.y<2.1,"Counterweight returns over multiple frames")
	press.set_physics_process(false)
	press.reset_cycle()
	var steam = level.hazards[0]
	level._reset_position(steam.global_position+Vector3(-2.3,0,0))
	await _ticks(12)
	steam.introduced = true
	steam.clock = steam.SAFE+0.4
	steam.phase = "warning"
	steam._refresh_visual()
	await _shot("steam-warning")
	steam.clock = steam.SAFE+steam.WARNING+0.12
	steam.phase = "active"
	steam._refresh_visual()
	steam.set_physics_process(true)
	await _ticks(2)
	await _shot("steam-active")
	paused = true
	var steam_time: float = steam.steam_material.get_shader_parameter("steam_time")
	var mix_time: float = level.ambience.mix_time
	await create_timer(0.25,true).timeout
	_check(is_equal_approx(steam_time,steam.steam_material.get_shader_parameter("steam_time")) and is_equal_approx(mix_time,level.ambience.mix_time),"Pause freezes the visible steam and ambient blend")
	paused = false
	await _ticks(3)
	_check(float(steam.steam_material.get_shader_parameter("steam_time"))>steam_time,"Steam resumes from its paused phase")
	steam.set_physics_process(false)
	steam.reset_cycle()

func _soundscape() -> void:
	var sound = level.ambience
	var steam = level.hazards[0]
	level._reset_position(steam.global_position+Vector3(-2.3,0,0))
	await _ticks(75)
	_check(sound.listener.is_current() and sound.listener.global_position.distance_to(level.player.global_position)<0.7,"Spatial listening follows the hero instead of the distant camera")
	_check(sound.listener.global_basis.is_equal_approx(level.player.presentation.camera.global_basis),"Stereo orientation agrees with the fixed camera")
	var normal: float = sound.duck_gain
	steam.phase = "warning"
	await _ticks(35)
	_check(sound.duck_gain<normal*0.6,"Approaching danger lowers local machinery ambience")
	steam.phase = "safe"
	await _ticks(55)
	_check(sound.duck_gain>0.95,"Room ambience returns after danger")
	# Inspect actual mixed samples, not just AudioStreamPlayer.playing.
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2
	var bus := AudioServer.get_bus_index(&"Effects")
	AudioServer.add_bus_effect(bus,capture)
	for hazard in [steam,level.hazards[1]]:
		level._reset_position(hazard.global_position+Vector3(0,0,2.5))
		await _ticks(12)
		for warning in [true,false]:
			capture.clear_buffer()
			hazard._play_cue(warning)
			await _ticks(22)
			var buffer := capture.get_buffer(capture.get_frames_available())
			var energy := 0.0
			for sample: Vector2 in buffer:
				energy += sample.length_squared()
			var rms := sqrt(energy/maxi(1,buffer.size()*2))
			_check(rms>0.00001,"Audible mixed %s %s cue RMS=%f" % [hazard.spec.kind,"warning" if warning else "active",rms])
			_write_wav(buffer,"%s-%s.wav" % [hazard.spec.kind,"warning" if warning else "active"])
			hazard.audio_player.stop()
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	var settings := SlimeGameSettings.current()
	settings.set_effects_volume(0)
	_check(AudioServer.is_bus_mute(bus),"Effects slider mutes mechanism bus")
	settings.set_effects_volume(1)
	settings.set_ambience_volume(0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambience")),"Ambience slider mutes local environmental sources")
	settings.set_ambience_volume(0.6)
	paused = true
	await create_timer(0.20,true).timeout
	_check(sound.sources.all(func(source: Dictionary) -> bool: return source.player.stream_paused),"Pause suspends every local loop")
	paused = false
	await _ticks(8)
	_check(sound.sources.all(func(source: Dictionary) -> bool: return source.player.playing and not source.player.stream_paused),"Local loops resume after pause")
	var old_hero: int = level.player.get_instance_id()
	level.player.apply_environment_damage(9999)
	level.retry_room()
	await _ticks(20)
	_check(level.player.is_alive() and sound.listener.global_position.distance_to(level.player.global_position)<0.7,"Listener follows the hero after death and retry")
	print("RETRY hero before=",old_hero," after=",level.player.get_instance_id())

func _write_wav(buffer: PackedVector2Array, name: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buffer.size()*4)
	for i in buffer.size():
		bytes.encode_s16(i*4,int(clampf(buffer[i].x,-1,1)*32767))
		bytes.encode_s16(i*4+2,int(clampf(buffer[i].y,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = int(AudioServer.get_mix_rate())
	stream.data = bytes
	stream.save_to_wav(out+name)

func _cross(a: Vector3, b: Vector3, label: String) -> void:
	level._reset_position(a)
	await _ticks(30)
	var geometry_id: int = level.geometry.get_instance_id()
	await _shot(label+"-before")
	frame_times.clear()
	last_frame = Time.get_ticks_usec()
	sampling = true
	var middle := false
	var arrived := false
	max_gain_step = 0.0
	previous_gains = level.ambience.sources.map(func(s: Dictionary): return s.gain)
	checking_blend = true
	for tick in 500:
		var delta: Vector3 = b-level.player.global_position
		delta.y = 0
		if delta.length()<0.22:
			arrived = true
			break
		var axes: Vector2 = level.player.controls.world_direction_to_screen_axes(delta.normalized())
		Input.action_press(&"move_right",maxf(axes.x,0))
		Input.action_press(&"move_left",maxf(-axes.x,0))
		Input.action_press(&"move_back",maxf(axes.y,0))
		Input.action_press(&"move_forward",maxf(-axes.y,0))
		await _ticks(1)
		if not middle and delta.length()<a.distance_to(b)*0.5:
			middle = true
			await _shot(label+"-middle")
	sampling = false
	checking_blend = false
	for action in [&"move_right",&"move_left",&"move_back",&"move_forward"]:
		Input.action_release(action)
	await _ticks(6)
	await _shot(label+"-after")
	frame_times.sort()
	var p95 := frame_times[int(frame_times.size()*0.95)] if not frame_times.is_empty() else INF
	transitions.append({"label":label,"viewport":[root.size.x,root.size.y],"samples":frame_times.size(),"p95_ms":p95,"max_ms":frame_times[-1] if not frame_times.is_empty() else INF,"max_gain_step":max_gain_step,"arrived":arrived,"fixture":"cleared enemies; native input movement; screenshot readback excluded; not GPU timestamps"})
	_check(arrived and geometry_id==level.geometry.get_instance_id() and level.room_roots.size()==10,label+" physical crossing preserves the resident world")
	_check(max_gain_step<0.06,label+" sound blend remains continuous")
	_check(p95<16.67,label+" drawn-frame p95 within 16.67 ms")

func _drawn() -> void:
	var now := Time.get_ticks_usec()
	if sampling:
		frame_times.append(float(now-last_frame)/1000.0)
	last_frame = now

func _audio_step() -> void:
	# Observe every physics tick, including catch-up ticks after PNG readback.
	# Comparing only coroutine resumes incorrectly counts several ticks as one.
	if not checking_blend:
		return
	for i in previous_gains.size():
		max_gain_step = maxf(max_gain_step,absf(level.ambience.sources[i].gain-previous_gains[i]))
		previous_gains[i] = level.ambience.sources[i].gain

func _shot(label: String) -> void:
	var was_sampling := sampling
	sampling = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+label+".png")
	last_frame = Time.get_ticks_usec()
	sampling = was_sampling

func _ticks(count: int) -> void:
	for i in count:
		# Only dismiss the OS-focus pause panel, not the explicit clock tests.
		if is_instance_valid(level) and level._pause_panel.visible:
			level._resume_game()
		await physics_frame
		await process_frame
		paused = false

func _check(value: bool, label: String) -> void:
	checks.append({"check":label,"pass":value})
	print("PASS " if value else "FAIL ",label)

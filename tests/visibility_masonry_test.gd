extends "res://tests/visibility_combat_test.gd"

# Focused native probe of the same authored fight. Mouse motion drives the
# production first-contact cue; the probe never writes a shader parameter.
var masonry_trace: Array[Dictionary] = []
var focus_continuous := true
var _trace_owner := 0
var _previous_focus: Dictionary = {}
var _previous_focus_time := 0.0


func _initialize() -> void:
	out = "res://output/visibility_masonry_2026_10_15/focused/"
	part = "masonry"
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "images"))
	SlimeGameSettings.current().load_settings(out + "settings.cfg")
	SlimeGameSettings.current().camera_shake = 0.0
	create_timer(235.0, true).timeout.connect(func() -> void:
		_check(false, "bounded 235 second masonry watchdog")
		_finish())
	if DisplayServer.get_name() == "headless": capture = false
	else:
		root.size = Vector2i(1280, 720)
		DisplayServer.window_set_size(root.size)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if not await _fresh_scene(1): _finish(); return
	var geometry_before: Dictionary = _geometry_signature()
	var actors_before: Array = _actor_state()
	_check(_ghost_contract(1), "masonry copies the actual complete source wall and cap without adding collision or shadows")
	for angle: int in 4:
		await _angle(angle)
		level._reset_position(Vector3(-5.5, 0, -18))
		await _ticks(55)
		var choice: Dictionary = await _find_revealed_aim()
		# A clear camera needs no cutaway. Move to the real threshold only when
		# this angle has no disclosed wall at the western starting point.
		if choice.is_empty():
			level._reset_position(Vector3(-0.6, 0, -18))
			await _ticks(55)
			choice = await _find_revealed_aim()
		records.append({"case": "masonry-viewpoint", "angle": angle, "hero": _vec(level.player.global_position)})
		_check(not choice.is_empty(), "angle %d actual mouse aiming finds a revealed high wall blocking the shot" % angle)
		if choice.is_empty():
			await _shot("masonry-angle-%d-no-aim-candidate" % angle, 1, angle)
			continue
		var section: Dictionary = choice.section
		await _clear_aim()
		await _ticks(65)
		_check(float(section.focus_amount) < 0.001, "angle %d wall settles to its quiet translucent masonry" % angle)
		await _shot("masonry-angle-%d-idle" % angle, 1, angle)
		await _aim_world(choice.point)
		await _ticks(3)
		_check(level.barrier_feedback.blocked and float(section.focus_amount) > 0.0 and float(section.focus_amount) < 1.0, "angle %d blocked aiming begins a gradual emphasis rather than an instant switch" % angle)
		if angle == 0: await _pause_focus("rising", choice.point)
		await _ticks(35)
		_check(float(section.focus_amount) > 0.999 and _part_focus_matches(section), "angle %d blocked wall and its owned cap share completed emphasis" % angle)
		await _shot("masonry-angle-%d-aim" % angle, 1, angle)
		await _clear_aim()
		await _ticks(3)
		_check(float(section.focus_amount) > 0.99, "angle %d brief cursor departure does not flash the wall off" % angle)
		await _aim_world(choice.point)
		await _ticks(4)
		_check(level.barrier_feedback.blocked and float(section.focus_amount) > 0.99, "angle %d cursor return retains the same wall emphasis" % angle)
		await _clear_aim()
		await _ticks(17)
		_check(float(section.focus_amount) > 0.0 and float(section.focus_amount) < 1.0, "angle %d cursor departure fades emphasis after its hold" % angle)
		if angle == 0: await _pause_focus("falling", _clear_target())
		await _ticks(45)
		_check(_focus_values().values().all(func(value: float) -> bool: return value < 0.001), "angle %d old wall emphasis fully clears after cursor departure" % angle)
		await _shot("masonry-angle-%d-restored" % angle, 1, angle)
		_check(_ghost_contract(1), "angle %d all masonry copies retain their source shape and alignment" % angle)
		var record: Dictionary = _visibility_record(1, angle, "masonry-passage")
		visibility.append(record)
		_check(record.points.all(func(point: Dictionary) -> bool: return bool(point.clear) or not bool(point.required)), "angle %d structural reveal still protects hero and nearby warning floors" % angle)
	_check(_geometry_signature() == geometry_before and _actor_state() == actors_before, "four-angle mouse emphasis preserves every physical collider and frozen actor state")
	await _angle(0)
	level._reset_position(Vector3(-5.5, 0, -18))
	await _ticks(45)
	var last_choice: Dictionary = await _find_revealed_aim()
	if not last_choice.is_empty():
		await _ticks(30)
		level.set_compare_mode(0)
		await _ticks(75)
		_check(_ghost_contract(0), "full-wall A mode restores real architecture without leaving masonry copies visible")
		await _clear_aim()
		level.set_compare_mode(1)
		await _ticks(65)
		_check(_focus_values().values().all(func(value: float) -> bool: return value < 0.001), "returning to B does not resurrect an obsolete aiming emphasis")
	await _wall_motion(1)
	_check(_geometry_signature() == geometry_before, "actual walking and a full jump still meet the same physical masonry wall")
	if not await _fresh_scene(1): _finish(); return
	await _clear_aim()
	await _ticks(60)
	_check(_focus_values().values().all(func(value: float) -> bool: return value < 0.001), "fresh encounter contains no stale emphasized wall from the previous scene")
	_check(focus_continuous, "all observed focus changes respect elapsed-time bounds including pause and camera turns")
	records.append({"case": "masonry-scope", "scope": "Production mouse events and original source mesh identity. Native images require separate visual review; assertions do not prove human recognition of collision or subjective readability."})
	_finish()


func _find_revealed_aim() -> Dictionary:
	var origin: Vector3 = level.player.global_position + Vector3.UP * level.player._combat_origin_height()
	var candidates: Array = level.reveal.pilot_sections.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.world_bounds as AABB).get_center().distance_squared_to(origin) < (b.world_bounds as AABB).get_center().distance_squared_to(origin))
	for section: Dictionary in candidates:
		if float(section.reveal_amount) < 0.98: continue
		var bounds: AABB = section.world_bounds
		var center: Vector3 = bounds.get_center()
		center.y = origin.y
		var nearest := Vector3(clampf(origin.x, bounds.position.x + 0.1, bounds.end.x - 0.1), origin.y, clampf(origin.z, bounds.position.z + 0.1, bounds.end.z - 0.1))
		var along := Vector3(bounds.size.x * 0.35, 0, 0) if bounds.size.x > bounds.size.z else Vector3(0, 0, bounds.size.z * 0.35)
		for contact: Vector3 in [nearest, center, center + along, center - along]:
			var direction := (contact - origin).normalized()
			if direction.length_squared() < 0.01 or contact.distance_to(origin) > 20.0: continue
			var target := contact + direction * 1.5
			await _aim_world(target)
			await _ticks(2)
			records.append({"case": "aim-candidate", "angle": _view().camera_yaw, "section": section.id, "target": _vec(target), "blocked": bool(level.barrier_feedback.blocked), "hit": _vec(level.barrier_feedback.hit_position), "bounds": str(bounds)})
			if not level.barrier_feedback.blocked: continue
			for actual: Dictionary in candidates:
				if float(actual.reveal_amount) < 0.98: continue
				if (actual.world_bounds as AABB).grow(0.02).has_point(level.barrier_feedback.hit_position):
					return {"section": actual, "point": target}
	return {}


func _aim_world(point: Vector3) -> void:
	var pointer: Vector2 = _view().camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	level.player.controls.pointer = pointer
	await _ticks(1)


func _clear_target() -> Vector3:
	return level.player.global_position + Vector3.UP * level.player._combat_origin_height() + Vector3(0, 0, -0.8)


func _clear_aim() -> void:
	await _aim_world(_clear_target())
	await _ticks(1)
	_check(not level.barrier_feedback.blocked, "nearby open floor removes the real blocked-shot cue")


func _pause_focus(phase: String, resume_target: Vector3) -> void:
	var values: Dictionary = _focus_values()
	var uniforms: Dictionary = _focus_uniforms()
	var holds: Dictionary = {}
	for section: Dictionary in level.reveal.pilot_sections: holds[section.id] = float(section.focus_hold)
	var time_before: float = level.reveal.elapsed_update_time
	paused = true
	await _ticks(20)
	var holds_after: Dictionary = {}
	for section: Dictionary in level.reveal.pilot_sections: holds_after[section.id] = float(section.focus_hold)
	_check(values == _focus_values() and uniforms == _focus_uniforms() and holds == holds_after and is_equal_approx(time_before, level.reveal.elapsed_update_time), "pause freezes %s wall emphasis, all cap materials and its hold timer" % phase)
	paused = false
	await _aim_world(resume_target)


func _focus_values() -> Dictionary:
	var result: Dictionary = {}
	for section: Dictionary in level.reveal.pilot_sections: result[section.id] = float(section.focus_amount)
	return result


func _focus_uniforms() -> Dictionary:
	var result: Dictionary = {}
	for section: Dictionary in level.reveal.pilot_sections:
		for part: MeshInstance3D in section.ghost_parts:
			var material := part.material_override as ShaderMaterial
			result[String(part.get_path())] = material.get_shader_parameter("focus_amount")
	return result


func _part_focus_matches(section: Dictionary) -> bool:
	var value := -1.0
	for part: MeshInstance3D in section.ghost_parts:
		var material := part.material_override as ShaderMaterial
		var current := float(material.get_shader_parameter("focus_amount"))
		if value < 0.0: value = current
		if not is_equal_approx(current, value) or current < 0.99: return false
	return value >= 0.99


func _ticks(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame
		if not is_instance_valid(level) or not bool(level.get("ready_for_comparison")) or not is_instance_valid(level.reveal): continue
		var owner: int = level.reveal.get_instance_id()
		var now: float = level.reveal.elapsed_update_time
		var values := _focus_values()
		if owner == _trace_owner:
			var allowed := maxf(0.0, now - _previous_focus_time) / 0.18 + 0.00001
			for key: String in values:
				if _previous_focus.has(key): focus_continuous = focus_continuous and absf(float(values[key]) - float(_previous_focus[key])) <= allowed
		masonry_trace.append({"owner": owner, "time": now, "paused": paused, "focus": values})
		_trace_owner = owner
		_previous_focus = values
		_previous_focus_time = now


func _finish() -> void:
	if not finished:
		FileAccess.open(out + "masonry-trace.json", FileAccess.WRITE).store_string(JSON.stringify(masonry_trace))
	super._finish()

extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const R01_SCENE := preload("res://scenes/r01_entrance.tscn")
const R07_SCENE := preload("res://scenes/r07_guardian.tscn")
const V5_PREVIEW_SCENE := preload("res://scenes/art_review/slime_model_preview_v5.tscn")
const HERO_MESH := preload("res://assets/models/slime_hero_v5.res")
const WHIP_SHADER := preload("res://assets/shaders/slime_whip_v5.gdshader")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")

var _failures := 0
var _held_materials: Array[ShaderMaterial] = []
var _watchdog: Timer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	set_meta(&"checkpoint_active", false)
	_watchdog = Timer.new()
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog.one_shot = true
	_watchdog.wait_time = 60.0
	root.add_child(_watchdog)
	_watchdog.timeout.connect(_on_timeout)
	_watchdog.start()

	_report("H01 R02 main hero", await _check_scene(MAIN_SCENE))
	_report("H02 R01 hero", await _check_scene(R01_SCENE))
	_report("H03 R07 hero", await _check_scene(R07_SCENE))
	_report("H04 v5 preview uses shared hero", await _check_scene(V5_PREVIEW_SCENE))
	_report("H05 action, pause and death visuals", await _check_visual_lifecycle())
	_report("H06 R07 camera start clearance", await _check_r07_camera())

	paused = false
	_held_materials.clear()
	_watchdog.stop()
	_watchdog.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("HERO_FINAL_SUMMARY: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _on_timeout() -> void:
	paused = false
	print("FAIL TIMEOUT: hero final test exceeded 60 seconds")
	quit(124)


func _check_scene(scene_resource: PackedScene) -> String:
	var fixture := scene_resource.instantiate() as Node3D
	root.add_child(fixture)
	await _frames(2)
	var player := fixture.get_node_or_null("SlimePlayer") as SlimeController
	var problem := _check_player(player)
	fixture.queue_free()
	await _frames(2)
	return problem


func _check_r07_camera() -> String:
	var fixture := R07_SCENE.instantiate() as Node3D
	root.add_child(fixture)
	await _frames(6)
	var player := fixture.get_node_or_null("SlimePlayer") as SlimeController
	var problem := ""
	if player == null:
		problem = "R07 has no SlimePlayer"
	else:
		var hit_length := player.spring_arm.get_hit_length()
		print("H06 R07 spring arm hit_length=%.3f m" % hit_length)
		if hit_length < 4.3:
			problem = "R07 starts with camera arm clipped to %.3f m" % hit_length
	fixture.queue_free()
	await _frames(2)
	return problem

func _check_player(player: SlimeController) -> String:
	if player == null:
		return "scene has no SlimePlayer"
	var model := player.get_node_or_null("VisualRoot/SlimeHeroModelV5") as SlimeHeroVisual
	if model == null:
		return "shared player has no SlimeHeroModelV5"
	if model.mesh != HERO_MESH or model.mesh.get_surface_count() != 4:
		return "hero does not use the four-surface v5 mesh"
	var model_count := 0
	for child in player.visual_root.get_children():
		if child is MeshInstance3D:
			model_count += 1
	if model_count != 1:
		return "VisualRoot contains %d mesh instances instead of one v5 model" % model_count
	for surface_index in range(4):
		var source := model.mesh.surface_get_material(surface_index) as ShaderMaterial
		var local := model.get_surface_override_material(surface_index) as ShaderMaterial
		if source == null or local == null or source == local:
			return "surface %d has no private shader material" % surface_index
		if _held_materials.has(local):
			return "surface %d shares material with another hero instance" % surface_index
		_held_materials.append(local)
	var whip := model.get_node_or_null("SlimeWhip") as SlimeWhipVisual
	if whip == null:
		return "SlimeWhip is not a child of the animated v5 model"
	var tendril := whip.get_node_or_null("Tendril") as MeshInstance3D
	if tendril == null or not tendril.material_override is ShaderMaterial:
		return "tendril has no shader material"
	if (tendril.material_override as ShaderMaterial).shader != WHIP_SHADER:
		return "tendril does not use the v5 shader"
	return ""


func _check_visual_lifecycle() -> String:
	var fixture := Node3D.new()
	fixture.name = "HeroVisualLifecycleFixture"
	var player := PLAYER_SCENE.instantiate() as SlimeController
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	fixture.add_child(player)
	root.add_child(fixture)
	await _frames(3)
	var problem := _check_player(player)
	if not problem.is_empty():
		fixture.queue_free()
		await _frames(2)
		return problem
	var model := player.get_node("VisualRoot/SlimeHeroModelV5") as SlimeHeroVisual
	var before_action := model.scale
	if not player.request_action(&"slime_whip"):
		problem = "slime whip action did not start"
	else:
		await _frames(3)
		if float(model.get("_action_pulse")) <= 0.0 or model.scale.distance_to(before_action) < 0.003:
			problem = "whip action did not animate the v5 model"
	if problem.is_empty():
		var before_pause := float(model.get("_visual_time"))
		paused = true
		await create_timer(0.12, true, false).timeout
		var during_pause := float(model.get("_visual_time"))
		paused = false
		await _frames(2)
		var after_pause := float(model.get("_visual_time"))
		if absf(during_pause - before_pause) > 0.0001 or after_pause <= during_pause:
			problem = "v5 visual time did not pause and resume with the game"
	if problem.is_empty():
		player.apply_environment_damage(SlimeController.MAX_HEALTH)
		var at_death := float(model.get("_visual_time"))
		await create_timer(0.12, true, false).timeout
		if player.is_alive() or absf(float(model.get("_visual_time")) - at_death) > 0.0001:
			problem = "v5 visual time continued after player death"
	fixture.queue_free()
	await _frames(2)
	return problem


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _report(case_name: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % case_name)
	else:
		_failures += 1
		print("FAIL %s: %s" % [case_name, problem])

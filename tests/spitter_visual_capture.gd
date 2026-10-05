extends SceneTree

const PREVIEW = preload("res://scenes/art_review/spitter_model_preview.tscn")
const OUTPUT := "res://output/S5/art_review/spitter/v4/"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var preview := PREVIEW.instantiate()
	root.add_child(preview)
	preview.automatic = false
	preview.set_process(false)
	preview.enemy.set_process(false)
	await _frames(4)
	await _save("01_idle_three_quarter.png")
	preview.yaw = 0.0
	preview._update_camera()
	await _save("02_front.png")
	preview.enemy.model._time = 4.10
	preview.enemy.model.animate(0.09, Vector3.ZERO, &"idle", 0.0)
	await _save("02b_blink.png")
	preview.enemy.model._time = 0.0
	preview.enemy.model.animate(0.01, Vector3.ZERO, &"idle", 0.0)
	preview.yaw = -PI * 0.5
	preview._update_camera()
	await _save("03_side.png")
	preview.yaw = PI
	preview._update_camera()
	await _save("04_back.png")
	preview.yaw = -0.46
	preview._update_camera()
	preview.select_mode(2)
	preview.enemy.set_process(false)
	preview.enemy._phase_left = 0.05
	preview.enemy._process(1.0 / 60.0)
	await _save("05_windup.png")
	preview.enemy._set_phase(Spitter.Phase.RECOVERY, 1.30)
	preview.enemy._phase_left = 1.16
	preview.enemy._process(1.0 / 60.0)
	await _save("06_recoil.png")
	preview.select_mode(3)
	preview.enemy.set_process(false)
	preview.enemy.receive_hit(10, "capture_hit", &"player")
	preview.enemy._process(0.11)
	await _save("07_hurt.png")
	preview.select_mode(4)
	preview.enemy.set_process(false)
	var corpse: SpitterVisual = preview.enemy.model
	preview.enemy.receive_hit(30, "capture_death", &"player")
	corpse.set_process(false)
	corpse._process(0.38)
	await _save("08_death.png")
	corpse._process(0.62)
	await _save("08b_fallen_crosses.png")
	preview.yaw = 0.0
	preview._update_camera()
	await _save("08c_fallen_front.png")
	preview.yaw = -0.46
	preview._update_camera()
	preview.automatic = true
	preview.select_mode(0)
	# Capture the same playable model through all review states at fixed frame time.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "motion"))
	var frame_count := 0 if OS.get_cmdline_user_args().has("--stills-only") else 375
	for frame in frame_count:
		preview._process(1.0 / 30.0)
		if is_instance_valid(preview.enemy):
			preview.enemy.set_process(false)
			preview.enemy._process(1.0 / 30.0)
		for remains: SpitterVisual in get_nodes_in_group(&"spitter_remains"):
			if not remains.is_queued_for_deletion():
				remains.set_process(false)
				remains._process(1.0 / 30.0)
		await _save("motion/frame_%04d.png" % frame, false)
	preview.queue_free()
	await _frames(3)
	await _capture_combat()
	# A real-time audio mixer needs a little wall time to release its last stream.
	var settings := root.get_node_or_null("GameSettings")
	if settings != null:
		settings.queue_free()
	await create_timer(0.12).timeout
	print("CAPTURE_SUMMARY failures=%d" % failures)
	call_deferred("quit", 0 if failures == 0 else 1)


func _capture_combat() -> void:
	set_meta(&"checkpoint_active", false)
	var battle := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	var player: SlimeController = battle.player
	var enemy: Spitter = battle.first_enemy
	player.global_position = Vector3(0.0, 0.05, 4.9)
	await _frames(18)
	await _save("09_in_combat.png")
	# Stage a close-range hit with the real whip action and unchanged damage path.
	enemy.player_target = null
	enemy.velocity = Vector3.ZERO
	enemy.set_physics_process(false)
	enemy._set_phase(Spitter.Phase.IDLE, 0.0)
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 1.65)
	player.velocity = Vector3.ZERO
	await _frames(5)
	for hit in 3:
		var started := player.request_action(&"slime_whip")
		for frame in 120:
			await physics_frame
			if player._action == &"":
				break
		await process_frame
		print("COMBAT_WHIP index=%d started=%s hp=%d" % [hit + 1, started, enemy.health if is_instance_valid(enemy) else 0])
		if not started:
			failures += 1
	await _frames(60)
	await _save("10_death_and_source.png")
	if battle.stage != &"absorb" or not is_instance_valid(battle.first_source):
		failures += 1
		print("FAIL COMBAT_DEATH_SOURCE")
	else:
		print("PASS COMBAT_DEATH_SOURCE")
	battle.queue_free()
	await _frames(5)


func _save(file: String, announce: bool = true) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file))
	if result != OK:
		failures += 1
	if announce:
		print("CAPTURE %s code=%d" % [file, result])


func _frames(count: int) -> void:
	for frame in count:
		await process_frame

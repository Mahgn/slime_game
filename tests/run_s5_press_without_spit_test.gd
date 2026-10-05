extends SceneTree

# Acceptance check: both two-slot builds without sticky spit can cross R06
# during the press's natural open phase, without modifying its phase by hand.
const ROOM_SCENE := preload("res://scenes/r06_press.tscn")
const OUTPUT_DIR := "res://output/S5/acceptance_v4/"
const LOADOUTS := [
	{"id": "shell_spikes", "slot_one": &"elastic_shell", "slot_two": &"slime_spikes"},
	{"id": "spikes_shell", "slot_one": &"slime_spikes", "slot_two": &"elastic_shell"},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta(&"checkpoint_active", false)
	var all_passed := true
	for loadout: Dictionary in LOADOUTS:
		all_passed = (await _check_loadout(loadout)) and all_passed
	print("PASS S5_PRESS_WITHOUT_SPIT" if all_passed else "FAIL S5_PRESS_WITHOUT_SPIT")
	paused = false
	Input.action_release(&"move_forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(0 if all_passed else 1)


func _check_loadout(loadout: Dictionary) -> bool:
	set_meta(&"r05_entry", {"slot_one": loadout["slot_one"], "slot_two": loadout["slot_two"]})
	var room := ROOM_SCENE.instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await _steps(8)
	var player := room.get_node("SlimePlayer") as SlimeController
	var correct_loadout: bool = (
		player.get_slot_ability(1) == loadout["slot_one"]
		and player.get_slot_ability(2) == loadout["slot_two"]
		and player.get_slot_ability(1) != &"sticky_spit"
		and player.get_slot_ability(2) != &"sticky_spit"
	)
	player.global_position = Vector3(0.0, 0.05, 2.6)
	player.velocity = Vector3.ZERO
	await _steps(4)
	var natural_open := false
	for tick in 240:
		if room.get("press_phase") == &"open" and float(room.get("phase_left")) > 2.2 and is_zero_approx(float(room.get("sticky_open_left"))):
			natural_open = true
			break
		await physics_frame
	if natural_open:
		_save_frame("%s_before.png" % loadout["id"])
		Input.action_press(&"move_forward")
		for tick in 85:
			await physics_frame
			if player.global_position.z < -1.6:
				break
		Input.action_release(&"move_forward")
		_save_frame("%s_after.png" % loadout["id"])
	var crossed := player.global_position.z < -1.6
	var unhurt := player.health == player.MAX_HEALTH
	var no_sticky := is_zero_approx(float(room.get("sticky_open_left")))
	var passed: bool = correct_loadout and natural_open and crossed and unhurt and no_sticky
	print("S5_NO_SPIT_%s loadout=%s natural_open=%s crossed=%s health=%d no_sticky=%s z=%.3f" % [
		loadout["id"], correct_loadout, natural_open, crossed, player.health, no_sticky, player.global_position.z
	])
	print("PASS S5_NO_SPIT_%s" % loadout["id"] if passed else "FAIL S5_NO_SPIT_%s" % loadout["id"])
	current_scene = null
	room.queue_free()
	await _steps(8)
	return passed


func _save_frame(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var image := root.get_texture().get_image()
	var result := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + filename))
	if result != OK:
		push_error("Could not save %s: %d" % [filename, result])


func _steps(count: int) -> void:
	for tick in count:
		await physics_frame

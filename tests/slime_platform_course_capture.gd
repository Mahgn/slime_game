extends SceneTree

const COURSE_SCENE = preload("res://scenes/art_review/slime_platform_course.tscn")
const OUTPUT := "res://output/S5/platform_course_revision/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var course := COURSE_SCENE.instantiate()
	root.add_child(course)
	await _frames(12)
	_save("view_start.png")
	var player: SlimeController = course.player
	var wall: FragileWall = course._fragile_wall
	wall.receive_hit(30, "capture:slime_whip", &"player")
	player.global_position = Vector3(0.0, 0.05, 10.5)
	player.velocity = Vector3.ZERO
	await _frames(18)
	_save("view_wall_hole.png")
	player.global_position = Vector3(0.0, 1.75, 0.5)
	player.velocity = Vector3.ZERO
	await _frames(15)
	_save("view_platforms.png")
	player.global_position = Vector3(0.0, 1.85, -9.3)
	player.velocity = Vector3.ZERO
	await _frames(15)
	_save("view_gap_to_press.png")
	player.global_position = Vector3(0.0, 0.05, -13.15)
	player.velocity = Vector3.ZERO
	course._info_left = 0.0
	course._press_motion_time = course.PRESS_PERIOD * 0.65
	await _frames(6)
	course._on_sticky_applied()
	await _frames(2)
	_save("view_press_low.png")
	course._press_frozen_left = 0.0
	course._press_motion_time = course.PRESS_PERIOD * 0.15
	await _frames(6)
	course._on_sticky_applied()
	await _frames(2)
	_save("view_press_high.png")
	quit()

func _frames(count: int) -> void:
	for frame in count:
		await process_frame

func _save(name: String) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT + name)
	var result := root.get_texture().get_image().save_png(path)
	print("CAPTURE %s code=%d" % [path, result])




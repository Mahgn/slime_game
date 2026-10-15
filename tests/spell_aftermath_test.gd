extends SceneTree

const HIT_VISUAL := preload("res://scripts/combat/actor_hit_visual.gd")
const ENEMY_SCENE := preload("res://scenes/enemies/spitter.tscn")
const CREATURE := preload("res://scripts/dungeon/dungeon_creature.gd")
const PROFILES := preload("res://scripts/combat/impact_profiles.gd")
const OUTPUT := "res://output/spell_juice_2026_10_15/"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var done := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	create_timer(30.0, true, false, true).timeout.connect(func() -> void:
		_check(false, "watchdog: aftermath checks finish")
		_finish())
	await _test_overlay_lifecycle()
	await _test_real_creature()
	_finish()


func _test_overlay_lifecycle() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var pose := HIT_VISUAL.new() as SlimeActorHitVisual
	fixture.add_child(pose)
	var art := Node3D.new()
	pose.add_child(art)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	var normal := StandardMaterial3D.new()
	var original_overlay := StandardMaterial3D.new()
	mesh.material_override = normal
	mesh.material_overlay = original_overlay
	art.add_child(mesh)
	pose.bind_visual(art)
	var profile := PROFILES.ACID.duplicate(true) as SlimeImpactProfile
	profile.flash_seconds = 0.05
	profile.aftermath_seconds = 0.32
	profile.aftermath_color = Color(0.45, 0.85, 0.13, 0.16)
	var original_profile_color := profile.aftermath_color
	pose.play_hit(Vector3.RIGHT, profile)
	_check(mesh.material_overlay == pose._flash_material and pose._flash_material.albedo_color.a > 0.9, "confirmed hit begins with its existing bright flash")
	pose._process(0.03)
	_check(is_equal_approx(pose._aftermath_left, 0.32), "afterglow lifetime is held until the brief hit flash ends")
	pose._process(0.03)
	_check(is_equal_approx(pose._aftermath_left, 0.31), "frame crossing the flash boundary counts only leftover time toward afterglow")
	_check(mesh.material_overlay == pose._flash_material and pose._flash_material.albedo_color.a <= 0.18 and pose._flash_material.albedo_color.g > pose._flash_material.albedo_color.r, "flash transitions into a subtle acid tint using the same actor-local material")
	_check(not pose._flash_material.no_depth_test, "afterglow keeps depth testing against walls")
	_check(mesh.material_override == normal and original_overlay.albedo_color == Color.WHITE and profile.aftermath_color == original_profile_color, "afterglow never mutates the base material, prior overlay or shared profile data")
	paused = true
	var age := pose._aftermath_left
	var tint := pose._flash_material.albedo_color
	var pose_transform := pose.transform
	await create_timer(0.12, true, false, true).timeout
	_check(is_equal_approx(age, pose._aftermath_left) and pose._flash_material.albedo_color == tint and pose.transform == pose_transform, "pause freezes both the tint lifetime and the visible recoil")
	paused = false
	pose._process(0.40)
	_check(mesh.material_overlay == original_overlay and not pose.is_processing(), "expiration restores the previous overlay and stops idle processing")
	_check(pose.position.is_equal_approx(Vector3.ZERO) and pose.scale.is_equal_approx(Vector3.ONE), "afterglow does not prolong visual displacement after recoil ends")
	profile.flash_seconds = 0.0
	profile.aftermath_seconds = 10.0
	profile.aftermath_color.a = 1.0
	pose.play_hit(Vector3.LEFT, profile)
	_check(is_equal_approx(pose._aftermath_left, 0.6) and is_equal_approx(pose._flash_material.albedo_color.a, 0.18), "out-of-range authoring is clamped to a short transparent cosmetic accent")
	pose._process(0.2)
	pose.play_hit(Vector3.FORWARD, PROFILES.WHIP)
	_check(pose._aftermath_left == 0.0, "a subsequent ordinary whip replaces the previous spell tint without a stale timer")
	pose._process(0.4)
	_check(mesh.material_overlay == original_overlay, "replacement hit also restores the original overlay")
	profile.flash_seconds = 0.05
	profile.aftermath_seconds = 0.45
	profile.aftermath_color = Color(0.9, 0.9, 1.0, 0.14)
	pose.play_hit(Vector3.RIGHT, profile)
	pose.become_remains(Vector3.ZERO)
	pose._process(0.30)
	_check(pose._death_elapsed == pose.DEATH_SECONDS and pose._aftermath_left > 0.0 and pose.is_processing(), "a defeated actor can finish a cosmetic tint after its collapse completes")
	pose._process(0.30)
	_check(mesh.material_overlay == original_overlay and not pose.is_processing(), "remains restore the overlay instead of retaining a permanent spell color")
	pose.play_hit(Vector3.RIGHT, profile)
	_check(not pose.is_processing() and pose._aftermath_left == 0.0, "late hit presentation cannot restart a defeated actor")
	fixture.queue_free()
	await process_frame
	_check(not is_instance_valid(pose), "removing the owning scene removes the complete aftermath node")


func _test_real_creature() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.set_script(CREATURE)
	fixture.add_child(enemy)
	enemy.set_physics_process(false)
	var pose := enemy.get("_impact_pose") as SlimeActorHitVisual
	var original_root := enemy.transform
	var profile := PROFILES.ACID.duplicate(true) as SlimeImpactProfile
	profile.aftermath_seconds = 0.32
	profile.aftermath_color = Color(0.45, 0.85, 0.13, 0.16)
	_check(enemy.receive_attack_hit(4, "aftermath-actual-hit", &"player", Vector3.RIGHT, profile), "real dungeon creature accepts a valid acid hit")
	_check(enemy.health == 26 and pose._aftermath_left == 0.32, "actual HP confirmation drives the existing creature art aftermath")
	var before := pose._flash_left
	_check(not enemy.receive_attack_hit(4, "aftermath-actual-hit", &"player", Vector3.RIGHT, profile) and pose._flash_left == before, "duplicate cast does not restart visual feedback or damage")
	_check(not enemy.receive_attack_hit(4, "aftermath-wrong-team", &"enemy", Vector3.RIGHT, profile), "invalid team cannot trigger creature aftermath")
	pose._process(0.7)
	_check(enemy.health == 26 and enemy.get_sticky_time_left() == 0.0, "acid tint expiry does not create damage-over-time or any new status")
	_check(enemy.transform == original_root, "spell tint and recoil keep the physical creature root unchanged")
	enemy.apply_sticky(0.55, 3.0)
	enemy.receive_attack_hit(4, "aftermath-web-hit", &"player", Vector3.RIGHT, PROFILES.WEB)
	pose._process(0.8)
	_check(enemy.health == 22 and is_equal_approx(enemy.get_sticky_time_left(), 3.0), "cosmetic web aftermath never shortens the separate gameplay sticky status or timer")
	enemy.receive_attack_hit(999, "aftermath-lethal-hit", &"player", Vector3.RIGHT, profile)
	await process_frame
	_check(not is_instance_valid(enemy) and is_instance_valid(pose) and pose.is_in_group(&"dungeon_creature_remains"), "real lethal hit preserves the existing remains lifecycle while its cosmetic tint finishes")
	pose._process(0.8)
	_check(not pose.is_processing() and pose._aftermath_left == 0.0, "real creature remains stop after all visual stages finish")
	fixture.queue_free()
	await process_frame


func _check(ok: bool, label: String) -> void:
	checks.append({"check": label, "pass": ok})
	if not ok:
		failures.append(label)
	print("PASS " if ok else "FAIL ", label)


func _finish() -> void:
	if done:
		return
	done = true
	paused = false
	var file := FileAccess.open(OUTPUT + "aftermath-checks.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("SPELL_AFTERMATH_RESULT checks=%d failures=%d" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

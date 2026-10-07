extends SceneTree

const ENEMY_SCENE = preload("res://scenes/enemies/spitter.tscn")
var failures := 0
var shot_count := 0
var death_count := 0
var shot_origin := Vector3.ZERO
var shot_damage := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var room := Node3D.new()
	root.add_child(room)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.2, 30.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	room.add_child(floor_body)
	var target := Node3D.new()
	target.position = Vector3(0.0, 0.0, -5.0)
	room.add_child(target)
	var enemy := _spawn(room)
	var other := _spawn(room)
	other.position.x = 4.0
	enemy.set_physics_process(false)
	other.set_physics_process(false)
	await _frames(2)
	var collider: CapsuleShape3D = enemy.get_node("CollisionShape3D").shape
	_check("P01_MODEL_AND_COLLIDER", enemy.model.body.mesh is ArrayMesh and is_equal_approx(collider.radius, 0.48) and is_equal_approx(collider.height, 1.35))
	var initial_muzzle := enemy.muzzle.transform
	enemy.set_process(false)
	other.set_process(false)
	var initial_foot: Transform3D = enemy.model.legs[0].get_node("Foot").transform
	for frame in 15:
		enemy.model.animate(1.0 / 60.0, Vector3(0.0, 0.0, -2.5), &"idle", 0.0)
	_check("P02_WALK_VISUAL_ONLY", not enemy.model.legs[0].get_node("Foot").transform.is_equal_approx(initial_foot) and enemy.scale == Vector3.ONE and enemy.muzzle.transform == initial_muzzle)
	enemy.model.animate(0.1, Vector3.ZERO, &"windup", 0.95)
	_check("P03_POUCH_TELEGRAPH", float((enemy.model.body.material_override as ShaderMaterial).get_shader_parameter("charge_amount")) > 0.95 and float((enemy.model.mouth.get_node("Lip").material_override as ShaderMaterial).get_shader_parameter("open_amount")) > 0.95 and enemy.model.mouth.scale == Vector3.ONE)
	var other_material := other.model.body.material_override as ShaderMaterial
	enemy.receive_hit(10, "hurt_unique", &"player")
	enemy.model.animate(0.11, Vector3.ZERO, &"windup", 0.95)
	_check("P04_HURT_ISOLATED", enemy.model.body.material_override != other_material and float(other_material.get_shader_parameter("hit_amount")) == 0.0 and float((enemy.model.body.material_override as ShaderMaterial).get_shader_parameter("hit_amount")) > 0.8)
	_check("P05_HIT_DEDUP", not enemy.receive_hit(10, "hurt_unique", &"player") and enemy.health == 20)
	var planted_feet: Array[Vector3] = []
	for leg in other.model.legs:
		planted_feet.append(leg.get_node("Foot").global_position)
	var feet_stay_planted := true
	for frame in 45:
		other.model.animate(1.0 / 60.0, Vector3.ZERO, &"windup", float(frame) / 45.0)
		for index in other.model.legs.size():
			var foot: Node3D = other.model.legs[index].get_node("Foot")
			feet_stay_planted = feet_stay_planted and foot.global_position.distance_to(planted_feet[index]) < 0.001 and foot.global_basis.y.distance_to(Vector3.UP) < 0.001
	_check("P15_STANCE_FEET_DURING_BREATH_AND_WINDUP", feet_stay_planted)
	other.model._time = 4.10
	other.model.animate(0.09, Vector3.ZERO, &"idle", 0.0)
	var eyelid_material := other.model.left_lid.get_node("Iris").material_override as ShaderMaterial
	_check("P20_EYELIDS_WITHOUT_SQUASHING_EYES", float(eyelid_material.get_shader_parameter("blink_amount")) > 0.9 and other.model.left_lid.scale == Vector3.ONE)
	var head_before := other.model.face.transform
	other.model.animate(0.15, Vector3(0.0, 0.0, -2.5), &"recovery", 0.12)
	var head_pose: Transform3D = other_material.get_shader_parameter("head_pose")
	_check("P21_ARTICULATED_FACE", not head_before.is_equal_approx(other.model.face.transform) and head_pose.is_equal_approx(other.model.face.transform) and other.model.body.scale == Vector3.ONE)
	var limbs_bend := true
	for leg in other.model.legs:
		limbs_bend = limbs_bend and leg.scale.is_equal_approx(Vector3.ONE)
	_check("P22_LIMBS_KEEP_THICKNESS", limbs_bend)
	other.model._step = 0.05
	other.model._movement = 1.0
	var walk_velocity := Vector3(0.0, 0.0, -0.8)
	other.model.animate(0.0, walk_velocity, &"idle", 0.0)
	var support_start: Vector3 = other.model.legs[0].get_node("Foot").global_position
	for frame in 5:
		other.position += walk_velocity / 60.0
		other.model.animate(1.0 / 60.0, walk_velocity, &"idle", 0.0)
	var support_end: Vector3 = other.model.legs[0].get_node("Foot").global_position
	_check("P23_SLOW_STANCE_WITHOUT_SLIDING", support_start.distance_to(support_end) < 0.001)
	enemy._set_phase(Spitter.Phase.IDLE, 0.0)
	enemy.player_target = target
	enemy.set_physics_process(true)
	enemy.set_process(true)
	await _physics(20)
	var windup_before := enemy._phase_left
	enemy.receive_hit(1, "during_windup", &"player")
	_check("P06_HURT_PRESERVES_ATTACK", enemy.get_attack_phase() == &"windup" and enemy._phase_left == windup_before)
	await _physics(31)
	_check("P07_ONE_REAL_SHOT", shot_count == 1 and shot_damage == 8 and enemy.get_attack_phase() == &"recovery")
	_check("P08_MOUTH_ALIGNMENT", shot_origin.distance_to(enemy.muzzle.global_position) < 0.01 and enemy.model.mouth.to_global(Vector3(0.0, 0.0, -0.07)).distance_to(enemy.muzzle.global_position) < 0.12)
	var remains := enemy.model
	enemy.receive_hit(30, "kill", &"player")
	_check("P09_DEATH_ONCE", death_count == 1 and not enemy.is_in_group(&"enemies") and enemy.collision_layer == 0 and not enemy.receive_hit(30, "again", &"player") and remains.get_parent() == room)
	_check("P16_DEATH_CROSSES_REPLACE_EYES", not remains.left_lid.visible and not remains.right_lid.visible and remains.dead_eyes[0].visible and remains.dead_eyes[1].visible)
	await _frames(3)
	_check("P10_COMBAT_DISPOSED", not is_instance_valid(enemy) and is_instance_valid(remains) and remains.is_in_group(&"spitter_remains"))
	paused = true
	var death_pose := remains.rig.transform
	var death_age := remains._death_time
	await _frames(15)
	_check("P11_DEATH_PAUSE", remains.rig.transform == death_pose and remains._death_time == death_age)
	paused = false
	var full_size_fall := true
	for frame in 90:
		await _physics(1)
		full_size_fall = full_size_fall and is_instance_valid(remains) and remains.rig.scale.is_equal_approx(Vector3.ONE) and remains.body.scale.is_equal_approx(Vector3.ONE)
	_check("P17_NO_SHRINK_DURING_FALL", full_size_fall)
	_check("P12_DEATH_FINISH", is_instance_valid(remains) and remains.animation_state == &"dead" and not remains.is_processing() and remains.rig.basis.y.dot(Vector3.UP) < 0.25)
	var lowest := _lowest_world_vertex(remains)
	var side_lowest := INF
	for vertex: Vector3 in remains.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var head_weight := smoothstep(-0.35, -0.15, vertex.y) * (1.0 - smoothstep(-0.22, 0.22, vertex.z))
		vertex = vertex.lerp(remains.face.transform * (vertex - SpitterVisual.HEAD_PIVOT), head_weight)
		side_lowest = minf(side_lowest, remains.body.to_global(vertex).y)
	print("FALL_CONTACT surface=%.5f body=%.5f" % [lowest, side_lowest])
	_check("P18_FALL_RESTS_ON_FLOOR", lowest > -0.01 and lowest < 0.018 and side_lowest < 0.018)
	var fallen_pose := remains.rig.transform
	await _physics(180)
	_check("P19_CORPSE_STAYS_FULL_SIZE", is_instance_valid(remains) and remains.rig.transform == fallen_pose and remains.dead_eyes[0].is_visible_in_tree())
	room.queue_free()
	await _frames(3)
	var clean_restarts := true
	for iteration in 10:
		var temporary_room := Node3D.new()
		root.add_child(temporary_room)
		var temporary_enemy := _spawn(temporary_room)
		var art := temporary_enemy.model
		temporary_enemy.receive_hit(30, "restart_%d" % iteration, &"player")
		temporary_room.queue_free()
		await _frames(2)
		clean_restarts = clean_restarts and not is_instance_valid(art) and get_nodes_in_group(&"spitter_remains").is_empty() and get_nodes_in_group(&"enemies").is_empty()
	_check("P13_TEN_RESTARTS_MID_DEATH", clean_restarts)
	print("SUMMARY: %d failed" % failures)
	call_deferred("quit", 0 if failures == 0 else 1)


func _spawn(parent: Node3D) -> Spitter:
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	parent.add_child(enemy)
	enemy.projectile_requested.connect(_shot)
	enemy.died.connect(_died)
	return enemy


func _lowest_world_vertex(art: SpitterVisual) -> float:
	var lowest := INF
	for node in art.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not mesh_node.is_visible_in_tree() or mesh_node == art.ground_contact:
			continue
		var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if mesh_node == art.body:
				var head_weight := smoothstep(-0.35, -0.15, vertex.y) * (1.0 - smoothstep(-0.22, 0.22, vertex.z))
				vertex = vertex.lerp(art.face.transform * (vertex - SpitterVisual.HEAD_PIVOT), head_weight)
			lowest = minf(lowest, mesh_node.to_global(vertex).y)
	return lowest


func _shot(_source: Spitter, origin: Vector3, _direction: Vector3, damage: int, _speed: float, _range: float, _key: String) -> void:
	shot_count += 1
	shot_origin = origin
	shot_damage = damage


func _died(_source: Spitter, _ability_id: StringName, _at: Vector3) -> void:
	death_count += 1


func _check(id: String, result: bool) -> void:
	print("%s %s" % ["PASS" if result else "FAIL", id])
	if not result:
		failures += 1


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _physics(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame

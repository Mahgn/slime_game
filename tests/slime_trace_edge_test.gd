extends SceneTree


const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const EDGE_X := 0.0
const EDGE_TOLERANCE := 0.015
const VISIBLE_ALPHA := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_report("E01 crawl trail at floor edge", await _crawl_at_edge())
	_report("E02 landing splash at floor edge", await _land_at_edge())
	_report("E03 whip mark at wall edge", await _mark_at_edge())
	_report("E04 crawl above lower floor", await _crawl_at_edge(true))
	_report("E05 landing above lower floor", await _land_at_edge(true))
	print("SLIME_TRACE_EDGE_SUMMARY: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _crawl_at_edge(with_lower_floor: bool = false) -> String:
	var fixture := _make_floor_fixture(with_lower_floor)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	if player == null:
		await _discard(fixture)
		return "SlimeController failed to load"
	var trail := player.get_node_or_null("GroundTrail") as SlimeGroundTrail
	if trail == null:
		await _discard(fixture)
		return "GroundTrail missing"
	await _physics_steps(2)
	# The center of the hero remains on the platform while half of its
	# 0.83 m wide deposit would extend past the x=0 collision edge.
	for step in range(10):
		player.global_position = Vector3(-0.20, 0.0, -0.90 + float(step) * 0.20)
		trail._sample_ground()
	var draw_start := Time.get_ticks_usec()
	trail._draw_effect()
	print("  draw=%d us, support rays=%s" % [Time.get_ticks_usec() - draw_start, str(trail.get("_support_rays_last_draw"))])
	var problem := _check_mesh_on_face(trail, -0.40, -0.09, 8)
	await _discard(fixture)
	return problem


func _land_at_edge(with_lower_floor: bool = false) -> String:
	var fixture := _make_floor_fixture(with_lower_floor)
	var player := fixture.get_node("SlimePlayer") as SlimeController
	if player == null:
		await _discard(fixture)
		return "SlimeController failed to load"
	var trail := player.get_node_or_null("GroundTrail") as SlimeGroundTrail
	if trail == null:
		await _discard(fixture)
		return "GroundTrail missing"
	player.global_position = Vector3(-0.20, 0.0, 0.0)
	await _physics_steps(2)
	trail.add_landing_splash(8.0)
	var draw_start := Time.get_ticks_usec()
	trail._draw_effect()
	print("  draw=%d us, support rays=%s" % [Time.get_ticks_usec() - draw_start, str(trail.get("_support_rays_last_draw"))])
	var problem := _check_mesh_on_face(trail, -0.45, -0.09, 8)
	await _discard(fixture)
	return problem


func _mark_at_edge() -> String:
	var fixture := Node3D.new()
	fixture.name = "WallEdgeFixture"
	var wall := StaticBody3D.new()
	wall.name = "HalfWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(-1.0, 1.0, -0.10)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.20)
	shape_node.shape = shape
	wall.add_child(shape_node)
	fixture.add_child(wall)
	root.add_child(fixture)
	await _physics_steps(2)
	# Contact point is on the front plane, only 0.12 m from its right edge.
	var mark := SlimeWallImpactMark.spawn(fixture, Vector3(-0.12, 1.0, 0.0), Vector3.BACK, Vector3.RIGHT)
	if mark == null:
		await _discard(fixture)
		return "wall contact did not create a mark"
	var problem := _check_mesh_on_face(mark, -0.18, -0.08, 8)
	await _discard(fixture)
	return problem


func _make_floor_fixture(with_lower_floor: bool = false) -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "FloorEdgeFixture"
	var floor := StaticBody3D.new()
	floor.name = "HalfFloor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	floor.position = Vector3(-1.0, -0.15, 0.0)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 0.30, 4.0)
	shape_node.shape = shape
	floor.add_child(shape_node)
	fixture.add_child(floor)
	if with_lower_floor:
		# A second platform directly below the missing upper-floor area.
		# Its top is within the support ray length but 0.15 m too low.
		var lower := StaticBody3D.new()
		lower.name = "LowerFloor"
		lower.collision_layer = 1
		lower.collision_mask = 0
		lower.position = Vector3(1.0, -0.30, 0.0)
		var lower_shape_node := CollisionShape3D.new()
		var lower_shape := BoxShape3D.new()
		lower_shape.size = Vector3(2.0, 0.30, 4.0)
		lower_shape_node.shape = lower_shape
		lower.add_child(lower_shape_node)
		fixture.add_child(lower)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.position = Vector3(-0.20, 0.0, 0.0)
	fixture.add_child(player)
	root.add_child(fixture)
	# Feed controlled, physically supported sample positions. The test still
	# uses the real raycast and inspects the mesh emitted by the effect.
	player.set_physics_process(false)
	var trail := player.get_node_or_null("GroundTrail") as SlimeGroundTrail
	if trail != null:
		trail.set_physics_process(false)
	return fixture


func _check_mesh_on_face(instance: MeshInstance3D, far_side: float, near_edge: float, min_triangles: int) -> String:
	if instance == null:
		return "effect node missing or script failed"
	if not instance.mesh is ArrayMesh:
		return "effect has no ArrayMesh"
	var effect_mesh := instance.mesh as ArrayMesh
	if effect_mesh.get_surface_count() == 0:
		return "effect has no surface"
	var visible_triangles := 0
	var outside_triangles := 0
	var most_outside := -INF
	var smallest_visible_x := INF
	var largest_visible_x := -INF
	for surface in range(effect_mesh.get_surface_count()):
		var arrays := effect_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.size() != colors.size() or indices.size() % 3 != 0:
			return "mesh vertex/color/index arrays are inconsistent"
		for triangle in range(0, indices.size(), 3):
			var a := indices[triangle]
			var b := indices[triangle + 1]
			var c := indices[triangle + 2]
			if maxf(colors[a].a, maxf(colors[b].a, colors[c].a)) < VISIBLE_ALPHA:
				continue
			visible_triangles += 1
			# A transparent corner still belongs to a triangle that interpolates
			# visible slime across it, so every corner must remain on the face.
			for index in [a, b, c]:
				var world: Vector3 = instance.global_transform * vertices[index]
				if world.x > EDGE_X + EDGE_TOLERANCE:
					outside_triangles += 1
					most_outside = maxf(most_outside, world.x)
				if colors[index].a >= VISIBLE_ALPHA:
					smallest_visible_x = minf(smallest_visible_x, world.x)
					largest_visible_x = maxf(largest_visible_x, world.x)
	if visible_triangles < min_triangles:
		return "effect largely disappeared: %d visible triangles" % visible_triangles
	if outside_triangles > 0:
		return "%d corners of visible triangles hang beyond x=0 (max x=%.3f m)" % [outside_triangles, most_outside]
	if smallest_visible_x > far_side or largest_visible_x < near_edge:
		return "effect was over-clipped: visible x range %.3f..%.3f m" % [smallest_visible_x, largest_visible_x]
	print("  %d visible triangles, x=%.3f..%.3f m" % [visible_triangles, smallest_visible_x, largest_visible_x])
	return ""


func _physics_steps(count: int) -> void:
	for step in range(count):
		await create_timer(0.0, true, true).timeout


func _discard(fixture: Node) -> void:
	fixture.queue_free()
	await _physics_steps(2)


func _report(case_name: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % case_name)
	else:
		_failures += 1
		print("FAIL %s: %s" % [case_name, problem])

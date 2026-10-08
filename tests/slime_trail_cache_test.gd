extends "res://tests/slime_trace_edge_test.gd"

# Cache invalidation must preserve turns, fading, separated deposits and reset.
func _run() -> void:
	var fixture := _make_floor_fixture(true)
	var hero: SlimeController = fixture.get_node("SlimePlayer")
	var trail: SlimeGroundTrail = hero._ground_trail
	await _physics_steps(2)
	for step in 28:
		hero.global_position = Vector3(-0.8+sin(step*0.22)*0.55,0,-1.1+step*0.08)
		trail._age += 0.035
		trail._sample_ground()
		if step in [9,21]: trail.add_landing_splash(8.0)
		trail._draw_effect()
	for age in [1.02,1.12,1.4,1.8,2.1,2.6,3.5]:
		trail._age = age
		trail._draw_effect()
		var cached := _triangle_signature(trail)
		for sample in trail._samples:
			sample.erase("raster")
			sample.erase("corner_raster")
		for splash in trail._splashes: splash.erase("settled_coverage")
		trail._draw_effect()
		_report("C01 cached/cold turn + splashes age %.2f" % age,"" if cached==_triangle_signature(trail) else "Cached geometry differs")
		# The saved pre-optimization code is optional evidence for this local run.
		var path := "res://output/keepers_ink_performance_2026_10_08/trail_baseline.gd"
		if ResourceLoader.exists(path):
			var original: SlimeGroundTrail = load(path).new()
			original.setup(hero)
			fixture.add_child(original)
			original.set_physics_process(false)
			original._samples=trail._samples.duplicate(true)
			original._splashes=trail._splashes.duplicate(true)
			original._age=age
			original._draw_effect()
			_report("C02 old/new triangle colors age %.2f" % age,"" if cached==_triangle_signature(original) else "Original geometry differs")
			original.free()
	trail.clear_for_room_change()
	_report("C03 restart clears geometry and caches","" if trail._samples.is_empty() and trail._splashes.is_empty() and trail._support_cache.is_empty() and trail.mesh.get_surface_count()==0 else "Stale trail after reset")
	await _discard(fixture)
	print("SLIME_TRAIL_CACHE_SUMMARY: %d failed" % _failures)
	quit(1 if _failures else 0)

func _triangle_signature(trail: SlimeGroundTrail) -> Array[String]:
	var result: Array[String] = []
	for triangle in range(0,trail._indices.size(),3):
		var data := PackedFloat32Array()
		for corner in 3:
			var index := trail._indices[triangle+corner]
			var p := trail._vertices[index]
			var c := trail._colors[index]
			data.append_array(PackedFloat32Array([p.x,p.y,p.z,c.r,c.g,c.b,c.a]))
		result.append(data.to_byte_array().hex_encode())
	result.sort()
	return result

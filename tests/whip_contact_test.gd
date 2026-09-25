extends SceneTree


const PLAYER_SCENE := preload("res://scenes/player/slime_player.tscn")
const ART_SCENE := preload("res://scenes/art_review/slime_model_preview_v5.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/spitter.tscn")
const INPUT_SETUP := preload("res://scripts/input_setup.gd")
const WALL_FRONT_Z := -0.75
const WALL_VERTEX_TOLERANCE := 0.06
const FAR_WALL_FRONT_Z := -1.85
const MID_CONTACT_MAX_T := 0.70
const TIP_CONTACT_MIN_T := 0.82
const MID_LAY_MIN_DISTANCE := 0.12
const TIP_LAY_MAX_DISTANCE := 0.10
const LAY_SURFACE_MAX_DISTANCE := 0.22
const MOVING_CAPSULE_MIN_GAP := -0.015
const WALL_MARK_POSITION_TOLERANCE := 0.075
const WALL_MARK_NORMAL_DOT_MIN := 0.95

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	INPUT_SETUP.install()
	for variant in range(SlimeWhipVisual.VARIANT_COUNT):
		_report("W01 enemy variant %d" % variant, await _enemy_contact(variant))
		_report("W02 wall variant %d" % variant, await _wall_contact(variant))
		_report("W03 open variant %d" % variant, await _open_swing(variant))
	_report("W04 multi-target sector", await _multi_target_sector())
	_report("W05 tip-only wall contact", await _tip_wall_contact())
	_report("W06 moving enemy capsule clearance", await _moving_enemy_contact())
	for variant in range(SlimeWhipVisual.VARIANT_COUNT):
		_report("W07 wall mark variant %d" % variant, await _wall_mark_lifecycle(variant))
	_report("W08 no wall mark on enemy or miss", await _no_wall_mark_without_wall())
	_report("W09 art preview nested whip wall mark", await _art_preview_wall_mark())
	print("WHIP_CONTACT_SUMMARY: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _enemy_contact(variant: int) -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.position = Vector3(0.0, 0.0, -1.12)
	fixture.add_child(enemy)
	await _physics_steps(5)
	_force_variant(player, variant)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	if player._whip_variant != variant:
		await _discard_fixture(fixture)
		return "selected variant %d, requested %d" % [player._whip_variant, variant]
	var active_trace := PackedStringArray()
	var seen_enemy := false
	var seen_laid := false
	var unexpected_contact := false
	for frame in range(16):
		await _physics_steps(1)
		if player.get("_phase") != &"active":
			continue
		var contact := visual.get_contact()
		active_trace.append("frame=%d selected=%d enemy=%s collider=%s extension=%.3f" % [frame, player._whip_variant, str(enemy.global_position), str(contact.get("collider", "none")), visual.get_visible_extension()])
		if contact.is_empty():
			continue
		if contact.get("collider") != enemy:
			unexpected_contact = true
			continue
		seen_enemy = true
		if not _valid_contact(contact):
			await _discard_fixture(fixture)
			return "enemy contact has invalid position, normal, or clip_t"
		if float(contact["clip_t"]) <= MID_CONTACT_MAX_T:
			var lay := _lay_geometry(visual, contact)
			seen_laid = seen_laid or (visual.visible and lay.get("distance", 0.0) >= MID_LAY_MIN_DISTANCE)
	var after_first := enemy.health
	await _physics_steps(25)
	var impact_cleared := visual.get_contact().is_empty()
	await _discard_fixture(fixture)
	if unexpected_contact:
		return "whip touched floor or another collider during enemy swing"
	if not seen_enemy or not seen_laid:
		return "lash did not lie along enemy after midshaft contact (contact=%s laid=%s HP=%d): %s" % [str(seen_enemy), str(seen_laid), after_first, " | ".join(active_trace)]
	if after_first != 20:
		return "combat damage changed: enemy HP=%d, expected 20" % after_first
	if not impact_cleared:
		return "contact persisted after recovery"
	return ""


func _wall_contact(variant: int) -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	var wall := _add_wall(fixture)
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.position = Vector3(0.0, 0.0, -1.7)
	fixture.add_child(enemy)
	await _physics_steps(5)
	_force_variant(player, variant)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	var seen_wall := false
	var seen_laid := false
	var min_mesh_z := INF
	var max_lay_surface_distance := 0.0
	var unexpected_contact := false
	for frame in range(16):
		await _physics_steps(1)
		if player.get("_phase") != &"active":
			continue
		var contact := visual.get_contact()
		if contact.is_empty():
			continue
		if contact.get("collider") != wall:
			unexpected_contact = true
			continue
		seen_wall = true
		if not _valid_contact(contact):
			await _discard_fixture(fixture)
			return "wall contact has invalid position, normal, or clip_t"
		# Check every vertex, including the rounded cap and the section along the wall.
		min_mesh_z = minf(min_mesh_z, _mesh_min_world_z(visual))
		if float(contact["clip_t"]) <= MID_CONTACT_MAX_T:
			var lay := _lay_geometry(visual, contact)
			if float(lay.get("distance", 0.0)) >= MID_LAY_MIN_DISTANCE:
				seen_laid = true
				max_lay_surface_distance = maxf(max_lay_surface_distance, float(lay.get("max_surface_distance", INF)))
	var enemy_hp := enemy.health
	await _discard_fixture(fixture)
	if unexpected_contact:
		return "whip touched a collider other than the wall"
	if not seen_wall:
		return "visible lash did not contact the wall"
	if not seen_laid:
		return "midshaft hit ended at the wall instead of lying along it"
	if max_lay_surface_distance > LAY_SURFACE_MAX_DISTANCE:
		return "laid section floated away from wall: %.3f" % max_lay_surface_distance
	if enemy_hp != 30:
		return "enemy behind wall lost health: %d" % enemy_hp
	if min_mesh_z == INF:
		return "visible lash mesh was unavailable at wall contact"
	if min_mesh_z < WALL_FRONT_Z - WALL_VERTEX_TOLERANCE:
		return "lash mesh penetrated wall: min z %.3f, near plane %.3f" % [min_mesh_z, WALL_FRONT_Z]
	print("W02 variant %d min mesh z=%.3f front z=%.3f lay surface distance=%.3f" % [variant, min_mesh_z, WALL_FRONT_Z, max_lay_surface_distance])
	return ""


func _tip_wall_contact() -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	var wall := _add_wall(fixture, FAR_WALL_FRONT_Z)
	await _physics_steps(5)
	_force_variant(player, SlimeWhipVisual.VARIANT_RIGHT)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	var seen_tip := false
	var max_tip_lay := 0.0
	var min_mesh_z := INF
	for frame in range(16):
		await _physics_steps(1)
		if player.get("_phase") != &"active":
			continue
		var contact := visual.get_contact()
		if contact.is_empty() or contact.get("collider") != wall:
			continue
		if float(contact.get("clip_t", 0.0)) < TIP_CONTACT_MIN_T:
			continue
		seen_tip = true
		max_tip_lay = maxf(max_tip_lay, float(_lay_geometry(visual, contact).get("distance", 0.0)))
		min_mesh_z = minf(min_mesh_z, _mesh_min_world_z(visual))
	await _physics_steps(25)
	var contact_cleared := visual.get_contact().is_empty()
	await _discard_fixture(fixture)
	if not seen_tip:
		return "far wall did not touch only the whip tip"
	if max_tip_lay > TIP_LAY_MAX_DISTANCE:
		return "tip-only contact bent too far along wall: %.3f" % max_tip_lay
	if min_mesh_z < FAR_WALL_FRONT_Z - WALL_VERTEX_TOLERANCE:
		return "tip-only mesh penetrated wall: min z %.3f" % min_mesh_z
	if not contact_cleared:
		return "tip contact persisted after recovery"
	return ""


func _moving_enemy_contact() -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	var enemy := ENEMY_SCENE.instantiate() as Spitter
	enemy.position = Vector3(0.0, 0.0, -1.12)
	enemy.player_target = player
	fixture.add_child(enemy)
	await _physics_steps(5)
	_force_variant(player, SlimeWhipVisual.VARIANT_RIGHT)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	var seen_contact := false
	var seen_lay := false
	var unexpected_contact := false
	var min_gap := INF
	var first_active_position := Vector3.ZERO
	var seen_active := false
	var active_move := 0.0
	for frame in range(16):
		await _physics_steps(1)
		if player.get("_phase") != &"active":
			continue
		if not seen_active:
			first_active_position = enemy.global_position
			seen_active = true
		active_move = maxf(active_move, enemy.global_position.distance_to(first_active_position))
		var contact := visual.get_contact()
		if contact.is_empty():
			continue
		if contact.get("collider") != enemy:
			unexpected_contact = true
			continue
		seen_contact = true
		var gap := _contact_ring_gap_to_capsule(visual, enemy)
		min_gap = minf(min_gap, gap)
		var lay := _lay_geometry(visual, contact)
		seen_lay = seen_lay or (visual.visible and float(lay.get("distance", 0.0)) > 0.05)
	var enemy_hp := enemy.health
	await _physics_steps(25)
	var contact_cleared := visual.get_contact().is_empty()
	await _discard_fixture(fixture)
	if unexpected_contact:
		return "moving enemy swing touched another collider"
	if not seen_contact:
		return "moving enemy was never touched during active phase"
	if active_move < 0.025:
		return "enemy did not retreat during active phase: %.3f m" % active_move
	if min_gap < MOVING_CAPSULE_MIN_GAP:
		return "contact ring entered moving enemy capsule: gap %.3f m, limit %.3f m" % [min_gap, MOVING_CAPSULE_MIN_GAP]
	if not seen_lay:
		return "no laid section was visible during moving enemy contact"
	if enemy_hp != 20:
		return "moving enemy HP=%d, expected 20" % enemy_hp
	if not contact_cleared:
		return "moving enemy contact persisted after recovery"
	print("W06 moving enemy min gap=%.3f m, active retreat=%.3f m" % [min_gap, active_move])
	return ""


func _wall_mark_lifecycle(variant: int) -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	var wall := _add_wall(fixture)
	await _physics_steps(5)
	_force_variant(player, variant)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	var hit := {}
	var most_marks := 0
	for frame in range(18):
		await _physics_steps(1)
		var contact := visual.get_contact()
		var frame_marks := _wall_marks(fixture)
		if hit.is_empty() and contact.get("collider") == wall and not frame_marks.is_empty():
			hit = contact.duplicate()
		most_marks = maxi(most_marks, frame_marks.size())
	var marks := _wall_marks(fixture)
	if hit.is_empty() or marks.size() != 1 or most_marks != 1:
		await _discard_fixture(fixture)
		return "wall hit made %d live marks (peak %d), expected exactly one; contact=%s" % [marks.size(), most_marks, str(not hit.is_empty())]
	var mark := marks[0] as SlimeWallImpactMark
	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var position_error := mark.global_position.distance_to(hit_position + hit_normal.normalized() * SlimeWallImpactMark.SURFACE_OFFSET)
	var normal_dot := mark.global_basis.z.normalized().dot(hit_normal.normalized())
	if position_error > WALL_MARK_POSITION_TOLERANCE or normal_dot < WALL_MARK_NORMAL_DOT_MIN:
		await _discard_fixture(fixture)
		return "mark is off wall: position error %.3f m, normal dot %.3f" % [position_error, normal_dot]
	var initial_opacity := mark.get_opacity()
	await create_timer(0.85, false, true).timeout
	marks = _wall_marks(fixture)
	if marks.size() != 1 or marks[0] != mark:
		await _discard_fixture(fixture)
		return "wall mark vanished with whip recovery or duplicated"
	if player.get("_phase") == &"active" or player.get("_phase") == &"recovery":
		await _discard_fixture(fixture)
		return "whip recovery had not finished at mark persistence check"
	var faded_opacity := mark.get_opacity()
	if initial_opacity < 0.95 or faded_opacity >= initial_opacity - 0.04 or faded_opacity <= 0.0:
		await _discard_fixture(fixture)
		return "wall mark did not gradually fade: alpha %.3f -> %.3f" % [initial_opacity, faded_opacity]
	await create_timer(1.45, false, true).timeout
	var remaining := _wall_marks(fixture).size()
	await _discard_fixture(fixture)
	if remaining != 0:
		return "wall mark did not fade and free itself after 2 seconds: %d remaining" % remaining
	return ""


func _no_wall_mark_without_wall() -> String:
	for target_enemy in [true, false]:
		var fixture := _make_fixture()
		var player := fixture.get_node("SlimePlayer") as SlimeController
		var visual := _get_whip(player)
		var enemy: Spitter = null
		if target_enemy:
			enemy = ENEMY_SCENE.instantiate() as Spitter
			enemy.position = Vector3(0.0, 0.0, -1.12)
			fixture.add_child(enemy)
		await _physics_steps(5)
		_force_variant(player, SlimeWhipVisual.VARIANT_RIGHT)
		if not player.request_action(&"slime_whip"):
			await _discard_fixture(fixture)
			return "whip did not start"
		var seen_expected_contact := false
		var seen_unexpected_contact := false
		var most_marks := 0
		for frame in range(20):
			await _physics_steps(1)
			var contact := visual.get_contact()
			seen_expected_contact = seen_expected_contact or (target_enemy and contact.get("collider") == enemy)
			seen_unexpected_contact = seen_unexpected_contact or (not target_enemy and not contact.is_empty())
			most_marks = maxi(most_marks, _wall_marks(fixture).size())
		var enemy_hp := enemy.health if target_enemy else -1
		await _discard_fixture(fixture)
		if most_marks != 0:
			return "%s swing spawned %d wall marks" % ["enemy" if target_enemy else "open", most_marks]
		if target_enemy and (not seen_expected_contact or enemy_hp != 20):
			return "enemy control missed or combat damage changed: contact=%s HP=%d" % [str(seen_expected_contact), enemy_hp]
		if seen_unexpected_contact:
			return "open swing touched a collider"
	return ""


func _discard_art_fixture(art: Node3D) -> void:
	# W09 runs the complete preview scene, which plays a short whip sound.
	# Stop its real-time audio playback before the accelerated fixed-FPS test exits.
	for child in art.get_children():
		if child is AudioStreamPlayer3D:
			var audio := child as AudioStreamPlayer3D
			audio.stop()
			audio.stream = null
	await _physics_steps(2)
	await _discard_fixture(art)

func _wall_marks(fixture: Node) -> Array[Node]:
	var marks: Array[Node] = []
	for node in get_nodes_in_group(&"slime_wall_impact_marks"):
		if fixture.is_ancestor_of(node):
			marks.append(node)
	return marks

func _art_preview_wall_mark() -> String:
	var art := ART_SCENE.instantiate() as Node3D
	root.add_child(art)
	var player := art.get_node_or_null("SlimePlayer") as SlimeController
	if player == null:
		await _discard_art_fixture(art)
		return "art preview has no SlimePlayer"
	var visual := player.get_node_or_null("VisualRoot/SlimeHeroModelV5/SlimeWhip") as SlimeWhipVisual
	if visual == null:
		await _discard_art_fixture(art)
		return "art preview did not reparent SlimeWhip under SlimeHeroModelV5"
	# The full preview Main plays a real-time WAV on action_started. W09 only
	# exercises the visual hierarchy, so leave the model callback but omit audio.
	var sound_callback := Callable(art, "_on_action_started")
	if player.action_started.is_connected(sound_callback):
		player.action_started.disconnect(sound_callback)
	var first_enemy := art.get("first_enemy") as Spitter
	if is_instance_valid(first_enemy):
		first_enemy.queue_free()
	var front_z := player.global_position.z + WALL_FRONT_Z
	var wall := _add_wall(art, front_z)
	await _physics_steps(5)
	_force_variant(player, SlimeWhipVisual.VARIANT_RIGHT)
	if not player.request_action(&"slime_whip"):
		await _discard_art_fixture(art)
		return "art preview whip did not start"
	var hit := {}
	var trace := PackedStringArray()
	var peak_marks := 0
	for frame in range(22):
		await _physics_steps(1)
		var contact := visual.get_contact()
		var marks := _wall_marks(art)
		trace.append("%d:%s:%d" % [frame, str(contact.get("collider", "none")), marks.size()])
		if hit.is_empty() and contact.get("collider") == wall and not marks.is_empty():
			hit = contact.duplicate()
		peak_marks = maxi(peak_marks, marks.size())
	var marks := _wall_marks(art)
	if hit.is_empty() or marks.size() != 1 or peak_marks != 1:
		await _discard_art_fixture(art)
		return "nested whip wall mark missing or duplicated (live=%d peak=%d): %s" % [marks.size(), peak_marks, " | ".join(trace)]
	var mark := marks[0] as SlimeWallImpactMark
	var normal: Vector3 = hit["normal"]
	var expected: Vector3 = hit["position"] + normal.normalized() * SlimeWallImpactMark.SURFACE_OFFSET
	var position_error := mark.global_position.distance_to(expected)
	var normal_dot := mark.global_basis.z.normalized().dot(normal.normalized())
	if position_error > WALL_MARK_POSITION_TOLERANCE or normal_dot < WALL_MARK_NORMAL_DOT_MIN:
		await _discard_art_fixture(art)
		return "nested whip mark is off wall: error %.3f m, normal dot %.3f" % [position_error, normal_dot]
	var initial_opacity := mark.get_opacity()
	await create_timer(0.85, false, true).timeout
	marks = _wall_marks(art)
	if marks.size() != 1 or marks[0] != mark or player.get("_phase") == &"recovery":
		await _discard_art_fixture(art)
		return "nested whip mark failed to outlive lash recovery"
	var faded_opacity := mark.get_opacity()
	if initial_opacity < 0.95 or faded_opacity >= initial_opacity - 0.04 or faded_opacity <= 0.0:
		await _discard_art_fixture(art)
		return "nested whip mark did not fade: alpha %.3f -> %.3f" % [initial_opacity, faded_opacity]
	await create_timer(1.45, false, true).timeout
	var remaining := _wall_marks(art).size()
	await _discard_art_fixture(art)
	if remaining != 0:
		return "nested whip mark remained after lifetime: %d" % remaining
	return ""

func _open_swing(variant: int) -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var visual := _get_whip(player)
	await _physics_steps(5)
	_force_variant(player, variant)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	var seen_full_reach := false
	var false_contact := false
	for frame in range(16):
		await _physics_steps(1)
		if player.get("_phase") != &"active":
			continue
		false_contact = false_contact or not visual.get_contact().is_empty()
		seen_full_reach = seen_full_reach or visual.get_visible_extension() >= 0.995
	await _discard_fixture(fixture)
	if false_contact:
		return "open swing touched player or floor"
	if not seen_full_reach:
		return "open swing never reached its full length"
	return ""


func _multi_target_sector() -> String:
	var fixture := _make_fixture()
	var player := fixture.get_node("SlimePlayer") as SlimeController
	var left := ENEMY_SCENE.instantiate() as Spitter
	left.position = Vector3(-0.55, 0.0, -1.4)
	fixture.add_child(left)
	var right := ENEMY_SCENE.instantiate() as Spitter
	right.position = Vector3(0.55, 0.0, -1.4)
	fixture.add_child(right)
	await _physics_steps(5)
	_force_variant(player, SlimeWhipVisual.VARIANT_RIGHT)
	if not player.request_action(&"slime_whip"):
		await _discard_fixture(fixture)
		return "whip did not start"
	await _physics_steps(13)
	var left_hp := left.health
	var right_hp := right.health
	await _discard_fixture(fixture)
	if left_hp != 20 or right_hp != 20:
		return "sector damage changed: left HP=%d, right HP=%d" % [left_hp, right_hp]
	return ""

func _valid_contact(contact: Dictionary) -> bool:
	if not contact.has("position") or not contact.has("normal") or not contact.has("clip_t"):
		return false
	var point: Vector3 = contact["position"]
	var normal: Vector3 = contact["normal"]
	var clip_t: float = contact["clip_t"]
	return point.is_finite() and normal.is_finite() and normal.length() > 0.8 and clip_t > 0.0 and clip_t < 1.0


func _mesh_min_world_z(visual: SlimeWhipVisual) -> float:
	var tendril := visual.get_node_or_null("Tendril") as MeshInstance3D
	if tendril == null or not tendril.mesh is ArrayMesh:
		return INF
	var mesh := tendril.mesh as ArrayMesh
	var minimum := INF
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			minimum = minf(minimum, (tendril.global_transform * vertex).z)
	return minimum


func _lay_geometry(visual: SlimeWhipVisual, contact: Dictionary) -> Dictionary:
	var tendril := visual.get_node_or_null("Tendril") as MeshInstance3D
	if tendril == null or not tendril.mesh is ArrayMesh:
		return {}
	var mesh := tendril.mesh as ArrayMesh
	if mesh.get_surface_count() == 0:
		return {}
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var stride := SlimeWhipVisual.SIDES + 1
	var impact_ring := SlimeWhipVisual.RINGS
	var end_ring := impact_ring + SlimeWhipVisual.LAY_RINGS
	if vertices.size() < (end_ring + 1) * stride:
		return {}
	var start := _ring_center(tendril, vertices, impact_ring)
	var finish := _ring_center(tendril, vertices, end_ring)
	var normal: Vector3 = contact["normal"]
	var surface_point: Vector3 = contact["position"]
	var offset := finish - start
	var tangent_offset := offset - normal * offset.dot(normal)
	var max_surface_distance := 0.0
	for ring in range(impact_ring + 1, end_ring + 1):
		var center := _ring_center(tendril, vertices, ring)
		max_surface_distance = maxf(max_surface_distance, absf((center - surface_point).dot(normal)))
	return {"distance": tangent_offset.length(), "max_surface_distance": max_surface_distance}


func _ring_center(tendril: MeshInstance3D, vertices: PackedVector3Array, ring: int) -> Vector3:
	var local_center := Vector3.ZERO
	var stride := SlimeWhipVisual.SIDES + 1
	for side in range(SlimeWhipVisual.SIDES):
		local_center += vertices[ring * stride + side]
	return tendril.global_transform * (local_center / float(SlimeWhipVisual.SIDES))


func _contact_ring_gap_to_capsule(visual: SlimeWhipVisual, enemy: Spitter) -> float:
	var tendril := visual.get_node_or_null("Tendril") as MeshInstance3D
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if tendril == null or not tendril.mesh is ArrayMesh or shape_node == null or not shape_node.shape is CapsuleShape3D:
		return -INF
	var mesh := tendril.mesh as ArrayMesh
	if mesh.get_surface_count() == 0:
		return -INF
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var stride := SlimeWhipVisual.SIDES + 1
	var ring := SlimeWhipVisual.RINGS
	if vertices.size() < (ring + 1) * stride:
		return -INF
	var center := _ring_center(tendril, vertices, ring)
	var ring_radius := 0.0
	for side in range(SlimeWhipVisual.SIDES):
		var point: Vector3 = tendril.global_transform * vertices[ring * stride + side]
		ring_radius = maxf(ring_radius, point.distance_to(center))
	var capsule := shape_node.shape as CapsuleShape3D
	var local_center := shape_node.global_transform.affine_inverse() * center
	var stem := maxf(0.0, capsule.height * 0.5 - capsule.radius)
	var axis_local := Vector3(0.0, clampf(local_center.y, -stem, stem), 0.0)
	var axis_world := shape_node.global_transform * axis_local
	return center.distance_to(axis_world) - capsule.radius - ring_radius


func _get_whip(player: SlimeController) -> SlimeWhipVisual:
	return player.get_node("VisualRoot/SlimeHeroModelV5/SlimeWhip") as SlimeWhipVisual


func _force_variant(player: SlimeController, variant: int) -> void:
	player._whip_variants_left.clear()
	player._whip_variants_left.append(variant)


func _make_fixture() -> Node3D:
	var fixture := Node3D.new()
	fixture.name = "WhipContactFixture"
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	floor.position = Vector3(0.0, -0.2, 0.0)
	var floor_collider := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.4, 20.0)
	floor_collider.shape = floor_shape
	floor.add_child(floor_collider)
	fixture.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as SlimeController
	player.name = "SlimePlayer"
	fixture.add_child(player)
	root.add_child(fixture)
	return fixture


func _add_wall(fixture: Node3D, front_z: float = WALL_FRONT_Z) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "WhipWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(0.0, 1.0, front_z - 0.1)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 2.0, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	fixture.add_child(wall)
	return wall


func _physics_steps(count: int) -> void:
	for step in range(count):
		await create_timer(0.0, true, true).timeout


func _discard_fixture(fixture: Node) -> void:
	fixture.queue_free()
	await _physics_steps(2)


func _report(case_name: String, problem: String) -> void:
	if problem.is_empty():
		print("PASS %s" % case_name)
	else:
		_failures += 1
		print("FAIL %s: %s" % [case_name, problem])

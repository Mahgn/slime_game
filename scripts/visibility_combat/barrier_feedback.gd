extends Control

var route: Node3D
var blocked := false
var hit_position := Vector3.ZERO
var _screen_point := Vector2.ZERO
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = "Стена перекрывает выстрел"
	_label.visible = false
	_label.add_theme_color_override("font_color",Color("ffd7a0"))
	_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x",2)
	_label.add_theme_constant_override("shadow_offset_y",2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	blocked = false
	var barrier: CollisionObject3D
	if route.ready_for_comparison and not get_tree().paused and route.player.is_alive():
		var hero: SlimeController = route.player
		var target: Vector3 = hero.controls.get_aim_point()
		var origin := hero.global_position + Vector3.UP*hero._combat_origin_height()
		var forward := target-origin
		forward.y = 0.0
		forward = forward.normalized()
		if forward.length_squared() < 0.01:
			forward = hero.controls.screen_movement_direction(Vector2(0,-1))
		origin += forward*0.5
		# The preview uses the same muzzle and first-hit layers as a player spit.
		# A creature in front of a wall is a valid target, not a blocked shot.
		var query := PhysicsRayQueryParameters3D.create(origin,target,1|4)
		query.hit_from_inside = true
		query.exclude = [hero.get_rid()]
		var hit := route.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and route.reveal.is_barrier(hit.collider) and hit.position.distance_to(target)>0.15:
			blocked = true
			barrier = hit.collider
			hit_position = hit.position
			_screen_point = hero.presentation.camera.unproject_position(hit_position)
	_label.visible = blocked
	if route.ready_for_comparison:
		route.reveal.set_aim_barrier(barrier)
	if blocked: _label.position = _screen_point+Vector2(12,-26)
	queue_redraw()

func _draw() -> void:
	if not blocked: return
	var color := Color("ffb66e")
	draw_line(_screen_point+Vector2(-5,-5),_screen_point+Vector2(5,5),color,2,true)
	draw_line(_screen_point+Vector2(-5,5),_screen_point+Vector2(5,-5),color,2,true)

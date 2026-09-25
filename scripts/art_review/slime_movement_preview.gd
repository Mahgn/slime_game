extends "res://scripts/art_review/slime_model_preview_v5.gd"

# The same v5 player art, camera, movement, lighting and HUD as the existing
# art-review scene. Only the independent movement course is added here.
const TUNNEL_CENTER_Z := 1.7
const TUNNEL_ROOF_LENGTH := 3.6
const TUNNEL_ZONE_LENGTH := 6.0
const TUNNEL_CLEARANCE := 0.60
const TUNNEL_PASSAGE_HALF_WIDTH := 0.96
const LEDGE_HEIGHT := 1.45

var _low_passage_area: Area3D


func _ready() -> void:
	super._ready()
	stage = &"movement_preview"
	_build_movement_course()
	_hint_label.text = "Идите к низкому проходу. Слайм сожмётся сам."


func _spawn_first_enemy() -> void:
	# Keep the movement preview separate from the combat route.
	pass


func _physics_process(_delta: float) -> void:
	if get_tree().paused or not is_instance_valid(player) or not is_instance_valid(_low_passage_area):
		return
	# The area marks both approaches, but only feet below the roof and inside
	# the walkable corridor request the compressed collider. Recheck every
	# physics tick so a jump onto the roof cannot retain a stale request.
	var local_position := _low_passage_area.to_local(player.global_position)
	var within_corridor := absf(local_position.x) <= TUNNEL_PASSAGE_HALF_WIDTH
	var within_length := absf(local_position.z) <= TUNNEL_ZONE_LENGTH * 0.5
	var below_roof := player.global_position.y < TUNNEL_CLEARANCE - 0.02
	var supported := player.is_on_floor() or player.is_compressed()
	player.set_low_passage_active(_low_passage_area, within_corridor and within_length and below_roof and supported)


func _process(delta: float) -> void:
	super._process(delta)
	if get_tree().paused or not is_instance_valid(player):
		return
	if player.is_on_floor() and player.global_position.y >= 1.20:
		_hint_label.text = "Уступ пройден. Вернитесь к проходу или попробуйте ещё раз."
	elif player.is_on_floor() and player.global_position.y > TUNNEL_CLEARANCE + 0.12 and absf(player.global_position.x) < 1.40 and absf(player.global_position.z - TUNNEL_CENTER_Z) < TUNNEL_ROOF_LENGTH * 0.5:
		_hint_label.text = "На крыше слайм сохраняет обычную форму."
	elif player.is_compressed():
		_hint_label.text = "Пройдите под низким потолком. На выходе слайм распрямится."
	elif player.global_position.z < -1.4:
		_hint_label.text = "Высокий уступ: удерживайте пробел, затем отпустите для прыжка."
	else:
		_hint_label.text = "Идите к низкому проходу. Слайм сожмётся сам."


func _build_movement_course() -> void:
	var stone := Color(0.39, 0.48, 0.51)
	var roof := Color(0.51, 0.59, 0.57)
	var ledge := Color(0.42, 0.52, 0.48)
	var marker := Color(0.85, 0.68, 0.31)
	_add_solid_box("TunnelRoof", Vector3(0.0, TUNNEL_CLEARANCE + 0.15, TUNNEL_CENTER_Z), Vector3(2.8, 0.30, TUNNEL_ROOF_LENGTH), roof)
	_add_solid_box("TunnelWestWall", Vector3(-1.31, 0.70, TUNNEL_CENTER_Z), Vector3(0.22, 1.40, TUNNEL_ROOF_LENGTH), stone)
	_add_solid_box("TunnelEastWall", Vector3(1.31, 0.70, TUNNEL_CENTER_Z), Vector3(0.22, 1.40, TUNNEL_ROOF_LENGTH), stone)
	_add_visual_box("TunnelEntrance", Vector3(0.0, 0.025, TUNNEL_CENTER_Z + TUNNEL_ROOF_LENGTH * 0.5 + 0.55), Vector3(2.4, 0.035, 0.16), marker)
	_add_visual_box("TunnelExit", Vector3(0.0, 0.025, TUNNEL_CENTER_Z - TUNNEL_ROOF_LENGTH * 0.5 - 0.55), Vector3(2.4, 0.035, 0.16), marker)

	# The zone extends 1.2 m beyond both ends, but its top remains below
	# the roof underside. The per-tick gate above also rejects the outer sides.
	_low_passage_area = Area3D.new()
	_low_passage_area.name = "LowPassageArea"
	_low_passage_area.collision_layer = 0
	_low_passage_area.collision_mask = 2
	_low_passage_area.monitoring = false
	_low_passage_area.position = Vector3(0.0, 0.275, TUNNEL_CENTER_Z)
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(2.4, 0.55, TUNNEL_ZONE_LENGTH)
	area_shape.shape = area_box
	_low_passage_area.add_child(area_shape)
	add_child(_low_passage_area)

	_add_visual_box("JumpMarker", Vector3(0.0, 0.025, -2.8), Vector3(2.5, 0.035, 0.18), marker)
	_add_solid_box("HighLedge", Vector3(0.0, LEDGE_HEIGHT * 0.5, -6.2), Vector3(3.4, LEDGE_HEIGHT, 3.4), ledge)
	_add_visual_box("LedgeTopAccent", Vector3(0.0, LEDGE_HEIGHT + 0.018, -4.62), Vector3(3.15, 0.025, 0.12), marker)



func _add_solid_box(piece_name: String, center: Vector3, size: Vector3, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.name = piece_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _make_stone(tint)
	body.add_child(visual)
	add_child(body)


func _add_visual_box(piece_name: String, center: Vector3, size: Vector3, tint: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = piece_name
	visual.position = center
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _make_stone(tint)
	add_child(visual)


func _make_stone(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.84
	return material

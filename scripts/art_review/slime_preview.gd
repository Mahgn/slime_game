extends "res://scripts/main.gd"

const FRONT_ART := preload("res://assets/art/slime_review/slime_front_candidate_v2.png")
const BACK_ART := preload("res://assets/art/slime_review/slime_back_candidate_v1.png")
const SIDE_ART := preload("res://assets/art/slime_review/slime_side_candidate_v2.png")

var _art_sprite: Sprite3D


func _ready() -> void:
	super._ready()
	for part in player.visual_root.get_children():
		if part is MeshInstance3D:
			part.hide()
	_art_sprite = Sprite3D.new()
	_art_sprite.name = "GeneratedSlimeArt"
	_art_sprite.texture = BACK_ART
	_art_sprite.pixel_size = 0.00095
	_art_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_art_sprite.shaded = false
	_art_sprite.double_sided = true
	player.visual_root.add_child(_art_sprite)
	_update_art_view()


func _process(delta: float) -> void:
	super._process(delta)
	_update_art_view()


func _update_art_view() -> void:
	if not is_instance_valid(_art_sprite):
		return
	var to_camera := player.camera.global_position - player.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.001:
		return
	to_camera = to_camera.normalized()
	var front := -player.visual_root.global_basis.z.normalized()
	var toward_front := front.dot(to_camera)
	if toward_front > 0.45:
		_art_sprite.texture = FRONT_ART
		_art_sprite.flip_h = false
	elif toward_front < -0.45:
		_art_sprite.texture = BACK_ART
		_art_sprite.flip_h = false
	else:
		_art_sprite.texture = SIDE_ART
		_art_sprite.flip_h = player.visual_root.global_basis.x.normalized().dot(to_camera) > 0.0

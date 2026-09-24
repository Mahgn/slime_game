extends "res://scripts/main.gd"

const SLIME_MODEL := preload("res://assets/models/slime_hero_v5.res")

var _model_instance: MeshInstance3D
var _animated_materials: Array[ShaderMaterial] = []
var _visual_time := 0.0
var _crawl_phase := 0.0
var _crawl_amount := 0.0
var _landing_pulse := 0.0
var _action_pulse := 0.0
var _was_on_floor := true


func _ready() -> void:
	super._ready()
	player.walk_visual_strength = 0.20
	for part in player.visual_root.get_children():
		if part is MeshInstance3D and part.name in ["Body", "LeftEye", "RightEye", "LeftPupil", "RightPupil"]:
			part.hide()
	_model_instance = MeshInstance3D.new()
	_model_instance.name = "SlimeHeroModelV5"
	_model_instance.mesh = SLIME_MODEL
	for surface_index in range(SLIME_MODEL.get_surface_count()):
		var unique_material := SLIME_MODEL.surface_get_material(surface_index).duplicate() as ShaderMaterial
		_model_instance.set_surface_override_material(surface_index, unique_material)
		_animated_materials.append(unique_material)
	player.visual_root.add_child(_model_instance)
	player.action_started.connect(_on_model_action)
	_was_on_floor = player.is_on_floor()


func _process(delta: float) -> void:
	super._process(delta)
	if get_tree().paused or not is_instance_valid(_model_instance):
		return
	_visual_time += delta
	var on_floor := player.is_on_floor()
	if on_floor and not _was_on_floor:
		_landing_pulse = 1.0
	_was_on_floor = on_floor
	_landing_pulse = maxf(0.0, _landing_pulse - delta * 4.5)
	_action_pulse = maxf(0.0, _action_pulse - delta * 4.0)

	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var move_ratio := clampf(speed / SlimeController.MOVE_SPEED, 0.0, 1.0)
	var crawl_target := move_ratio if on_floor else 0.0
	_crawl_amount = lerpf(_crawl_amount, crawl_target, minf(1.0, delta * 7.0))
	_crawl_phase += delta * (6.5 + 2.0 * move_ratio) * _crawl_amount
	var plant := (1.0 - cos(_crawl_phase)) * 0.5
	var push := sin(_crawl_phase)
	var target_scale := Vector3(
		1.0 + _crawl_amount * plant * 0.010,
		1.0 - _crawl_amount * plant * 0.018,
		1.0 + _crawl_amount * plant * 0.018
	)
	target_scale += Vector3(0.045, -0.065, 0.045) * _landing_pulse
	target_scale += Vector3(-0.025, 0.035, 0.025) * _action_pulse
	var blend := minf(1.0, delta * 13.0)
	_model_instance.scale = _model_instance.scale.lerp(target_scale, blend)
	var target_position := Vector3(0.0, _crawl_amount * (-0.015 + push * 0.014) - _landing_pulse * 0.018, -_crawl_amount * plant * 0.075)
	_model_instance.position = _model_instance.position.lerp(target_position, blend)
	_model_instance.rotation.x = lerpf(_model_instance.rotation.x, _crawl_amount * push * 0.110, blend)
	_model_instance.rotation.z = lerpf(_model_instance.rotation.z, _crawl_amount * push * 0.008, blend)

	var gel_energy := 0.025 + _landing_pulse * 0.20 + _action_pulse * 0.14
	for material in _animated_materials:
		material.set_shader_parameter("gel_time", _visual_time)
		material.set_shader_parameter("gel_energy", gel_energy)
		material.set_shader_parameter("gel_motion", Vector2.ZERO)
		material.set_shader_parameter("crawl_phase", _crawl_phase)
		material.set_shader_parameter("crawl_amount", _crawl_amount)


func _on_model_action(_action_id: StringName) -> void:
	_action_pulse = 1.0
extends "res://scripts/main.gd"

const SLIME_MODEL := preload("res://assets/models/slime_hero_v2.res")

var _model_instance: MeshInstance3D
var _gel_material: ShaderMaterial
var _visual_time := 0.0
var _landing_pulse := 0.0
var _action_pulse := 0.0
var _was_on_floor := true


func _ready() -> void:
	super._ready()
	for part in player.visual_root.get_children():
		if part is MeshInstance3D:
			part.hide()
	_model_instance = MeshInstance3D.new()
	_model_instance.name = "SlimeHeroModelV2"
	_model_instance.mesh = SLIME_MODEL
	_gel_material = SLIME_MODEL.surface_get_material(0).duplicate() as ShaderMaterial
	_model_instance.set_surface_override_material(0, _gel_material)
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
	_landing_pulse = maxf(0.0, _landing_pulse - delta * 2.6)
	_action_pulse = maxf(0.0, _action_pulse - delta * 3.0)

	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var move_ratio := clampf(speed / SlimeController.MOVE_SPEED, 0.0, 1.0)
	var stride := sin(_visual_time * 11.5)
	var breath := sin(_visual_time * 3.2)
	var spread := breath * 0.045 + move_ratio * (0.10 + stride * 0.09)
	var target_scale := Vector3(1.0 + spread, 1.0 - spread * 1.18, 1.0 + spread)
	if not on_floor:
		target_scale = Vector3(0.91 + breath * 0.025, 1.19 - breath * 0.025, 0.91 + breath * 0.025)
	if _landing_pulse > 0.0:
		target_scale += Vector3(0.27, -0.38, 0.27) * _landing_pulse
	if _action_pulse > 0.0:
		target_scale += Vector3(-0.10, 0.14, 0.12) * _action_pulse

	var blend := minf(1.0, delta * (24.0 if _landing_pulse > 0.0 or _action_pulse > 0.0 else 17.0))
	_model_instance.scale = _model_instance.scale.lerp(target_scale, blend)
	var bounce := move_ratio * (absf(stride) * 0.065 - 0.025)
	var target_position := Vector3(move_ratio * sin(_visual_time * 5.75) * 0.023, bounce - _landing_pulse * 0.10 + _action_pulse * 0.026, 0.0)
	_model_instance.position = _model_instance.position.lerp(target_position, blend)
	_model_instance.rotation.z = lerpf(_model_instance.rotation.z, move_ratio * stride * 0.14 + _action_pulse * 0.075, blend)
	_model_instance.rotation.x = lerpf(_model_instance.rotation.x, move_ratio * cos(_visual_time * 11.5) * 0.045 - _action_pulse * 0.07, blend)

	_gel_material.set_shader_parameter("gel_time", _visual_time)
	_gel_material.set_shader_parameter("gel_energy", 0.18 + move_ratio * 0.72 + _landing_pulse * 0.8 + _action_pulse * 0.65)


func _on_model_action(_action_id: StringName) -> void:
	_action_pulse = 1.0


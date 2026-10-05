extends MeshInstance3D
class_name SlimeHeroVisual

const WHIP_SHADER := preload("res://assets/shaders/slime_whip_v5.gdshader")

var player: SlimeController
var _animated_materials: Array[ShaderMaterial] = []
var _visual_time := 0.0
var _crawl_phase := 0.0
var _crawl_amount := 0.0
var _landing_pulse := 0.0
var _landing_wobble_time := 1.0
var _charge_pose := 0.0
var _charge_rebound := 0.0
var _last_charge_ratio := 0.0
var _action_pulse := 0.0
var _was_on_floor := true


func setup(player_node: SlimeController, whip_visual: SlimeWhipVisual) -> void:
	player = player_node
	for surface_index in range(mesh.get_surface_count()):
		var source_material := mesh.surface_get_material(surface_index) as ShaderMaterial
		var unique_material := source_material.duplicate() as ShaderMaterial
		set_surface_override_material(surface_index, unique_material)
		_animated_materials.append(unique_material)
	whip_visual.reparent(self, false)
	var whip_material := ShaderMaterial.new()
	whip_material.shader = WHIP_SHADER
	whip_visual.set_tendril_material(whip_material)
	player.action_started.connect(_on_model_action)
	_was_on_floor = player.is_on_floor()

func _process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(player) or player.health <= 0:
		return
	_visual_time += delta
	var on_floor := player.is_on_floor()
	if on_floor and not _was_on_floor:
		_landing_pulse = 1.0
		_landing_wobble_time = 0.0
	_was_on_floor = on_floor
	_landing_pulse = maxf(0.0, _landing_pulse - delta * 4.5)
	_landing_wobble_time = minf(1.0, _landing_wobble_time + delta)
	_action_pulse = maxf(0.0, _action_pulse - delta * 4.0)

	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var move_ratio := clampf(speed / SlimeController.MOVE_SPEED, 0.0, 1.0)
	var crawl_target := move_ratio if on_floor else 0.0
	_crawl_amount = lerpf(_crawl_amount, crawl_target, minf(1.0, delta * 7.0))
	_crawl_phase += delta * (6.5 + 2.0 * move_ratio) * _crawl_amount
	var plant := (1.0 - cos(_crawl_phase)) * 0.5
	var push := sin(_crawl_phase)
	var charge_ratio: float = player.get_jump_charge_ratio()
	if _last_charge_ratio > 0.35 and charge_ratio < 0.001 and not on_floor and player.velocity.y > 1.0:
		_charge_rebound = 1.0
	_last_charge_ratio = charge_ratio
	_charge_pose = lerpf(_charge_pose, smoothstep(0.0, 1.0, charge_ratio), minf(1.0, delta * 12.0))
	_charge_rebound = maxf(0.0, _charge_rebound - delta * 6.0)
	var landing_wobble := sin(_landing_wobble_time * 16.0) * exp(-_landing_wobble_time * 5.0)
	var target_scale := Vector3(
		1.0 + _crawl_amount * plant * 0.010,
		1.0 - _crawl_amount * plant * 0.018,
		1.0 + _crawl_amount * plant * 0.018
	)
	target_scale += Vector3(0.045, -0.065, 0.045) * _landing_pulse
	target_scale += Vector3(0.015, -0.028, 0.015) * landing_wobble
	target_scale += Vector3(0.050, -0.130, 0.050) * _charge_pose
	target_scale += Vector3(-0.015, 0.035, -0.015) * _charge_rebound
	target_scale += Vector3(-0.025, 0.035, 0.025) * _action_pulse
	var blend := minf(1.0, delta * 13.0)
	scale = scale.lerp(target_scale, blend)
	var target_position := Vector3(0.0, _crawl_amount * (-0.015 + push * 0.014) - _landing_pulse * 0.018 - _charge_pose * 0.055 + _charge_rebound * 0.012 - landing_wobble * 0.006, -_crawl_amount * plant * 0.075)
	position = position.lerp(target_position, blend)
	rotation.x = lerpf(rotation.x, _crawl_amount * push * 0.110, blend)
	rotation.z = lerpf(rotation.z, _crawl_amount * push * 0.008, blend)

	var gel_energy := 0.025 + _landing_pulse * 0.20 + absf(landing_wobble) * 0.06 + _charge_pose * 0.055 + _charge_rebound * 0.045 + _action_pulse * 0.14
	for material in _animated_materials:
		material.set_shader_parameter("gel_time", _visual_time)
		material.set_shader_parameter("gel_energy", gel_energy)
		material.set_shader_parameter("gel_motion", Vector2.ZERO)
		material.set_shader_parameter("crawl_phase", _crawl_phase)
		material.set_shader_parameter("crawl_amount", _crawl_amount)


func _on_model_action(_action_id: StringName) -> void:
	_action_pulse = 1.0

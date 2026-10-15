extends Node3D
class_name SlimeSpellCastVisual

# One scene-owned presentation for all authored spell profiles. No gameplay
# timers, damage or body transforms are changed by this component.
const SOUND = preload("res://scripts/audio/sound_playback.gd")
const MOTE_COUNT := 8
var hero: SlimeController
var profile: SlimeImpactProfile
var phase: StringName = &"idle"
var charge_count := 0
var release_count := 0
var block_count := 0
var _charge_duration := 0.1
var _cast_key := ""
var _direction := Vector3.FORWARD
var _age := 0.0
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _motes: Array[MeshInstance3D] = []
var _primary: StandardMaterial3D
var _accent: StandardMaterial3D
var _charge_voice: AudioStreamPlayer3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_primary = _material()
	_accent = _material()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_core = _part(sphere, _accent)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.0
	torus.rings = 20
	torus.ring_segments = 6
	_ring = _part(torus, _primary)
	for index in MOTE_COUNT:
		_motes.append(_part(sphere, _primary))
	reset()


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 2
	return material


func _part(mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


func configure(owner_hero: SlimeController) -> void:
	hero = owner_hero


func begin_cast(selected: SlimeImpactProfile, duration: float, direction: Vector3) -> void:
	reset()
	if selected == null or (selected.charge_style == 0 and selected.charge_sound == null and selected.release_sound == null):
		return
	profile = selected
	_direction = direction.normalized()
	_cast_key = hero._cast_key
	_charge_duration = maxf(0.001, duration)
	phase = &"charge"
	charge_count += 1
	_primary.albedo_color = profile.primary_color
	_accent.albedo_color = profile.accent_color
	_charge_voice = SOUND.play_3d(self, profile.charge_sound, hero.global_position, {
		"pitch_variation": profile.cast_pitch_variation, "volume_db": -6.0})
	show()
	set_process(true)
	_draw_stage(0.0)


func release_cast() -> void:
	if phase != &"charge" or profile == null:
		return
	_stop_charge_voice()
	phase = &"release"
	_age = 0.0
	release_count += 1
	SOUND.play_3d(self, profile.release_sound, hero.global_position, {
		"pitch_variation": profile.cast_pitch_variation, "volume_db": -4.0})
	_draw_stage(0.0)


func play_block(selected: SlimeImpactProfile = null) -> void:
	# Called only by the real shell block, including a completely absorbed hit.
	if selected != null:
		profile = selected
	if profile == null or profile.charge_style != 3:
		return
	_cast_key = hero._cast_key
	_direction = hero._action_direction
	_primary.albedo_color = profile.primary_color
	_accent.albedo_color = profile.accent_color
	_stop_charge_voice()
	phase = &"block"
	_age = 0.0
	block_count += 1
	show()
	set_process(true)
	SOUND.play_3d(self, profile.impact_sound, hero.global_position, {
		"pitch_variation": profile.pitch_variation, "volume_db": -2.0})
	_draw_stage(0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(hero) or not hero.is_alive() or hero._cast_key != _cast_key:
		reset()
		return
	if phase == &"charge" and hero._phase != &"preparation":
		# An interrupted cast must not synthesize a release.
		reset()
		return
	_age += delta
	if phase == &"release" or phase == &"block":
		if _age >= maxf(0.05, profile.release_seconds):
			if profile.charge_style == 3 and hero._phase == &"guard":
				phase = &"guard"
				hide()
			else:
				_finish_visual()
				return
	elif phase == &"guard":
		if hero._phase != &"guard":
			reset()
		return
	_draw_stage(delta)


func _draw_stage(_delta: float) -> void:
	if profile == null:
		return
	if profile.charge_style == 0:
		hide()
		return
	var grounded := profile.charge_style == 2
	var shell := profile.charge_style == 3
	var at := hero.global_position + Vector3.UP * (0.06 if grounded else hero._combat_origin_height())
	if not grounded and not shell:
		at += _direction * 0.57
	global_position = at
	global_basis = Basis.looking_at(_direction, Vector3.UP)
	var progress := clampf(1.0 - hero._phase_left / _charge_duration, 0.0, 1.0) if phase == &"charge" else clampf(_age / maxf(0.05, profile.release_seconds), 0.0, 1.0)
	var charging := phase == &"charge"
	var radius := profile.charge_size * (lerpf(0.25, 1.0, progress) if charging else lerpf(1.0, 1.65, progress))
	var fade := 0.85 if charging else (1.0 - progress) * 0.85
	_primary.albedo_color.a = fade
	_accent.albedo_color.a = fade
	_core.visible = not grounded and not shell
	_core.scale = Vector3.ONE * maxf(0.001, radius * (1.0 if charging else 1.0 - progress))
	_core.position = Vector3(0.0, 0.0, 0.0 if charging else -progress * 0.18)
	_ring.show()
	_ring.rotation = Vector3.ZERO if grounded else Vector3(PI * 0.5, 0.0, 0.0)
	_ring.scale = Vector3.ONE * maxf(0.001, radius * (1.4 if not grounded and not shell else 1.0))
	for index in MOTE_COUNT:
		var angle := TAU * float(index) / MOTE_COUNT + _age * (5.0 if profile.trail_style == 0 else 2.0)
		var mote := _motes[index]
		var orbit := profile.charge_size * (lerpf(2.0, 0.7, progress) if charging else lerpf(0.8, 2.3, progress))
		mote.position = Vector3(cos(angle) * orbit, 0.0, sin(angle) * orbit) if grounded else Vector3(cos(angle) * orbit, sin(angle) * orbit, 0.04)
		if grounded:
			mote.position.y = (1.0 - progress) * 0.12
		var width := 0.032 if not shell else 0.04
		mote.scale = Vector3(width, width, width) * maxf(0.05, fade)
		if profile.trail_style == 1:
			mote.scale.y *= 3.2
			mote.rotation.z = angle


func snapshot() -> Dictionary:
	return {"profile": profile, "phase": phase, "charge_visible": visible and phase == &"charge",
		"release_visible": visible and (phase == &"release" or phase == &"block"),
		"charge_count": charge_count, "release_count": release_count, "block_count": block_count}


func _stop_charge_voice() -> void:
	if is_instance_valid(_charge_voice):
		_charge_voice.stop()
		_charge_voice.queue_free()
	_charge_voice = null


func reset() -> void:
	_stop_charge_voice()
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.queue_free()
	_finish_visual()


func _finish_visual() -> void:
	# A release sound can be slightly longer than its flash. Let its finished
	# signal free it naturally; interruption/death/restart still use reset().
	phase = &"idle"
	profile = null
	_age = 0.0
	hide()
	set_process(false)

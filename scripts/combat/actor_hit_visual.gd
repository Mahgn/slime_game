extends Node3D
class_name SlimeActorHitVisual

# Presentation-only parent: the actor's body, velocity and attack clock never
# move with this short recoil. The same node can outlive a defeated actor.
const RECOIL_SECONDS := 0.18
const DEATH_SECONDS := 0.28
const PROFILES := preload("res://scripts/combat/impact_profiles.gd")

var _meshes: Array[MeshInstance3D] = []
var _previous_overlays: Array[Material] = []
var _flash_material: StandardMaterial3D
var _flash_left := 0.0
var _aftermath_left := 0.0
var _aftermath_seconds := 0.0
var _aftermath_color := Color.TRANSPARENT
var _recoil_left := 0.0
var _recoil_strength := 1.0
var _local_direction := Vector3.BACK
var _death_elapsed := -1.0
var _death_start := Vector3.ZERO
var _death_finish := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The alpha pass keeps the overlay visible in GL Compatibility and after
	# the Ink outline, while retaining ordinary wall depth tests.
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 0.98, 0.90, 0.98)
	_flash_material.render_priority = 1
	_flash_material.roughness = 1.0


func bind_visual(visual: Node3D) -> void:
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
		_previous_overlays.append((node as MeshInstance3D).material_overlay)


func play_hit(world_direction: Vector3, profile: SlimeImpactProfile = null) -> void:
	if _death_elapsed >= 0.0:
		return
	if profile == null:
		profile = PROFILES.GENERIC
	var horizontal := Vector3(world_direction.x, 0.0, world_direction.z)
	if horizontal.length_squared() < 0.001:
		horizontal = global_basis.z
	_local_direction = global_basis.inverse() * horizontal.normalized()
	_flash_left = clampf(profile.flash_seconds, 0.0, DEATH_SECONDS)
	_flash_material.albedo_color = profile.flash_color
	_flash_material.albedo_color.a = 0.98
	_aftermath_seconds = clampf(profile.aftermath_seconds, 0.0, 0.6)
	_aftermath_left = _aftermath_seconds
	_aftermath_color = profile.aftermath_color
	_aftermath_color.a = clampf(_aftermath_color.a, 0.0, 0.18)
	_recoil_left = RECOIL_SECONDS
	_recoil_strength = maxf(0.0, profile.recoil_strength)
	for index: int in _meshes.size():
		var mesh := _meshes[index]
		if is_instance_valid(mesh):
			# Keep the actor's normal/Ink material untouched and restore the
			# pre-existing overlay after the flash and optional cosmetic tint.
			mesh.material_overlay = _flash_material if _flash_left > 0.0 or _aftermath_left > 0.0 else _previous_overlays[index]
	if _flash_left <= 0.0:
		_flash_material.albedo_color = _aftermath_color
	_apply_recoil(1.0)
	set_process(true)


func become_remains(ground_position: Vector3) -> void:
	_death_elapsed = 0.0
	_death_start = position
	var room := get_parent() as Node3D
	_death_finish = room.to_local(ground_position + Vector3.UP * 0.02) if room != null else ground_position + Vector3.UP * 0.02
	add_to_group(&"dungeon_creature_remains")
	set_process(true)


func _process(delta: float) -> void:
	var flash_before := _flash_left
	_flash_left = maxf(0.0, _flash_left - delta)
	if _flash_left <= 0.0:
		_aftermath_left = maxf(0.0, _aftermath_left - maxf(0.0, delta - flash_before))
		if _aftermath_left > 0.0:
			var color := _aftermath_color
			color.a *= _aftermath_left / maxf(_aftermath_seconds, 0.001)
			_flash_material.albedo_color = color
		else:
			for index: int in _meshes.size():
				var mesh := _meshes[index]
				if is_instance_valid(mesh) and mesh.material_overlay == _flash_material:
					mesh.material_overlay = _previous_overlays[index]
	if _death_elapsed >= 0.0:
		_death_elapsed = minf(DEATH_SECONDS, _death_elapsed + delta)
		var pop := sin(clampf(_death_elapsed / 0.10, 0.0, 1.0) * PI)
		var collapse := smoothstep(0.065, DEATH_SECONDS, _death_elapsed)
		scale = Vector3.ONE.lerp(Vector3(1.05, 0.34, 1.05), collapse) + Vector3(0.15, 0.12, 0.15) * pop
		position = _death_start.lerp(_death_finish, collapse)
		rotation.x = lerpf(rotation.x, 0.0, minf(1.0, delta * 22.0))
		rotation.z = lerpf(rotation.z, 0.0, minf(1.0, delta * 22.0))
		if _death_elapsed >= DEATH_SECONDS:
			rotation.x = 0.0
			rotation.z = 0.0
			if _aftermath_left <= 0.0 and _flash_left <= 0.0:
				set_process(false)
		return
	_recoil_left = maxf(0.0, _recoil_left - delta)
	var remaining := _recoil_left / RECOIL_SECONDS
	_apply_recoil(remaining * remaining)
	if _recoil_left <= 0.0 and _flash_left <= 0.0 and _aftermath_left <= 0.0:
		set_process(false)


func _apply_recoil(strength: float) -> void:
	strength *= _recoil_strength
	position = _local_direction * (0.16 * strength)
	rotation.x = _local_direction.z * 0.13 * strength
	rotation.z = -_local_direction.x * 0.13 * strength
	scale = Vector3.ONE + Vector3(0.09, -0.13, 0.09) * strength

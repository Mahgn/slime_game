extends Node3D

# Scene-owned presentation. Profiles share a renderer, never gameplay state.
const PROFILES := preload("res://scripts/combat/impact_profiles.gd")
const POOL_SIZE := 8
const SHARD_COUNT := 10
const BURST_SECONDS := 0.30
const HITSTOP_SCALE := 0.08
const REFRACTORY_USEC := 120000

var enabled := true
var impact_count := 0
var contact_count := 0
var player: SlimeController
var _bursts: Array[Dictionary] = []
var _profile_materials: Dictionary = {}
var _round_mesh: SphereMesh
var _angular_mesh: BoxMesh
var _pool_cursor := 0
var _stop_until: int = 0
var _next_stop_at: int = 0
var _saved_time_scale := 1.0
var _owns_time_scale := false
var _stop_serial := 0


func _ready() -> void:
	# The clock must release a stop even when a menu pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_round_mesh = SphereMesh.new()
	_round_mesh.radius = 1.0
	_round_mesh.height = 2.0
	_round_mesh.radial_segments = 6
	_round_mesh.rings = 3
	_angular_mesh = BoxMesh.new()
	_angular_mesh.size = Vector3.ONE * 2.0
	# Built-in materials and geometry are prepared once, never per impact.
	for profile: SlimeImpactProfile in [PROFILES.GENERIC, PROFILES.WHIP, PROFILES.ACID, PROFILES.WEB, PROFILES.SPIKES]:
		_materials_for(profile)
	for slot in POOL_SIZE:
		var burst := Node3D.new()
		burst.name = "ImpactBurst%d" % slot
		add_child(burst)
		var parts: Array[MeshInstance3D] = []
		for index in SHARD_COUNT:
			var shard := MeshInstance3D.new()
			shard.mesh = _round_mesh
			shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			burst.add_child(shard)
			parts.append(shard)
		burst.hide()
		_bursts.append({"node": burst, "parts": parts, "age": BURST_SECONDS,
			"duration": BURST_SECONDS, "direction": Vector3.FORWARD,
			"lethal": false, "contact": false, "profile": PROFILES.GENERIC})


func _materials_for(profile: SlimeImpactProfile) -> Array:
	var key := profile.get_instance_id()
	if _profile_materials.has(key):
		return _profile_materials[key]
	var materials: Array[StandardMaterial3D] = []
	for color: Color in [profile.primary_color, profile.accent_color]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		# Draw after Ink's depth pass, retaining ordinary wall depth tests.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.98
		material.render_priority = 2
		materials.append(material)
	_profile_materials[key] = materials
	return materials


func play_impact(at: Vector3, direction: Vector3, lethal: bool = false, profile: SlimeImpactProfile = null) -> void:
	if not enabled or get_tree().paused:
		return
	if profile == null:
		profile = PROFILES.GENERIC
	impact_count += 1
	var forward := _spawn_burst(at, direction, lethal, profile, false)
	if is_instance_valid(player) and is_instance_valid(player.presentation):
		player.presentation.play_combat_impact(forward, profile.kill_camera_strength if lethal else profile.camera_strength)
	_start_hitstop(profile.kill_hitstop_seconds if lethal else profile.hitstop_seconds)


func play_contact(at: Vector3, direction: Vector3, profile: SlimeImpactProfile = null) -> void:
	# Environment/shell contact has its material accent but no HP-loss accent.
	if not enabled or get_tree().paused:
		return
	if profile == null:
		profile = PROFILES.GENERIC
	contact_count += 1
	_spawn_burst(at, direction, false, profile, true)


func _spawn_burst(at: Vector3, direction: Vector3, lethal: bool, profile: SlimeImpactProfile, contact: bool) -> Vector3:
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var burst: Dictionary = _bursts[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % POOL_SIZE
	burst.age = 0.0
	burst.duration = maxf(0.08, profile.burst_seconds)
	burst.direction = forward
	burst.lethal = lethal
	burst.contact = contact
	burst.profile = profile
	var materials := _materials_for(profile)
	for index in SHARD_COUNT:
		var shard: MeshInstance3D = burst.parts[index]
		shard.mesh = _angular_mesh if profile.particle_style == SlimeImpactProfile.ParticleStyle.SPIKES else _round_mesh
		shard.material_override = materials[1 if index < 3 else 0]
	# Actor events give torso position; contact events give the physics surface.
	burst.node.global_position = at if contact else at - forward * 0.62
	burst.node.show()
	_update_burst(burst)
	return forward


func _start_hitstop(seconds: float) -> void:
	var duration := clampf(seconds, 0.0, 0.10)
	if duration <= 0.0:
		return
	var now: int = Time.get_ticks_usec()
	if _owns_time_scale or now < _next_stop_at:
		return
	# Never take over another system's slow-motion or an external pause.
	if not is_equal_approx(Engine.time_scale, 1.0):
		return
	_saved_time_scale = Engine.time_scale
	_owns_time_scale = true
	_stop_serial += 1
	_stop_until = now + int(duration * 1000000.0)
	_next_stop_at = _stop_until + REFRACTORY_USEC
	Engine.time_scale = HITSTOP_SCALE
	# Unscaled engine time also bounds deterministic fixed-FPS replays: hundreds
	# of simulated frames can pass before a wall-clock-only deadline expires.
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(_release_stop_serial.bind(_stop_serial))


func _release_stop_serial(serial: int) -> void:
	if serial == _stop_serial:
		_release_hitstop()


func _release_hitstop() -> void:
	if not _owns_time_scale:
		return
	if is_equal_approx(Engine.time_scale, HITSTOP_SCALE):
		Engine.time_scale = _saved_time_scale
	_owns_time_scale = false
	_stop_until = 0


func _process(delta: float) -> void:
	if _owns_time_scale and (Time.get_ticks_usec() >= _stop_until or get_tree().paused or not enabled):
		_release_hitstop()
	if get_tree().paused:
		return
	for burst in _bursts:
		if float(burst.age) >= float(burst.duration):
			continue
		burst.age = minf(float(burst.duration), float(burst.age) + delta)
		_update_burst(burst)


func _update_burst(burst: Dictionary) -> void:
	var age: float = burst.age
	var duration: float = burst.duration
	if age >= duration:
		burst.node.hide()
		return
	var profile: SlimeImpactProfile = burst.profile
	var forward: Vector3 = burst.direction
	var right := forward.cross(Vector3.UP).normalized()
	var size := (1.35 if bool(burst.lethal) else 1.0) * (0.72 if bool(burst.contact) else 1.0)
	var progress := age / duration
	var fade := maxf(0.001, 1.0 - progress)
	for index in SHARD_COUNT:
		var angle: float = TAU * float(index) / float(SHARD_COUNT)
		var spread := right * cos(angle) * 0.85 + Vector3.UP * (0.35 + sin(angle) * 0.65)
		var direction := (-forward * (0.45 if index % 2 else 0.85) + spread).normalized()
		var speed := maxf(0.0, profile.particle_speed) * (1.0 + float(index % 3) * 0.196) * size
		var shard: MeshInstance3D = burst.parts[index]
		var particle_scale := profile.particle_size * size * fade
		match profile.particle_style:
			SlimeImpactProfile.ParticleStyle.DROPLETS:
				# Heavy drops arc downward while three bubbles rise nearby.
				if index < 3:
					shard.position = -forward * age * speed * 0.20 + right * cos(angle) * age * 0.42 + Vector3.UP * (0.04 + age * 0.80)
					shard.basis = Basis.IDENTITY
					particle_scale *= 0.55 + sin(progress * PI) * 0.65
				else:
					shard.position = direction * (0.04 + age * speed) + Vector3.UP * (age * 0.45 - age * age * 4.8)
					var velocity := direction * speed + Vector3.UP * (0.45 - age * 9.6)
					shard.basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
					particle_scale.z *= 1.3 - progress * 0.3
			SlimeImpactProfile.ParticleStyle.THREADS:
				# The strands spread softly and sag instead of striking hard.
				var travel := (1.0 - exp(-age * 5.0)) / 5.0
				shard.position = direction * (0.025 + travel * speed) + Vector3.DOWN * age * age * 0.65
				shard.basis = Basis.looking_at((direction + Vector3.DOWN * age * 0.8).normalized(), Vector3.UP)
				particle_scale.z *= 0.55 + sin(progress * PI) * 1.15
			SlimeImpactProfile.ParticleStyle.SPIKES:
				# Faceted fragments burst upward and tumble on the way down.
				var rising := (-forward * 0.35 + right * cos(angle) * 0.75 + Vector3.UP * (0.85 + sin(angle) * 0.30)).normalized()
				shard.position = rising * (0.04 + age * speed) + Vector3.DOWN * age * age * 5.5
				shard.basis = Basis.from_euler(Vector3(age * (4.0 + index), angle + age * 3.0, angle * 0.5))
			_:
				# Short strokes, with three longer accents at the centre.
				shard.position = direction * (0.06 + age * speed) + Vector3.DOWN * age * age * 2.0
				shard.basis = Basis.looking_at(direction, Vector3.UP)
				particle_scale.z *= 1.5 if index < 3 else 1.0
		shard.scale = particle_scale.max(Vector3.ONE * 0.0001)


func active_burst_count() -> int:
	var count := 0
	for burst in _bursts:
		if float(burst.age) < float(burst.duration):
			count += 1
	return count


func hitstop_active() -> bool:
	return _owns_time_scale


func reset() -> void:
	_release_hitstop()
	_stop_serial += 1
	_next_stop_at = 0
	for burst in _bursts:
		burst.age = burst.duration
		burst.node.hide()
	if is_instance_valid(player) and is_instance_valid(player.presentation):
		player.presentation._reset_combat_impact()


func _exit_tree() -> void:
	_release_hitstop()

extends Node3D

# A projectile owns this fixed pool; samples stay in world space, and freeing
# the projectile also removes its trail. No mesh is rebuilt during flight.
const ELEMENT_COUNT := 10
static var _drop_mesh: SphereMesh
static var _thread_mesh: CylinderMesh

var _parts: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _points := PackedVector3Array()
var _born := PackedFloat32Array()
var _cursor := 0
var _clock := 0.0
var _sample_clock := 0.0
var _last_position := Vector3.ZERO
var _direction := Vector3.FORWARD
var _speed := 0.0
var _seconds := 0.0
var _width := 0.03
var _threads := false
var _color := Color.WHITE
var _started := false


func configure(profile: SlimeImpactProfile, at: Vector3, forward: Vector3, speed: float) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_direction = forward.normalized()
	_speed = speed
	_seconds = clampf(profile.trail_seconds, 0.0, 0.5)
	_width = maxf(profile.trail_width, 0.001)
	_threads = profile.trail_style == 1
	_color = profile.accent_color if _threads else profile.primary_color
	_points.resize(ELEMENT_COUNT)
	_born.resize(ELEMENT_COUNT)
	if _drop_mesh == null:
		_drop_mesh = SphereMesh.new()
		_drop_mesh.radius = 1.0
		_drop_mesh.height = 2.0
		_drop_mesh.radial_segments = 8
		_drop_mesh.rings = 4
	if _thread_mesh == null:
		_thread_mesh = CylinderMesh.new()
		_thread_mesh.top_radius = 1.0
		_thread_mesh.bottom_radius = 1.0
		_thread_mesh.height = 1.0
		_thread_mesh.radial_segments = 6
	for index in ELEMENT_COUNT:
		var part := MeshInstance3D.new()
		part.name = "Thread%d" % index if _threads else "Drop%d" % index
		part.mesh = _thread_mesh if _threads else _drop_mesh
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(_color, 0.65)
		# Draw after the Ink pass, but keep ordinary depth testing against walls.
		material.render_priority = 2
		part.material_override = material
		part.visible = false
		add_child(part)
		_parts.append(part)
		_materials.append(material)
	reset_at(at)


func reset_at(at: Vector3) -> void:
	_last_position = at
	_sample_clock = 0.0
	_cursor = 0
	for index in ELEMENT_COUNT:
		_points[index] = at
		_born[index] = -1000.0
		_parts[index].visible = false


func active_sample_count() -> int:
	var count := 0
	for part in _parts:
		if part.visible:
			count += 1
	return count


func advance(at: Vector3, delta: float) -> void:
	if _seconds <= 0.0:
		return
	_clock += delta
	if not _started:
		# Callers position a newly added projectile after its _ready callback.
		_started = true
		reset_at(at)
		return
	var displacement := _last_position.distance_to(at)
	var maximum_step := maxf(1.5, minf(3.0, _speed * delta * 2.5))
	if displacement > maximum_step:
		reset_at(at)
		return
	var interval := _seconds / float(ELEMENT_COUNT)
	_sample_clock += delta
	# Stopped shots stop emitting; their existing samples still expire.
	if displacement > 0.0001:
		var samples := 0
		while _sample_clock >= interval and samples < ELEMENT_COUNT:
			_sample_clock -= interval
			var fraction := clampf(1.0 - _sample_clock / maxf(delta, 0.00001), 0.0, 1.0)
			_points[_cursor] = _last_position.lerp(at, fraction)
			_born[_cursor] = _clock - _sample_clock
			_cursor = (_cursor + 1) % ELEMENT_COUNT
			samples += 1
		_sample_clock = fmod(_sample_clock, interval)
	else:
		# Rendering can run faster than physics. Keep the time accumulated between
		# physical steps, but do not backfill a long pause with identical points.
		_sample_clock = minf(_sample_clock, interval)
	_last_position = at
	_draw_samples()


func _draw_samples() -> void:
	var side := _direction.cross(Vector3.UP).normalized()
	for index in ELEMENT_COUNT:
		var age := _clock - _born[index]
		var part := _parts[index]
		if age >= _seconds or age < 0.0:
			part.visible = false
			continue
		var progress := age / _seconds
		var fade := 1.0 - progress
		_materials[index].albedo_color = Color(_color, 0.65 * fade * fade)
		if _threads:
			var newer := (index + 1) % ELEMENT_COUNT
			var endpoint := _last_position if newer == _cursor else _points[newer]
			if newer != _cursor and _born[newer] <= _born[index]:
				part.visible = false
				continue
			var origin := _points[index]
			var segment := endpoint - origin
			var length := segment.length()
			if length < 0.001 or length > 1.5:
				part.visible = false
				continue
			var up := Vector3.UP if absf(segment.normalized().dot(Vector3.UP)) < 0.95 else Vector3.BACK
			part.basis = Basis.looking_at(segment, up) * Basis(Vector3.RIGHT, PI * 0.5)
			part.position = (origin + endpoint) * 0.5 + side * sin(float(index) * 1.8) * progress * 0.018
			part.scale = Vector3(_width * fade, length, _width * fade)
		else:
			part.position = _points[index] + side * sin(float(index) * 2.4) * progress * 0.065 - Vector3.UP * age * age * 0.9
			var up := Vector3.UP if absf(_direction.dot(Vector3.UP)) < 0.95 else Vector3.BACK
			part.basis = Basis.looking_at(_direction, up)
			part.scale = Vector3(_width, _width, _width * 1.5) * (0.45 + fade * 0.55)
		part.visible = true

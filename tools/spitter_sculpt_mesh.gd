extends RefCounted

## Offline implicit sculpt. A single manifold surface blends head, cheeks,
## brows, torso and upper limbs, instead of intersecting visible primitives.
const STEP := 0.03
const START := Vector3(-0.87, -0.72, -0.78)
const SIZE := Vector3i(59, 41, 53)
const HEAD_PIVOT := Vector3(0.0, -0.035, -0.17)
const EYE_POSITION := Vector3(0.285, 0.25, -0.465)
const MOUTH_POSITION := Vector3(0.0, -0.075, -0.535)
const TETS := [[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]]
var _points := PackedVector3Array()
var _field := PackedFloat32Array()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _indices := PackedInt32Array()
var _edges: Dictionary = {}
var _forms: Array[Dictionary] = []


func build() -> ArrayMesh:
	_forms = [
		{"c": Vector3(0.0, -0.08, 0.16), "r": Vector3(0.465, 0.34, 0.50), "k": 0.11},
		{"c": Vector3(0.0, 0.065, -0.23), "r": Vector3(0.54, 0.245, 0.32), "k": 0.14},
		{"c": Vector3(0.0, -0.205, -0.25), "r": Vector3(0.42, 0.18, 0.30), "k": 0.12},
		{"c": Vector3(0.0, -0.265, -0.025), "r": Vector3(0.39, 0.27, 0.40), "k": 0.10},
	]
	for side in [-1.0, 1.0]:
		_forms.append({"c": Vector3(side * 0.38, -0.06, -0.265), "r": Vector3(0.18, 0.185, 0.245), "k": 0.12})
		_forms.append({"c": Vector3(side * 0.285, 0.265, -0.31), "r": Vector3(0.16, 0.135, 0.185), "k": 0.08})
		_forms.append({"c": Vector3(side * 0.455, -0.35, 0.285), "r": Vector3(0.245, 0.185, 0.29), "k": 0.095})
		_forms.append({"c": Vector3(side * 0.395, -0.29, -0.21), "r": Vector3(0.105, 0.165, 0.13), "k": 0.09})
	var total := SIZE.x * SIZE.y * SIZE.z
	_points.resize(total)
	_field.resize(total)
	for z in SIZE.z:
		for y in SIZE.y:
			for x in SIZE.x:
				var id := _id(x, y, z)
				var p := START + Vector3(x, y, z) * STEP
				_points[id] = p
				_field[id] = _distance(p)
	for z in SIZE.z - 1:
		for y in SIZE.y - 1:
			for x in SIZE.x - 1:
				var cube := [_id(x, y, z), _id(x + 1, y, z), _id(x + 1, y + 1, z), _id(x, y + 1, z), _id(x, y, z + 1), _id(x + 1, y, z + 1), _id(x + 1, y + 1, z + 1), _id(x, y + 1, z + 1)]
				var inside_count := 0
				for corner: int in cube:
					if _field[corner] < 0.0:
						inside_count += 1
				if inside_count == 0 or inside_count == 8:
					continue
				for tet: Array in TETS:
					_polygonize([cube[tet[0]], cube[tet[1]], cube[tet[2]], cube[tet[3]]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_INDEX] = _indices
	var colors := PackedColorArray()
	for index in _vertices.size():
		var occlusion := 0.0
		for distance: float in [0.035, 0.07, 0.13, 0.22]:
			var clearance := _distance(_vertices[index] + _normals[index] * distance)
			occlusion += maxf(0.0, distance - clearance) / distance
		var ambient := clampf(1.0 - occlusion * 0.23, 0.52, 1.0)
		colors.append(Color(ambient, ambient, ambient))
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	print("SCULPT vertices=%d triangles=%d" % [_vertices.size(), _indices.size() / 3])
	return mesh


func _id(x: int, y: int, z: int) -> int:
	return x + SIZE.x * (y + SIZE.y * z)


func _distance(p: Vector3) -> float:
	var result := 10.0
	for form in _forms:
		var d := _ellipsoid(p - (form["c"] as Vector3), form["r"])
		result = _smooth_union(result, d, form["k"])
	# Eye sockets and a mouth crease are carved into the continuous head.
	for side in [-1.0, 1.0]:
		var socket := _ellipsoid(p - Vector3(side * EYE_POSITION.x, EYE_POSITION.y, EYE_POSITION.z - 0.01), Vector3(0.124, 0.093, 0.090))
		result = maxf(result, -socket)
	var mouth_point := p - Vector3(0.0, -0.075, -0.578)
	mouth_point.y -= 0.024 * pow(p.x / 0.251, 2.0)
	mouth_point.z -= 0.114 * pow(p.x / 0.241, 2.0)
	var mouth_cut := _ellipsoid(mouth_point, Vector3(0.26, 0.026, 0.105))
	result = maxf(result, -mouth_cut)
	# Broad anatomical folds, not an even covering of spherical bumps.
	var chin_line := p.y + 0.27 - pow(p.x / 0.43, 2.0) * 0.032
	result += exp(-pow(chin_line * 85.0, 2.0)) * (1.0 - smoothstep(-0.43, -0.28, p.z)) * (1.0 - smoothstep(0.31, 0.43, absf(p.x))) * 0.009
	var back_fold := exp(-pow((absf(p.x) - 0.23) * 28.0, 2.0))
	result -= back_fold * smoothstep(0.0, 0.28, p.z) * smoothstep(0.0, 0.12, p.y) * 0.009
	return result


func _normal(p: Vector3) -> Vector3:
	const E := 0.0015
	return Vector3(_distance(p + Vector3(E, 0, 0)) - _distance(p - Vector3(E, 0, 0)),
		_distance(p + Vector3(0, E, 0)) - _distance(p - Vector3(0, E, 0)),
		_distance(p + Vector3(0, 0, E)) - _distance(p - Vector3(0, 0, E))).normalized()


func _ellipsoid(p: Vector3, radius: Vector3) -> float:
	var q := p / radius
	var k0 := q.length()
	var k1 := (q / radius).length()
	return k0 * (k0 - 1.0) / k1 if k1 > 0.00001 else -minf(radius.x, minf(radius.y, radius.z))


func _smooth_union(a: float, b: float, radius: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / radius, 0.0, 1.0)
	return lerpf(b, a, h) - radius * h * (1.0 - h)


func _polygonize(tet: Array) -> void:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for id: int in tet:
		if _field[id] < 0.0:
			inside.append(id)
		else:
			outside.append(id)
	if inside.size() == 1:
		_triangle(_edge(inside[0], outside[0]), _edge(inside[0], outside[1]), _edge(inside[0], outside[2]))
	elif inside.size() == 3:
		_triangle(_edge(outside[0], inside[0]), _edge(outside[0], inside[1]), _edge(outside[0], inside[2]))
	elif inside.size() == 2:
		var a := _edge(inside[0], outside[0])
		var b := _edge(inside[0], outside[1])
		var c := _edge(inside[1], outside[0])
		var d := _edge(inside[1], outside[1])
		_triangle(a, b, c)
		_triangle(b, d, c)


func _edge(a: int, b: int) -> int:
	var key := mini(a, b) + maxi(a, b) * _points.size()
	if _edges.has(key):
		return _edges[key]
	var t := _field[a] / (_field[a] - _field[b])
	var index := _vertices.size()
	_vertices.append(_points[a].lerp(_points[b], t))
	_normals.append(_normal(_vertices[index]))
	_edges[key] = index
	return index


func _triangle(a: int, b: int, c: int) -> void:
	var cross := (_vertices[b] - _vertices[a]).cross(_vertices[c] - _vertices[a])
	if cross.length_squared() < 0.000000000000000001:
		return
	if cross.dot(_normals[a] + _normals[b] + _normals[c]) > 0.0:
		_indices.append_array(PackedInt32Array([a, c, b]))
	else:
		_indices.append_array(PackedInt32Array([a, b, c]))

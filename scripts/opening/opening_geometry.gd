extends Node3D

# Author-built rooms only. No procedural dungeon generation or runtime randomness.
const STONE_SHADER = preload("res://shaders/opening/stone.gdshader")
var occluders: Array[MeshInstance3D] = []
var cutaway: SlimeRoomCutaway
var stone: ShaderMaterial
var dark_stone: ShaderMaterial
var bronze: StandardMaterial3D
var horizontal_scale := 1.5
var _active_section: StringName = &""
var _section_meshes: Dictionary = {}
var _section_decorations: Dictionary = {}
var _section_floors: Dictionary = {}


func build(room: Dictionary, index: int) -> void:
	cutaway = SlimeRoomCutaway.new()
	cutaway.name = "ArchitecturalCutaway"
	add_child(cutaway)
	stone = _stone(Color("97866b"))
	dark_stone = _stone(Color("706b5d"))
	bronze = _material(Color("68543a"), 0.6)
	for surface: Dictionary in room.floor:
		var poly := _polygon(surface.polygon)
		if index == 2 and surface.id == "A":
			# The return ramp gets an open landing slot. An overlapping flat A
			# slab otherwise creates a vertical step above the sloped surface.
			var slot := PackedVector2Array([Vector2(2.8,6.1),Vector2(8,6.1),Vector2(8,8),Vector2(2.8,8)])
			poly = Geometry2D.clip_polygons(poly,slot)[0]
		var upper: bool = index == 2 and surface.id in ["A", "B", "C"]
		var thickness := 0.15 if upper else 0.30
		if upper:
			_begin_section(StringName("gallery_" + String(surface.id)), float(surface.y))
		var mesh := _slab(String(surface.id), poly, float(surface.y), thickness, dark_stone if String(surface.id).begins_with("recovery") else stone)
		if upper:
			occluders.append(mesh)
		_active_section = &""
	if room.has("ramp"):
		_build_ramp(room.ramp)
	match index:
		0: _hollow(room)
		1: _cistern()
		2: _gallery(room)
	var exit_point := _vector(room.points[1].pos)
	if index == 2:
		_begin_section(&"gallery_C", exit_point.y)
	_portal(exit_point, 0.0 if index == 1 else (-0.32 if index == 0 else -PI * 0.5))
	_lantern(exit_point + Vector3(0.72, 1.25, 0))
	_active_section = &""
	for section_id: StringName in _section_meshes:
		cutaway.register_section(section_id, _section_meshes[section_id], _section_floors[section_id], _section_decorations[section_id])


func _begin_section(section_id: StringName, floor_y: float) -> void:
	_active_section = section_id
	if not _section_meshes.has(section_id):
		var meshes: Array[MeshInstance3D] = []
		var decorations: Array[Node3D] = []
		_section_meshes[section_id] = meshes
		_section_decorations[section_id] = decorations
		_section_floors[section_id] = floor_y


func _stone(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STONE_SHADER
	material.set_shader_parameter("stone_color", color)
	return material


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _polygon(raw: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for point: Array in raw:
		poly.append(Vector2(float(point[0]), float(point[1])))
	# Closed input circles repeat the first vertex; triangulation wants an open list.
	if poly.size() > 3 and poly[0].is_equal_approx(poly[-1]):
		poly.remove_at(poly.size() - 1)
	return poly


func _vector(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _scaled(point: Vector3) -> Vector3:
	return Vector3(point.x*horizontal_scale,point.y,point.z*horizontal_scale)


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Godot's front faces are clockwise; normal and collision faces agree.
	var vertices := [a, b, c] if (b-a).cross(c-a).dot(normal) < 0 else [a, c, b]
	for vertex: Vector3 in vertices:
		tool.set_normal(normal)
		tool.add_vertex(vertex)


func _slab(label: String, poly: PackedVector2Array, y: float, depth: float, material: Material, heights: PackedFloat32Array = PackedFloat32Array(), collide: bool = true) -> MeshInstance3D:
	var triangulation := Geometry2D.triangulate_polygon(poly)
	assert(not triangulation.is_empty(), "Invalid room polygon " + label)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var signed_area := 0.0
	for i in poly.size():
		var h := heights[i] if not heights.is_empty() else y
		top.append(_scaled(Vector3(poly[i].x, h, poly[i].y)))
		bottom.append(_scaled(Vector3(poly[i].x, h-depth, poly[i].y)))
		var next := poly[(i+1) % poly.size()]
		signed_area += poly[i].x * next.y - next.x * poly[i].y
	for i in range(0, triangulation.size(), 3):
		var a := triangulation[i]
		var b := triangulation[i+1]
		var c := triangulation[i+2]
		var normal := (top[b]-top[a]).cross(top[c]-top[a]).normalized()
		if normal.y < 0:
			normal = -normal
		_triangle(tool, top[a], top[b], top[c], normal)
		_triangle(tool, bottom[a], bottom[b], bottom[c], -normal)
	for i in poly.size():
		var j := (i+1) % poly.size()
		var edge := poly[j]-poly[i]
		var normal := Vector3(edge.y, 0, -edge.x).normalized() * (1.0 if signed_area > 0 else -1.0)
		_triangle(tool, top[i], bottom[i], bottom[j], normal)
		_triangle(tool, top[i], bottom[j], top[j], normal)
	tool.index()
	var mesh := tool.commit()
	var parent: Node3D = self
	if collide:
		var body := StaticBody3D.new()
		body.name = label
		body.collision_layer = 1
		body.collision_mask = 2
		add_child(body)
		var shape := CollisionShape3D.new()
		var collision := ConcavePolygonShape3D.new()
		collision.set_faces(mesh.get_faces())
		shape.shape = collision
		body.add_child(shape)
		parent = body
	var visual := MeshInstance3D.new()
	visual.name = label + "Visual"
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	if _active_section != &"":
		_section_meshes[_active_section].append(visual)
		visual.set_meta(&"cutaway_section", _active_section)
	return visual


func _block(at: Vector3, size: Vector3, yaw: float = 0.0, material: Material = null, collide: bool = true, cutaway: bool = true) -> MeshInstance3D:
	var x := size.x * 0.5
	var z := size.z * 0.5
	var bevel := minf(0.045, minf(x,z) * 0.25)
	var poly := PackedVector2Array([Vector2(-x+bevel,-z),Vector2(x-bevel,-z),Vector2(x,-z+bevel),Vector2(x,z-bevel),Vector2(x-bevel,z),Vector2(-x+bevel,z),Vector2(-x,z-bevel),Vector2(-x,-z+bevel)])
	var mesh := _slab("Stone", poly, size.y*0.5, size.y, material if material != null else stone, PackedFloat32Array(), collide)
	var body := mesh.get_parent() as Node3D
	if body == self:
		mesh.position = _scaled(at)
		mesh.rotation.y = yaw
	else:
		body.position = _scaled(at)
		body.rotation.y = yaw
	if cutaway:
		occluders.append(mesh)
	return mesh


func _wall(a: Vector2, b: Vector2, y: float, height: float, width: float = 0.28) -> void:
	var length := a.distance_to(b)
	var direction := (b-a).normalized()
	var yaw := -atan2(direction.y, direction.x)
	var count := maxi(1, int(ceil(length / 0.85)))
	var span := length / count
	# Visual masonry and its continuous collision have the same authored height.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = _scaled(Vector3((a.x+b.x)*0.5, y+height*0.5, (a.y+b.y)*0.5))
	body.rotation.y = yaw
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length*horizontal_scale,height,width*horizontal_scale)
	shape.shape = box
	body.add_child(shape)
	# Few tall modules rather than hundreds of tiny independently rendered bricks.
	for i in count:
		var p := a.lerp(b, (float(i)+0.5)/count)
		var visual := _block(Vector3(p.x,y+height*0.5,p.y),Vector3(span-0.012,height,width),yaw,null,false)
		# Attach to the same physical owner so hidden wall meshes are excluded from aiming.
		visual.reparent(body, true)
		_block(Vector3(p.x,y+height+0.055,p.y),Vector3(span-0.015,0.11,width+0.09),yaw,dark_stone,false)


func _arc_wall(center: Vector2, radius: float, start: float, end: float, y: float, height: float, width: float = 0.18) -> void:
	var count := maxi(1, int(ceil(absf(end-start)/12.0)))
	for i in count:
		_wall(_radial(center,radius,lerpf(start,end,float(i)/count)),_radial(center,radius,lerpf(start,end,float(i+1)/count)),y,height,width)


func _radial(center: Vector2, radius: float, degrees: float) -> Vector2:
	return center + Vector2(cos(deg_to_rad(degrees)),sin(deg_to_rad(degrees))) * radius


func _rib(base: Vector3, inward: Vector3, height: float, reach: float) -> void:
	_block(base+Vector3.UP*0.16,Vector3(0.76,0.32,0.76),0,dark_stone)
	for i in 8:
		var t0 := float(i)/8.0 * PI * 0.47
		var t1 := float(i+1)/8.0 * PI * 0.47
		var a := base + inward * reach * (1-cos(t0)) + Vector3.UP * (0.28+height*sin(t0))
		var b := base + inward * reach * (1-cos(t1)) + Vector3.UP * (0.28+height*sin(t1))
		var mesh := _block((a+b)*0.5,Vector3(0.46,_scaled(a).distance_to(_scaled(b))+0.025,0.50))
		var owner := mesh.get_parent() as Node3D
		owner.quaternion = Quaternion(Vector3.UP,(_scaled(b)-_scaled(a)).normalized())
		if i == 3:
			_block((a+b)*0.5,Vector3(0.53,0.12,0.57),0,bronze,false)


func _portal(at: Vector3, yaw: float) -> void:
	var across := Vector3(cos(yaw),0,-sin(yaw))
	for side in [-1.0,1.0]:
		_block(at+across*side*1.10+Vector3.UP*0.8,Vector3(0.36,1.6,0.45),yaw)
		_block(at+across*side*1.10+Vector3.UP*0.12,Vector3(0.5,0.24,0.6),yaw,dark_stone)
	for i in 9:
		var a := PI * float(i)/9.0
		var b := PI * float(i+1)/9.0
		var center := at+across * (1.1*cos((a+b)*0.5)) + Vector3.UP * (1.60+0.72*sin((a+b)*0.5))
		_block(center,Vector3(0.40,0.30,0.45),yaw)


func _lantern(at: Vector3) -> void:
	_block(at,Vector3(0.24,0.12,0.28),0,bronze,false,false)
	var glow := _material(Color("ffcf8a"),0.4)
	glow.emission_enabled = true
	glow.emission = Color("ffc47c")
	glow.emission_energy_multiplier = 0.7
	_block(at+Vector3.UP*0.1,Vector3(0.10,0.14,0.10),0,glow,false,false)
	var light := OmniLight3D.new()
	light.position = _scaled(at+Vector3.UP*0.25)
	light.light_color = Color("ffd3a0")
	light.light_energy = 1.3
	light.omni_range = 3.4*horizontal_scale
	add_child(light)
	if _active_section != &"":
		_section_decorations[_active_section].append(light)


func _hollow(room: Dictionary) -> void:
	var perimeter := _polygon(room.floor[0].polygon)
	for i in perimeter.size():
		var a := perimeter[i]
		var b := perimeter[(i+1)%perimeter.size()]
		# Side exit opens through the northeast edge; no wall across the exit.
		if a.x > 6.0 and b.x > 6.0 and minf(a.y,b.y) < 2.0:
			continue
		# The fixed camera looks from +X/+Z: foreground boundaries stay low,
		# while the far fractured wall keeps the room's tall silhouette.
		_wall(a,b,0,2.0 if (a.y+b.y)*0.5 < 2.8 else 0.25,0.38)
	var rubble: Dictionary = room.features[0]
	_slab("RubbleBank",_polygon(rubble.polygon),0.66,0.66,dark_stone)
	for i in 9:
		var x := 0.9 + float(i%3)*0.65
		var z := 0.9 + float(i/3)*0.52
		_block(Vector3(x,0.8+float(i%2)*0.11,z),Vector3(0.72,0.48,0.63),float(i)*0.47,dark_stone)
	# Large fractured outcrops separate the natural fissure from intact masonry.
	var rock_material := _material(Color("626455"))
	var rock := _slab("FissureRock",PackedVector2Array([Vector2(0.1,1.3),Vector2(0.6,0.3),Vector2(1.1,0.7),Vector2(1.35,2.5),Vector2(0.3,3.2)]),0,2.2,rock_material,PackedFloat32Array([2.1,2.8,2.3,1.4,1.0]))
	occluders.append(rock)
	var a := Vector3(0.8,3.1,1.5)
	var b := Vector3(3.3,1.0,1.8)
	for i in 8:
		var p := a.lerp(b,(float(i)+0.5)/8.0)
		var mesh := _block(p,Vector3(0.70,_scaled(a).distance_to(_scaled(b))/8.0,0.62))
		(mesh.get_parent() as Node3D).quaternion = Quaternion(Vector3.UP,(_scaled(b)-_scaled(a)).normalized())
	var light := SpotLight3D.new()
	light.position = _scaled(Vector3(2.2,4.2,1.7))
	light.light_color = Color("cfdfed")
	light.light_energy = 2.2
	light.spot_range = 8.0
	light.spot_angle = 32.0
	light.shadow_enabled = true
	add_child(light)
	light.look_at(_scaled(Vector3(3.3,0,3.8)))


func _cistern() -> void:
	# Three distant bays retain the vault; the ten camera-facing bays become
	# a continuous low parapet, revealing the whole walkway before movement.
	_arc_wall(Vector2(3.5,3.5),3.52,-78,-42,0.35,1.65,0.30)
	_arc_wall(Vector2(3.5,3.5),3.52,-42,78,0.35,0.25,0.30)
	_arc_wall(Vector2(3.5,3.5),1.66,24,90,0.35,0.25)
	_arc_wall(Vector2(3.5,3.5),1.66,-90,-24,0.35,0.25)
	var basin := PackedVector2Array()
	for i in 48:
		basin.append(_radial(Vector2(3.5,3.5),1.57,float(i)*7.5))
	var water := _material(Color(0.19,0.44,0.46,0.70),0.20)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slab("Water",basin,0.378,0.012,water,PackedFloat32Array(),false)
	# Low outer lip closes the half-disc's unwalkable left edge.
	_arc_wall(Vector2(3.5,3.5),1.67,90,270,0.35,0.25)
	for angle in [-72.0,0.0,72.0]:
		var p := _radial(Vector2(3.5,3.5),3.47,angle)
		var inward := Vector3(3.5-p.x,0,3.5-p.y).normalized()
		_rib(Vector3(p.x,0.35,p.y),inward,2.65,1.5)
	# The entry and exit are framed by curved masonry, not an enclosing box.
	_wall(Vector2(2.3,6),Vector2(2.4,7.5),0.35,0.25)
	_wall(Vector2(4.7,6),Vector2(4.6,7.5),0.35,0.25)


func _gallery(room: Dictionary) -> void:
	var center := Vector2(3.9,3.9)
	# The lower route has its own low edge; it never belongs to an upper slice.
	_arc_wall(center,1.94,100,370,-0.80,0.25,0.12)
	# Upper parapets stop short of both jump edges.
	var gap: float = room.jumps[0].angularGapDegrees
	for section in [[&"gallery_A",100.0,200.0,0.35],[&"gallery_B",205.0+gap+5.0,286.0,0.8],[&"gallery_C",291.0+gap+5.0,365.0,1.25]]:
		_begin_section(section[0], section[3])
		# A and C face the camera; the distant B parapets retain their height.
		var front: bool = section[0] != &"gallery_B"
		_arc_wall(center,3.66,section[1],section[2],section[3],0.25 if front else 0.55,0.16)
		_arc_wall(center,1.94,section[1],section[2],section[3],0.25 if front else 0.45,0.12)
	_active_section = &""
	_arc_wall(center,3.66,205,320,-0.8,0.25,0.16)
	_wall(Vector2(7.65,4),Vector2(7.65,7.8),-0.8,0.25)
	_wall(Vector2(2.8,7.79),Vector2(7.65,7.79),-0.8,0.25)
	_begin_section(&"gallery_A", 0.35)
	_rib(Vector3(1.3,0.35,1.6),Vector3(0.75,0,0.66).normalized(),2.9,1.75)
	# Keep the footing outside C's new landing area after widening the route.
	var upper_rib := _radial(center,3.8,330.0)
	_begin_section(&"gallery_C", 1.25)
	_rib(Vector3(upper_rib.x,1.25,upper_rib.y),Vector3(3.9-upper_rib.x,0,3.9-upper_rib.y).normalized(),2.5,1.1)
	_active_section = &""
	# Broad masonry footings on the inside of the shaft, outside the return route.
	for angle in [145.0,260.0,350.0]:
		var p := _radial(center,1.5,angle)
		_block(Vector3(p.x,-1.05,p.y),Vector3(0.5,1.5,0.5),0,dark_stone)


func _build_ramp(ramp: Dictionary) -> void:
	var poly := PackedVector2Array([Vector2(3.8,6.1),Vector2(6.8,6.1),Vector2(6.8,7.7),Vector2(3.8,7.7)])
	var heights := PackedFloat32Array()
	for point in poly:
		heights.append(lerpf(0.35,-0.80,inverse_lerp(3.8,6.8,point.x)))
	_slab("ReturnRamp",poly,0,0.15,stone,heights)
	_slab("RampLanding",PackedVector2Array([Vector2(2.8,6.1),Vector2(3.8,6.1),Vector2(3.8,7.7),Vector2(2.8,7.7)]),0.35,0.15,stone)

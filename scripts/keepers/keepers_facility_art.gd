extends SlimeKeepersGeometry

# F04 authored kit. Mesh profiles and bevels are built once, then batched by
# material. Small details are visual; equipment keeps explicit solid blockers.
var masonry: ShaderMaterial
var copper: ShaderMaterial
var iron: ShaderMaterial
var service_paths: Array[Dictionary] = []

func prepare() -> void:
	_stone = _vertex_material(0.94)
	_metal = _vertex_material(0.6,0.5)
	_cloth = _vertex_material(1.0)
	_wood = ShaderMaterial.new()
	_wood.shader = WOOD_SHADER
	_coal = _vertex_material(0.8)
	_coal.emission_enabled = true
	_coal.emission = Color("bd4112")
	_coal.emission_energy_multiplier = 0.65
	masonry = ShaderMaterial.new()
	masonry.shader = preload("res://shaders/keepers/facility_stone.gdshader")
	copper = ShaderMaterial.new()
	copper.shader = preload("res://shaders/keepers/facility_metal.gdshader")
	iron = ShaderMaterial.new()
	iron.shader = copper.shader
	iron.set_shader_parameter("oxidation",Color("382d23"))
	iron.set_shader_parameter("metalness",0.52)

func finish() -> void:
	_flush_batches()

func service_portal() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "VaultedServicePortal"
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	for segment in 11:
		var a := segment*PI/11.0+0.006
		var b := (segment+1)*PI/11.0-0.006
		var mesh := _arch_stone(Vector3(0,1.72,0.48),1.78,2.13,a,b,0.96,Color("8a795a").darkened((segment%3)*0.035))
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		shape.position = Vector3(0,1.72,0.48)
		body.add_child(shape)
	for side in [-1,1]:
		_block("PortalUpperJamb",Vector3(side*1.965,1.385,0),Vector3(0.35,0.67,0.96),Color("807156"),masonry,0.035)
		_block("PortalImpost",Vector3(side*1.965,1.71,0),Vector3(0.48,0.14,1.06),Color("9a8561"),masonry,0.026)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.48,0.74,1.06)
		shape.shape = box
		shape.position = Vector3(side*1.965,1.42,0)
		body.add_child(shape)
	return body

func conduit(corners: Array, radius: float, color: Color) -> void:
	# Round the center line at each elbow. A single swept tube avoids intersecting
	# cylinders with black caps in the middle of a connected service run.
	var path: Array[Vector3] = [corners[0]]
	for i in range(1,corners.size()-1):
		var point: Vector3 = corners[i]
		var incoming: Vector3 = (point-corners[i-1]).normalized()
		var outgoing: Vector3 = (corners[i+1]-point).normalized()
		var bend := minf(0.65,minf(point.distance_to(corners[i-1]),point.distance_to(corners[i+1]))*0.35)
		var start := point-incoming*bend
		var end := point+outgoing*bend
		for step in 7:
			var t := step/6.0
			path.append(start.lerp(point,t).lerp(point.lerp(end,t),t))
	path.append(corners[-1])
	service_paths.append({"points":path.duplicate(),"radius":radius})
	# Exposed services are physical. A short feed must not become another
	# decorative tube that characters can stand inside. Buried runs need no body.
	var body := StaticBody3D.new()
	body.name = "ServicePipeCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	for i in range(path.size()-1):
		var a := path[i]
		var b := path[i+1]
		if maxf(a.y,b.y)+radius<0 or a.distance_to(b)<0.001: continue
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = a.distance_to(b)+2*radius
		shape.shape = capsule
		shape.transform = Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
		body.add_child(shape)
	if body.get_child_count()>0: add_child(body)
	else: body.free()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frames: Array[Basis] = []
	for i in path.size():
		var tangent := (path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
		frames.append(Basis(Quaternion(Vector3.UP,tangent)))
	for i in range(path.size()-1):
		for side in 20:
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(i,side),Vector2i(i,side+1),Vector2i(i+1,side+1),Vector2i(i+1,side)]:
				var a := corner.y*TAU/20
				var normal := frames[corner.x]*Vector3(sin(a),0,cos(a))
				vertices.append(path[corner.x]+normal*radius)
				normals.append(normal)
			for triangle in [[0,1,2],[0,2,3]]:
				var order: Array = triangle.duplicate()
				if (vertices[order[1]]-vertices[order[0]]).cross(vertices[order[2]]-vertices[order[0]]).dot(normals[order[0]])>0:
					order.reverse()
				for index: int in order:
					tool.set_normal(normals[index])
					tool.set_color(color)
					tool.set_uv(Vector2(vertices[index].x,vertices[index].z))
					tool.add_vertex(vertices[index])
	tool.index()
	_emit("SweptServicePipe",tool.commit(),Transform3D.IDENTITY,copper,false)
	for index in [0,path.size()-1]:
		_ring("PipeUnion",path[index],radius*1.14,0.055,Color("41483a"),iron,frames[index])
	for i in range(corners.size()-1):
		var start: Vector3 = corners[i]
		var end: Vector3 = corners[i+1]
		if start.distance_to(end)>3.0:
			var middle := start.lerp(end,0.5)
			var basis := Basis(Quaternion(Vector3.UP,(end-start).normalized()))
			_ring("PipeSupportCollar",middle,radius*1.05,0.045,Color("545b49"),iron,basis)

func furnace(at: Vector3) -> void:
	_block("HearthFoundation",at+Vector3(0,0.22,0),Vector3(5.6,0.44,4.6),Color("50473b"),masonry,0.10)
	_collision_box("FireboxFoundation",at+Vector3(0,0.22,0),Vector3(5.6,0.44,4.6),0)
	for side in [-1,1]:
		_collision_box("FireboxCheek",at+Vector3(side*2.2,1.55,0),Vector3(1.1,2.7,3.8),0)
		for row in 6:
			for column in 4:
				var shade := Color("79614a").darkened(0.055*((row+column*3)%4))
				_block("RefractoryCheek",at+Vector3(side*2.2,0.65+row*0.43,-1.42+column*0.94),Vector3(1.07,0.405,0.91),shade,masonry,0.045)
	_collision_box("FireboxBack",at+Vector3(0,1.5,-1.4),Vector3(4.8,2.6,0.7),0)
	_block("RefractoryBack",at+Vector3(0,1.5,-1.4),Vector3(4.6,2.6,0.7),Color("2e2b25"),masonry,0.06)
	# Deep barrel vault: actual wedge stones, visible intrados and keystone.
	for depth in 4:
		for segment in 11:
			var a := segment*PI/11.0+0.009
			var b := (segment+1)*PI/11.0-0.009
			_arch_stone(at+Vector3(0,1.08,2.00-depth*0.69),1.48,1.82,a,b,0.67,Color("947953").darkened(0.04*((segment+depth*3)%4)))
	for x in [-1.65,1.65]:
		for row in 2:
			_block("ArchSpringer",at+Vector3(x,0.60+row*0.32,1.67),Vector3(0.34,0.30,0.66),Color("9b805c"),masonry,0.055)
	# Tapered sheet-metal hood and stack give the machine a distinct silhouette.
	_profile_box(at+Vector3(0,0,-0.25),[
		Vector3(2.49,2.9,1.68),Vector3(2.49,3.06,1.68),
		Vector3(1.65,3.58,1.16),Vector3(1.65,3.70,1.16)
	],Color("766247"),copper,true)
	for x in [-1.55,0.0,1.55]:
		_strut(at+Vector3(x,3.08,1.416),at+Vector3(x*0.68,3.58,0.925),0.045,Color("a88b5e"),copper)
	_lathe("RivetedFlue",at+Vector3(0,3.64,-0.35),[Vector2(0,0),Vector2(0.63,0),Vector2(0.7,0.13),Vector2(0.6,0.24),Vector2(0.58,1.07),Vector2(0.66,1.14),Vector2(0.66,1.29),Vector2(0,1.29)],Color("353a36"),iron,Basis.IDENTITY,true)
	for y in [3.97,4.54]:
		_ring("FlueBand",at+Vector3(0,y,-0.35),0.60,0.065,Color("8d754e"),copper)
	# Recessed glowing fuel, an ash drawer and a hinged grille rather than a
	# bright solid rectangle pasted across the front of the firebox.
	_block("BlackFirebox",at+Vector3(0,0.95,0.7),Vector3(3.3,1.4,0.4),Color("201d18"),_stone,0.07)
	_collision_box("BlackFirebox",at+Vector3(0,0.95,0.7),Vector3(3.3,1.4,0.4),0)
	for i in 32:
		_shard(at+Vector3(sin(i*5.7)*1.32,0.49+0.035*sin(i*1.7),1.05+float(i%4)*0.17),Vector3(0.20,0.08,0.20),Color("9b461b").darkened((i%5)*0.08),_coal,i)
	for x in range(-6,7):
		_strut(at+Vector3(x*0.22,0.48,1.83),at+Vector3(x*0.22,1.13,1.72),0.031,Color("3a3630"),iron)
	for y in [0.51,1.12]:
		_strut(at+Vector3(-1.48,y,1.84),at+Vector3(1.48,y,1.84),0.05,Color("473c2e"),iron)
	_block("AshDrawer",at+Vector3(0,0.24,2.19),Vector3(2.42,0.24,0.21),Color("373932"),iron,0.035)
	_strut(at+Vector3(-0.34,0.3,2.34),at+Vector3(0.34,0.3,2.34),0.032,Color("9e855e"),copper)
	for side in [-1,1]:
		for y in [0.78,1.45,2.20]:
			_block("HearthIronTie",at+Vector3(side*2.24,y,1.95),Vector3(0.86,0.105,0.10),Color("363a34"),iron,0.017)
			for dx in [-0.27,0.27]:
				_rivet(at+Vector3(side*2.24+dx,y,2.01),0.047)
	# The rack and shovel stay on the broad plinth, outside fighting routes.
	_strut(at+Vector3(2.63,0.45,1.15),at+Vector3(2.63,2.1,0.96),0.045,Color("4d3d2c"),_wood)
	_block("CoalShovel",at+Vector3(2.63,0.55,1.17),Vector3(0.38,0.50,0.09),Color("434940"),iron,0.05)
	_ring("ShovelGrip",at+Vector3(2.63,2.18,0.95),0.14,0.023,Color("9a784b"),_wood,Basis(Vector3.RIGHT,PI/2))
	_light(at+Vector3(0,0.95,2.15),Color("ff9d4d"),2.8,7.0,true)

func boiler(at: Vector3, radius: float) -> void:
	# Turned pressure vessel: rounded shoulder and lid, not a cylinder with a
	# straight cone. The old floor footprint and collision heights are retained.
	_cylinder("BoilerFoot",at+Vector3.UP*0.23,radius+0.35,radius+0.45,0.46,Color("4e4c40"),masonry,true,40)
	_lathe("FormedCopperVessel",at,[Vector2(0,0.40),Vector2(radius*0.91,0.40),Vector2(radius*0.98,0.50),Vector2(radius,0.69),Vector2(radius,2.65),Vector2(radius*0.98,2.91),Vector2(radius*0.90,3.12),Vector2(radius*0.75,3.32),Vector2(radius*0.52,3.45),Vector2(radius*0.25,3.50),Vector2(0,3.51)],Color("997348"),copper,Basis.IDENTITY,true)
	for y in [0.69,1.63,2.63]:
		_ring("RivetedVesselBand",at+Vector3.UP*y,radius+0.018,0.065,Color("343b35"),iron)
		for i in 32:
			var a := i*TAU/32.0
			_rivet(at+Vector3(sin(a)*(radius+0.09),y,cos(a)*(radius+0.09)),0.05,Basis(Vector3.UP,a))
	# Upright rolled seams break the copper into plausible sheet panels.
	for i in 8:
		var a := i*TAU/8.0+PI/8
		var p := Vector3(sin(a)*(radius+0.012),0,cos(a)*(radius+0.012))
		_strut(at+p+Vector3.UP*0.75,at+p+Vector3.UP*2.55,0.022,Color("b2905c"),copper)
	_lathe("BoltedServiceLid",at+Vector3.UP*3.49,[Vector2(0,0),Vector2(0.66,0),Vector2(0.66,0.1),Vector2(0.55,0.16),Vector2(0,0.16)],Color("424a40"),iron)
	for i in 10:
		var a := i*TAU/10
		_cylinder("LidBolt",at+Vector3(sin(a)*0.54,3.68,cos(a)*0.54),0.055,0.055,0.07,Color("b39562"),copper,false,6)
	_strut(at+Vector3(-0.28,3.67,0),at+Vector3(-0.28,3.86,0),0.055,Color("aa8956"),copper)
	_strut(at+Vector3(0.28,3.67,0),at+Vector3(0.28,3.86,0),0.055,Color("aa8956"),copper)
	_strut(at+Vector3(-0.28,3.86,0),at+Vector3(0.28,3.86,0),0.055,Color("aa8956"),copper)
	var face := at+Vector3(0,1.29,radius+0.03)
	_lathe("InspectionHatch",face,[Vector2(0,0),Vector2(0.70,0),Vector2(0.70,0.09),Vector2(0.59,0.16),Vector2(0,0.16)],Color("435c51"),iron,Basis(Vector3.RIGHT,PI/2))
	_ring("HatchBrassRim",face+Vector3(0,0,0.16),0.56,0.05,Color("ac8952"),copper,Basis(Vector3.RIGHT,PI/2))
	for i in 8:
		var a := i*TAU/8
		_rivet(face+Vector3(sin(a)*0.63,cos(a)*0.63,0.2),0.058)
	_strut(face+Vector3(-0.24,0,0.24),face+Vector3(0.24,0,0.24),0.045,Color("b49662"),copper)
	_gauge(at+Vector3(-0.86,2.24,radius+0.09),0.34)
	# A protected water-level glass, connected top and bottom to the vessel.
	for x in [0.73,1.0]:
		_strut(at+Vector3(x,1.8,radius),at+Vector3(x,2.59,radius),0.045,Color("b5915a"),copper)
	_block("WaterLevelGlass",at+Vector3(0.865,2.20,radius),Vector3(0.13,0.71,0.09),Color("568476"),_metal,0.035)
	for y in [1.87,2.02,2.17,2.32,2.47]:
		_block("LevelScale",at+Vector3(0.78,y,radius+0.062),Vector3(0.14,0.019,0.02),Color("dcc897"),_stone,0.005)

func coal_bin(at: Vector3, size: Vector3) -> void:
	_collision_box("CoalMass",at+Vector3.UP*size.y*0.45,size*Vector3(0.90,0.70,0.93),0)
	for side in [-1,1]:
		_collision_box("CoalBinWall",at+Vector3(side*size.x*0.5,size.y*0.5,0),Vector3(0.15,size.y,size.z),0)
		for row in 4:
			_block("CoalBinPlank",at+Vector3(side*size.x*0.5,0.13+row*0.255,0),Vector3(0.15,0.23,size.z),Color("695035").lightened(row*0.025),_wood,0.02)
		for z in [-size.z*0.44,0.0,size.z*0.44]:
			_block("BinIronStrap",at+Vector3(side*(size.x*0.5+0.085),0.54,z),Vector3(0.035,1.08,0.1),Color("323b34"),iron,0.01)
	# Overlapping irregular chunks hide the solid collision proxy entirely.
	for x in 8:
		for z in 12:
			var px := (x/7.0-0.5)*size.x*0.86
			var pz := (z/11.0-0.5)*size.z*0.91
			var mound := 0.15*(1.0-absf(px)/(size.x*0.5))
			_shard(at+Vector3(px+sin(z*5+x)*0.07,0.63+mound+sin(x*7+z*3)*0.07,pz+sin(x*7+z)*0.09),Vector3(0.31,0.27,0.33),Color("272c27").lightened(((x*3+z)%5)*0.017),_stone,x+z*8)
	# A small spill is tucked against the bin, never on the main route.
	for i in 11:
		_shard(at+Vector3(size.x*0.53+sin(i*4)*0.13,0.045,cos(i*5)*size.z*0.43),Vector3(0.08,0.06,0.11),Color("353831"),_stone,i)

func cart(at: Vector3) -> void:
	_collision_box("CargoCart",at+Vector3.UP*0.6,Vector3(1.8,0.35,2.4),0)
	for i in 6:
		_block("CartBedPlank",at+Vector3(-0.75+i*0.30,0.70,0),Vector3(0.275,0.15,2.4),Color("88633c").darkened((i%3)*0.07),_wood,0.025)
	for z in [-0.80,0.80]:
		_strut(at+Vector3(-1.04,0.41,z),at+Vector3(1.04,0.41,z),0.065,Color("3a4036"),iron)
		for side in [-1,1]:
			var wheel := at+Vector3(side*1.0,0.41,z)
			var rotation := Basis(Vector3.FORWARD,PI/2)
			_ring("CartIronTyre",wheel,0.36,0.05,Color("313c35"),iron,rotation)
			_ring("WheelWoodRim",wheel,0.31,0.045,Color("8a673c"),_wood,rotation)
			_cylinder("WheelAxle",wheel,0.10,0.10,0.20,Color("a98c57"),copper,false,10,Vector3(0,0,PI/2))
			for spoke in 8:
				var a := spoke*TAU/8
				_strut(wheel,wheel+Vector3(0,sin(a),cos(a))*0.31,0.025,Color("82663c"),_wood)
	for side in [-1,1]:
		_block("CartLongFrame",at+Vector3(side*0.82,0.56,0),Vector3(0.15,0.25,2.45),Color("55472e"),_wood,0.028)
		_strut(at+Vector3(side*0.7,0.65,1.1),at+Vector3(side*0.7,0.85,2),0.055,Color("917042"),_wood)
	_sack(at+Vector3(-0.4,0.78,-0.4),0.5,0.7)
	_sack(at+Vector3(0.4,0.78,0.4),0.4,0.6)

func _gauge(at: Vector3, radius: float) -> void:
	var basis := Basis(Vector3.RIGHT,PI/2)
	_lathe("GaugeHousing",at,[Vector2(0,0),Vector2(radius,0),Vector2(radius,0.12),Vector2(radius*0.9,0.16),Vector2(0,0.16)],Color("a38c5d"),copper,basis)
	_cylinder("GaugeEnamel",at+Vector3(0,0,0.17),radius*0.81,radius*0.81,0.016,Color("d7c89f"),_stone,false,32,Vector3(PI/2,0,0))
	for i in 9:
		var a := lerpf(-2.2,2.2,i/8.0)
		_strut(at+Vector3(sin(a)*radius*0.61,cos(a)*radius*0.61,0.185),at+Vector3(sin(a)*radius*0.73,cos(a)*radius*0.73,0.185),0.008,Color("3d4539"),_stone)
	_strut(at+Vector3(0,0,0.2),at+Vector3(-radius*0.48,radius*0.38,0.2),0.013,Color("944023"),_stone)

func _arch_stone(at: Vector3, inner: float, outer: float, a: float, b: float, depth: float, color: Color) -> ArrayMesh:
	var points: Array[Vector3] = []
	for z in [0.0,-depth]:
		for item in [Vector2(inner,a),Vector2(outer,a),Vector2(outer,b),Vector2(inner,b)]:
			points.append(Vector3(cos(item.y)*item.x,sin(item.y)*item.x,z))
	var mesh := _solid(points,[[0,1,2,3],[7,6,5,4],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]],color)
	_emit("VaultVoussoir",mesh,Transform3D(Basis.IDENTITY,at),masonry,false)
	return mesh

func _profile_box(at: Vector3, rings: Array, color: Color, material: Material, collide: bool = false) -> void:
	var points: Array[Vector3] = []
	var faces: Array = []
	for ring: Vector3 in rings:
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			points.append(Vector3(corner.x*ring.x,ring.y,corner.y*ring.z))
	for j in range(rings.size()-1):
		for i in 4:
			faces.append([j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i])
	faces.append([0,3,2,1])
	var last := (rings.size()-1)*4
	faces.append([last,last+1,last+2,last+3])
	_emit("FoldedMetalHood",_solid(points,faces,color),Transform3D(Basis.IDENTITY,at),material,collide)

func _solid(points: Array[Vector3], faces: Array, color: Color) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var middle := Vector3.ZERO
	for p in points:
		middle += p/points.size()
	for face: Array in faces:
		var a: Vector3 = points[face[0]]
		var normal := (points[face[1]]-a).cross(points[face[2]]-a).normalized()
		var center := Vector3.ZERO
		for index: int in face:
			center += points[index]/face.size()
		if normal.dot(center-middle)<0:
			normal = -normal
		for i in range(1,face.size()-1):
			_triangle(tool,a,points[face[i]],points[face[i+1]],normal,color)
	tool.index()
	return tool.commit()

func _block(label: String, at: Vector3, size: Vector3, color: Color, material: Material, bevel: float, basis: Basis = Basis.IDENTITY) -> void:
	# Complete 26-face chamfer: six faces, twelve edge strips, eight corners.
	var h := size*0.5
	var b := minf(bevel,minf(h.x,minf(h.y,h.z))*0.8)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis+1)%3
		var v := (axis+2)%3
		for sign_value in [-1,1]:
			var face: Array[Vector3] = []
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p := Vector3.ZERO
				p[axis] = h[axis]*sign_value
				p[u] = (h[u]-b)*corner.x
				p[v] = (h[v]-b)*corner.y
				face.append(p)
			_triangle(tool,face[0],face[1],face[2],normal,color)
			_triangle(tool,face[0],face[2],face[3],normal,color)
	for edge_axis in 3:
		var u := (edge_axis+1)%3
		var v := (edge_axis+2)%3
		for su in [-1,1]:
			for sv in [-1,1]:
				var face: Array[Vector3] = []
				for item in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
					var p := Vector3.ZERO
					p[edge_axis] = item.x*(h[edge_axis]-b)
					p[u] = (h[u]-b*item.y)*su
					p[v] = (h[v]-b*(1-item.y))*sv
					face.append(p)
				var normal := Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				normal = normal.normalized()
				_triangle(tool,face[0],face[1],face[2],normal,color.lightened(0.035))
				_triangle(tool,face[0],face[2],face[3],normal,color.lightened(0.035))
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:
				var signs := Vector3(x,y,z)
				var p := (h-Vector3.ONE*b)*signs
				_triangle(tool,p+Vector3(x*b,0,0),p+Vector3(0,y*b,0),p+Vector3(0,0,z*b),signs.normalized(),color.lightened(0.045))
	tool.index()
	_emit(label,tool.commit(),Transform3D(basis,at),material,false)

func _lathe(label: String, at: Vector3, profile: Array, color: Color, material: Material, basis: Basis = Basis.IDENTITY, collide: bool = false) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 40
	for j in range(profile.size()-1):
		for i in SEGMENTS:
			var quad: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for index: Vector2i in [Vector2i(j,i),Vector2i(j,i+1),Vector2i(j+1,i+1),Vector2i(j+1,i)]:
				var p: Vector2 = profile[index.x]
				var tangent: Vector2 = profile[mini(index.x+1,profile.size()-1)]-profile[maxi(index.x-1,0)]
				var a := index.y*TAU/SEGMENTS
				quad.append(Vector3(sin(a)*p.x,p.y,cos(a)*p.x))
				normals.append(Vector3(sin(a)*tangent.y,-tangent.x,cos(a)*tangent.y).normalized())
			for triangle in [[0,1,2],[0,2,3]]:
				var order: Array = triangle.duplicate()
				if (quad[order[1]]-quad[order[0]]).cross(quad[order[2]]-quad[order[0]]).dot(normals[order[0]])>0:
					order.reverse()
				for index: int in order:
					tool.set_normal(normals[index])
					tool.set_color(color)
					tool.set_uv(Vector2(quad[index].x,quad[index].z))
					tool.add_vertex(quad[index])
	tool.index()
	_emit(label,tool.commit(),Transform3D(basis,at),material,collide)

func _ring(label: String, at: Vector3, radius: float, thickness: float, color: Color, material: Material, basis: Basis = Basis.IDENTITY) -> void:
	var profile: Array[Vector2] = []
	for i in 9:
		var a := i*TAU/8
		profile.append(Vector2(radius+cos(a)*thickness,sin(a)*thickness))
	_lathe(label,at,profile,color,material,basis)

func _strut(a: Vector3, b: Vector3, radius: float, color: Color, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_emit("ForgedDetail",_color_mesh(cylinder,color),Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5),material,false)

func _rivet(at: Vector3, radius: float, basis: Basis = Basis.IDENTITY) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2
	sphere.radial_segments = 8
	sphere.rings = 3
	_emit("HammeredRivet",_color_mesh(sphere,Color("b09c6b")),Transform3D(basis.scaled(Vector3(1,1,0.65)),at),copper,false)

func _shard(at: Vector3, size: Vector3, color: Color, material: Material, seed_value: int) -> void:
	var points: Array[Vector3] = []
	for y in [-0.6,0.45]:
		for i in 5:
			var a := i*TAU/5+seed_value*0.45
			points.append(Vector3(sin(a)*(0.8+0.2*sin(i+seed_value)),y+sin(i*2+seed_value)*0.17,cos(a))*size)
	points.append(Vector3(0.08,0.85,0)*size)
	var faces: Array = [[4,3,2,1,0]]
	for i in 5:
		faces.append([i,(i+1)%5,(i+1)%5+5,i+5])
		faces.append([i+5,(i+1)%5+5,10])
	_emit("CoalShard",_solid(points,faces,color),Transform3D(Basis.IDENTITY,at),material,false)

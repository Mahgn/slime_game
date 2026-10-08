extends "res://scripts/keepers/keepers_facility_craft.gd"

# Wall assemblies use +Z as the room-facing side. Their back plane is Z=0;
# the room builder mounts and parents the entire assembly to a wall section.
func service_detail(role: String, width: float) -> void:
	match role:
		"intake", "hearth", "collector", "sluice":
			_vent(width, role)
		"pressure", "boiler", "water":
			_instrument_panel(width, role)
		"parts", "tools":
			_parts_shelf(width, role)
		"plan":
			_waterworks_plan(width)

func _frame(width: float, height: float, color: Color, material: Material) -> void:
	_block("SealedBacking",Vector3(0,0,0.025),Vector3(width,height,0.05),Color("282f29"),iron,0.018)
	for side in [-1,1]:
		_block("FrameUpright",Vector3(side*(width*0.5-0.055),0,0.075),Vector3(0.11,height,0.15),color,material,0.024)
		_block("FrameCrosspiece",Vector3(0,side*(height*0.5-0.055),0.075),Vector3(width-0.22,0.11,0.15),color,material,0.024)
		for y in [-height*0.5+0.08,height*0.5-0.08]:
			_rivet(Vector3(side*(width*0.5-0.055),y,0.158),0.028)

func _vent(width: float, role: String) -> void:
	var height := 0.7 if role=="hearth" else 1.18
	_frame(width,height,Color("697060"),masonry)
	if role=="intake" or role=="hearth":
		for i in 5:
			_block("OverlappingVentLouver",Vector3(0,-height*0.33+i*height*0.165,0.103),Vector3(width-0.22,height*0.17,0.035),Color("4f5c51"),iron,0.008,Basis(Vector3.RIGHT,-0.32))
	else:
		var bars := int(width/0.22)
		for i in bars:
			var x := lerpf(-width*0.5+0.18,width*0.5-0.18,float(i)/float(bars-1))
			_block("RecessGrilleBar",Vector3(x,0,0.09),Vector3(0.034,height-0.16,0.045),Color("424d40"),iron,0.007)
		_block("GrilleTie",Vector3(0,-0.12,0.12),Vector3(width-0.19,0.045,0.035),Color("766c50"),iron,0.007)
		if role=="collector":
			# Short ivy stems start in the lower mortar joint, all within the frame.
			for i in 6:
				var x := -width*0.35+i*width*0.12
				var tip := Vector3(x+0.1,-0.02+(i%3)*0.10,0.17)
				_strut(Vector3(x,-height*0.46,0.06),tip,0.012,Color("4a5230"),foliage)
				_block("MortarIvyLeaf",tip,Vector3(0.12,0.19,0.018),Color("647648").darkened((i%3)*0.08),foliage,0.016,Basis(Vector3.FORWARD,0.4 if i%2==0 else -0.4))

func _instrument_panel(width: float, role: String) -> void:
	var height := 1.3
	_frame(width,height,Color("716e50"),iron)
	_block("InstrumentEnamel",Vector3(0,0,0.058),Vector3(width-0.25,height-0.25,0.025),Color("475b51"),iron,0.028)
	var count := 3 if width>2.0 else 2
	for i in count:
		var x := lerpf(-width*0.30,width*0.30,float(i)/float(count-1))
		var radius := 0.21 if count==3 else 0.19
		_gauge(Vector3(x,0.23,0.08),radius)
		# Each pressure take-off disappears through a bolted gland in the plate.
		_strut(Vector3(x,0.04,0.14),Vector3(x,-0.32,0.14),0.022,Color("9b8756"),copper)
		_strut(Vector3(x,-0.32,0.14),Vector3(x,-0.32,0.07),0.029,Color("9b8756"),copper)
		_ring("PanelGland",Vector3(x,-0.32,0.092),0.055,0.018,Color("ad9763"),copper,Basis(Vector3.RIGHT,PI/2))
		_block("InstrumentTag",Vector3(x,-0.49,0.084),Vector3(radius*1.3,0.065,0.012),Color("b3aa84"),_cloth,0.005)
	if role=="water":
		_block("LevelGlass",Vector3(0,-0.15,0.10),Vector3(0.08,0.60,0.045),Color("84ada0"),copper,0.008)
	elif role=="boiler":
		_block("IsolationLever",Vector3(0,-0.14,0.17),Vector3(0.30,0.055,0.06),Color("754b36"),_wood,0.012)

func _parts_shelf(width: float, role: String) -> void:
	_frame(width,1.35,Color("685636"),_wood)
	for y in [-0.45,0.15]:
		_block("PartsShelf",Vector3(0,y,0.22),Vector3(width-0.14,0.065,0.44),Color("89704a"),_wood,0.012)
		for sign_value in [-1,1]:
			var x: float = sign_value*(width*0.5-0.17)
			_strut(Vector3(x,y-0.19,0.07),Vector3(x,y-0.034,0.37),0.022,Color("404f41"),iron)
		for i in 3:
			var x := (i-1)*(width-0.36)/3.0
			var bottom: float = y+0.0325
			shelf_supply(Vector3(x,bottom,0.23),i+(3 if y>0 else 0)+(1 if role=="tools" else 0))

func _waterworks_plan(width: float) -> void:
	_frame(width,1.42,Color("715a3a"),_wood)
	_block("SurveyParchment",Vector3(0,0,0.062),Vector3(width-0.23,1.18,0.024),Color("aeaa83"),_cloth,0.008)
	# A diagram of connected reservoirs; no language is baked into the art.
	var points := [Vector3(-0.92,-0.25,0.08),Vector3(-0.55,0.30,0.08),Vector3(0,-0.1,0.08),Vector3(0.62,0.25,0.08),Vector3(0.99,-0.28,0.08)]
	for i in range(points.size()-1):
		var elbow := Vector3(points[i+1].x,points[i].y,0.08)
		_strut(points[i],elbow,0.012,Color("596e62"),_cloth)
		_strut(elbow,points[i+1],0.012,Color("596e62"),_cloth)
	for point: Vector3 in points:
		_ring("SurveyReservoir",point,0.115,0.016,Color("685b42"),_cloth,Basis(Vector3.RIGHT,PI/2))
	for side in [-1,1]:
		_block("PlanClamp",Vector3(side*(width*0.5-0.25),0.52,0.10),Vector3(0.11,0.09,0.035),Color("9c895b"),copper,0.009)

func work_mat(at: Vector3, size: Vector2, color: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/keepers/facility_work_mat.gdshader")
	material.set_shader_parameter("cloth_color",color)
	material.set_shader_parameter("mat_size",size)
	var mesh := MeshInstance3D.new()
	mesh.name = "WornWorkMat"
	mesh.mesh = plane
	mesh.material_override = material
	mesh.position = at+Vector3.UP*0.012
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

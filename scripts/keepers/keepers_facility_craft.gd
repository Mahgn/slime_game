extends "res://scripts/keepers/keepers_facility_props.gd"

# Authored construction, with the previous equipment envelopes retained.
# Profiles are built once and join the existing material batches.
const SACK_PROFILE = [Vector2(0,0),Vector2(0.62,0),Vector2(0.87,0.12),Vector2(1,0.33),Vector2(0.92,0.58),Vector2(0.68,0.77),Vector2(0.30,0.87),Vector2(0.21,0.91),Vector2(0.28,0.98),Vector2(0.17,1.0),Vector2(0,0.96)]
var burlap: ShaderMaterial

func prepare() -> void:
	super.prepare()
	_wood.shader=preload("res://shaders/keepers/facility_timber.gdshader")
	burlap=ShaderMaterial.new()
	burlap.shader=preload("res://shaders/keepers/facility_burlap.gdshader")

func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	# Face-local coordinates also work for vertical masonry and its bevels.
	var points := [a,b,c] if (b-a).cross(c-a).dot(normal)<0.0 else [a,c,b]
	for point: Vector3 in points:
		var uv := Vector2(point.x,point.y)
		if absf(normal.y)>0.7: uv=Vector2(point.x,point.z)
		elif absf(normal.x)>0.7: uv=Vector2(point.z,point.y)
		tool.set_normal(normal); tool.set_color(color); tool.set_uv(uv); tool.add_vertex(point)

func _sack_point(row: int, angle: float, radius: float, height: float, phase: float) -> Vector3:
	var p: Vector2=SACK_PROFILE[row]
	var gather := smoothstep(0.55,0.88,p.y)
	var fold := 1.0+sin(angle*9.0+phase+p.y*3.0)*(0.025+gather*0.12)+sin(angle*4.0+p.y*6.0)*0.025
	return Vector3(sin(angle)*radius*p.x*fold*(1.0-0.05*p.y)+sin(p.y*PI)*radius*0.09,p.y*height,cos(angle)*radius*p.x*fold*0.89)

func _sack(at: Vector3, radius: float, height: float) -> void:
	var phase := at.x*1.7+at.z*2.3
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 40
	for row in range(SACK_PROFILE.size()-1):
		for i in SEGMENTS:
			var points: Array[Vector3]=[]
			var normals: Array[Vector3]=[]
			var uvs: Array[Vector2]=[]
			for index: Vector2i in [Vector2i(row,i),Vector2i(row,i+1),Vector2i(row+1,i+1),Vector2i(row+1,i)]:
				var angle := float(index.y)*TAU/SEGMENTS
				var side := _sack_point(index.x,angle+0.01,radius,height,phase)-_sack_point(index.x,angle-0.01,radius,height,phase)
				var up := _sack_point(mini(index.x+1,SACK_PROFILE.size()-1),angle,radius,height,phase)-_sack_point(maxi(index.x-1,0),angle,radius,height,phase)
				var normal := side.cross(up).normalized()
				if normal.length_squared()<0.1: normal=Vector3.DOWN if index.x==0 else Vector3.UP
				points.append(_sack_point(index.x,angle,radius,height,phase))
				normals.append(normal)
				uvs.append(Vector2(float(index.y)/SEGMENTS,SACK_PROFILE[index.x].y))
			for triangle in [[0,1,2],[0,2,3]]:
				var order: Array=triangle.duplicate()
				if (points[order[1]]-points[order[0]]).cross(points[order[2]]-points[order[0]]).dot(normals[order[0]])>0: order.reverse()
				for j: int in order:
					tool.set_normal(normals[j]); tool.set_uv(uvs[j]); tool.set_color(Color("978a64")); tool.add_vertex(points[j])
	tool.index()
	_emit("GatheredClothSack",tool.commit(),Transform3D(Basis.IDENTITY,at),burlap,true)
	for y in [0.888,0.917]:
		_ring("SackTwine",at+Vector3.UP*height*y,radius*0.235,0.011,Color("b6a374"),_cloth)
	var knot := at+Vector3(radius*0.21,height*0.90,0)
	_block("TwineKnot",knot,Vector3(0.06,0.045,0.045),Color("b6a374"),_cloth,0.018)
	_strut(knot,knot+Vector3(0.08,-0.09,0.025),0.009,Color("b6a374"),_cloth)
	_strut(knot,knot+Vector3(0.025,-0.12,-0.03),0.009,Color("b6a374"),_cloth)
	for row in range(1,7):
		var a := _sack_point(row,0.40,radius,height,phase)*Vector3(1.01,1,1.01)
		var b := _sack_point(row+1,0.40,radius,height,phase)*Vector3(1.01,1,1.01)
		_strut(at+a,at+b,0.006,Color("746743"),_cloth)
		for stitch in 3:
			var p := a.lerp(b,stitch/3.0)
			_strut(at+p-Vector3(0.012,0.008,0),at+p+Vector3(0.012,0.008,0),0.004,Color("c0ac7a"),_cloth)

func shelf_supply(at: Vector3, variant: int) -> void:
	var tone: Color=[Color("688879"),Color("a98e60"),Color("757459"),Color("967158")][variant%4]
	if variant%3==0:
		_lathe("GlazedServiceBottle",at,[Vector2(0,0),Vector2(0.085,0),Vector2(0.09,0.025),Vector2(0.087,0.17),Vector2(0.068,0.21),Vector2(0.036,0.23),Vector2(0.036,0.30),Vector2(0.043,0.305),Vector2(0.043,0.325),Vector2(0,0.325)],tone,copper)
		_cylinder("BottleCork",at+Vector3.UP*0.339,0.029,0.03,0.028,Color("9c7951"),_wood,false,12)
		_block("BottlePaperBand",at+Vector3(0,0.135,0.083),Vector3(0.10,0.076,0.016),Color("c1b088"),_cloth,0.006)
	elif variant%3==1:
		_lathe("OilCanPressedBody",at,[Vector2(0,0),Vector2(0.09,0),Vector2(0.092,0.025),Vector2(0.082,0.19),Vector2(0.03,0.22),Vector2(0,0.22)],tone,iron)
		_strut(at+Vector3(0.03,0.19,0),at+Vector3(0.12,0.28,0),0.022,tone,iron)
		_strut(at+Vector3(0.12,0.28,0),at+Vector3(0.15,0.33,0),0.012,Color("b9a574"),copper)
		_ring("CanLoopHandle",at+Vector3(-0.077,0.13,0),0.064,0.010,tone,iron,Basis(Vector3.RIGHT,PI/2))
	else:
		_lathe("PackingJar",at,[Vector2(0,0),Vector2(0.091,0),Vector2(0.098,0.035),Vector2(0.095,0.17),Vector2(0.084,0.20),Vector2(0.084,0.215),Vector2(0,0.215)],tone,masonry)
		_lathe("JarRolledLid",at+Vector3.UP*0.21,[Vector2(0,0),Vector2(0.101,0),Vector2(0.101,0.02),Vector2(0.080,0.037),Vector2(0,0.037)],Color("625139"),_wood)
		_ring("JarBinding",at+Vector3.UP*0.185,0.088,0.008,Color("bba875"),_cloth)

func valve_wheel(at: Vector3, radius: float) -> void:
	var face := Basis(Vector3.RIGHT,PI/2)
	var cast := Color("507365")
	_strut(at-Vector3(0,0,0.38),at+Vector3(0,0,0.03),0.060,Color("9a8b61"),copper)
	_lathe("ValveStemGland",at-Vector3(0,0,0.19),[Vector2(0,0),Vector2(0.13,0),Vector2(0.13,0.065),Vector2(0.08,0.11),Vector2(0,0.11)],cast,iron,face)
	_ring("ContinuousCastHandwheel",at,radius,0.042,cast,iron,face)
	_ring("HandwheelWornLip",at+Vector3(0,0,0.023),radius-0.015,0.013,Color("8e987a"),iron,face)
	for spoke in 5:
		var angle := spoke*TAU/5+0.18
		var p := at+Vector3(cos(angle),sin(angle),0)*radius*0.25-Vector3(0,0,0.025)
		var q := at+Vector3(cos(angle+0.12),sin(angle+0.12),0)*radius*0.63-Vector3(0,0,0.035)
		var r := at+Vector3(cos(angle+0.17),sin(angle+0.17),0)*radius
		_strut(p,q,0.028,cast,iron); _strut(q,r,0.032,cast,iron)
	_lathe("HandwheelHub",at-Vector3(0,0,0.055),[Vector2(0,0),Vector2(radius*0.25,0),Vector2(radius*0.25,0.11),Vector2(radius*0.18,0.13),Vector2(0,0.13)],cast,iron,face)
	_cylinder("SpindleLockNut",at+Vector3(0,0,0.09),0.055,0.055,0.05,Color("b8a16b"),copper,false,6,Vector3(PI/2,0,0))

func cargo_crate(at: Vector3, size: Vector3) -> void:
	_collision_box("CargoCrate",at,size,0)
	_block("CrateInterior",at,size-Vector3.ONE*0.07,Color("3e382a"),_wood,0.022)
	for i in 6:
		var x := -size.x*0.5+(i+0.5)*size.x/6
		var tone := Color("79603f").lightened(float((i*7)%5)*0.023)
		for side in [-1,1]:
			_block("IndividualCrateBoard",at+Vector3(x,0,side*(size.z*0.5-0.025)),Vector3(size.x/6-0.012,size.y-0.025,0.05),tone,_wood,0.014)
		_block("CrateLidBoard",at+Vector3(x,size.y*0.5-0.025,0),Vector3(size.x/6-0.010,0.05,size.z-0.025),tone,_wood,0.012)
	for side in [-1,1]:
		for i in 5:
			_block("CrateEndBoard",at+Vector3(side*(size.x*0.5-0.024),0,-size.z*0.5+(i+0.5)*size.z/5),Vector3(0.048,size.y-0.02,size.z/5-0.009),Color("756040").lightened((i%3)*0.025),_wood,0.012)
		for y in [-0.36,0.36]:
			_block("CrateBindingRail",at+Vector3(0,size.y*y,side*(size.z*0.5+0.025)),Vector3(size.x,0.12,0.065),Color("967a4d"),_wood,0.017)
			for x in [-size.x*0.43,size.x*0.43]:
				_rivet(at+Vector3(x,size.y*y,side*(size.z*0.5+0.063)),0.023)
		var slope: float = atan2(size.y*0.63,size.x*0.80)*side
		_block("CrateDiagonalBrace",at+Vector3(0,0,side*(size.z*0.5+0.028)),Vector3(Vector2(size.x*0.80,size.y*0.63).length(),0.10,0.060),Color("8b7046"),_wood,0.015,Basis(Vector3.BACK,slope))
		_block("CrateLidBatten",at+Vector3(side*size.x*0.37,size.y*0.5+0.019,0),Vector3(0.10,0.038,size.z),Color("9a7e50"),_wood,0.009)
		for z in [-size.z*0.39,size.z*0.39]:
			_rivet(at+Vector3(side*size.x*0.37,size.y*0.5+0.04,z),0.017)
	# Small geometric shipping stencil, not a baked language label.
	for x in [-0.10,0.10]:
		_block("ShippingMark",at+Vector3(x,-size.y*0.14,size.z*0.5+0.052),Vector3(0.035,0.16,0.008),Color("b4ac87"),_cloth,0.002)

func coopered_barrel(at: Vector3, radius: float, height: float) -> void:
	# Keep the old two-frustum physical envelope. Staves seal around it.
	_cylinder("BarrelLowerCore",at+Vector3.UP*height*0.25,radius-0.012,radius*0.83,height*0.5,Color("3f3425"),_wood,true,20)
	# The recessed head must remain above the inner core's cap.
	_cylinder("BarrelUpperCore",at+Vector3.UP*(height*0.75-0.025),radius*0.83,radius-0.012,height*0.5-0.05,Color("3f3425"),_wood,true,20)
	var rings := [Vector2(0.84,0),Vector2(0.93,0.18),Vector2(1,0.42),Vector2(1,0.58),Vector2(0.93,0.82),Vector2(0.84,1)]
	for stave in 18:
		var points: Array[Vector3]=[]
		var faces: Array=[]
		var a := stave*TAU/18+0.005
		var b := (stave+1)*TAU/18-0.005
		for ring: Vector2 in rings:
			for item in [Vector2(ring.x*radius,a),Vector2(ring.x*radius,b),Vector2(ring.x*radius-0.04,b),Vector2(ring.x*radius-0.04,a)]:
				points.append(Vector3(sin(item.y)*item.x,ring.y*height,cos(item.y)*item.x))
		for row in range(rings.size()-1):
			for j in 4: faces.append([row*4+j,row*4+(j+1)%4,(row+1)*4+(j+1)%4,(row+1)*4+j])
		faces.append([3,2,1,0]); faces.append([20,21,22,23])
		_emit("CurvedCooperStave",_solid(points,faces,Color("886b45").darkened((stave*7%6)*0.027)),Transform3D(Basis.IDENTITY,at),_wood,false)
	for y in [0.10,0.28,0.72,0.90]:
		var r: float=radius*(0.84+0.16*sin(y*PI))
		_lathe("RolledBarrelHoop",at+Vector3.UP*height*y,[Vector2(r-0.014,-0.037),Vector2(r+0.014,-0.037),Vector2(r+0.014,0.037),Vector2(r-0.014,0.037),Vector2(r-0.014,-0.037)],Color("465147"),iron)
		for i in 9:
			var a := i*TAU/9
			_rivet(at+Vector3(sin(a)*(r+0.018),height*y,cos(a)*(r+0.018)),0.016)
	var lid := radius*0.80
	for board in 5:
		var x0 := -lid+2*lid*board/5.0+0.003
		var x1 := -lid+2*lid*(board+1)/5.0-0.003
		var polygon := PackedVector2Array()
		for i in 5:
			var x := lerpf(x0,x1,i/4.0)
			polygon.append(Vector2(at.x+x,at.z-sqrt(maxf(0,lid*lid-x*x))))
		for i in range(4,-1,-1):
			var x := lerpf(x0,x1,i/4.0)
			polygon.append(Vector2(at.x+x,at.z+sqrt(maxf(0,lid*lid-x*x))))
		var heights := PackedFloat32Array(); heights.resize(polygon.size()); heights.fill(at.y+height-0.025)
		_prism("InsetBarrelHead",polygon,heights,0.04,Color("9a7e50").darkened((board%3)*0.035),_wood,true)
	_cylinder("BarrelBung",at+Vector3(radius*0.28,height-0.011,0),0.056,0.061,0.025,Color("66543a"),_wood,false,12)

func archive_cabinet(at: Vector3, length: float) -> void:
	_collision_box("RecordsCabinet",at+Vector3(0.15,1.2,0),Vector3(1,2.4,length+0.14),0)
	for i in 18:
		_block("CabinetBackBoard",at+Vector3(-0.18,1.17,-length*0.5+(i+0.5)*length/18),Vector3(0.18,2.34,length/18-0.008),Color("55452e").lightened((i%4)*0.025),_wood,0.01)
	for y in [0.13,0.84,1.59,2.34]:
		_block("CabinetShelf",at+Vector3(0.15,y,0),Vector3(1,0.12,length+0.1),Color("8a6b40"),_wood,0.025)
		_block("ShelfMouldedNose",at+Vector3(0.64,y-0.014,0),Vector3(0.06,0.072,length+0.1),Color("a38653"),_wood,0.024)
	for z in [-length*0.5,0,length*0.5]:
		_block("CabinetUpright",at+Vector3(0,1.2,z),Vector3(0.91,2.4,0.14),Color("75603b"),_wood,0.028)
		for y in [0.35,1.05,1.80]:
			_block("CabinetJoineryPeg",at+Vector3(0.464,y,z),Vector3(0.012,0.04,0.06),Color("b09766"),_wood,0.005)
	for row in 3:
		for bay in 2:
			var start: float=-length*0.5+0.17+bay*length*0.5
			var z := start
			var stacked := (row+bay)%2==0
			for i in (8 if stacked else 10):
				var seed_value := i+row*11+bay*7
				var width := 0.13+(seed_value*7%5)*0.025
				var h := 0.38+(seed_value*5%7)*0.030
				var base: float=[0.19,0.90,1.65][row]
				var tint: Color=[Color("685044"),Color("465e52"),Color("9b8150"),Color("594b3e"),Color("714b3a")][seed_value%5]
				_bound_book(at+Vector3(0.25,base,z+width*0.5),width,h,0.48,tint,Basis(Vector3.UP,PI/2),seed_value)
				z+=width+0.022
			if stacked:
				for i in 2:
					var base: float=[0.19,0.90,1.65][row]
					_bound_book(at+Vector3(0.25,base+0.065+i*0.13,start+2.25),0.13,0.49,0.45,Color("72533e") if i==0 else Color("69715a"),Basis(Vector3.UP,PI/2)*Basis(Vector3.BACK,PI/2),row*7+i)
			# A tied packet of loose repair sheets breaks the regular spines.
			var center := at+Vector3(0.24,[0.19,0.90,1.65][row]+0.075,start+2.54)
			for packet in 5:
				_block("UnevenRepairPages",center+Vector3((packet%2)*0.007,-0.06+packet*0.03,0),Vector3(0.48-(packet%3)*0.012,0.03,0.32),Color("b7a980").darkened((packet%3)*0.035),_cloth,0.006)
			for sign_value in [-1,1]:
				_strut(center+Vector3(0,-0.07,sign_value*0.165),center+Vector3(0,0.083,sign_value*0.165),0.007,Color("735b37"),_cloth)
			_strut(center+Vector3(0,0.083,-0.165),center+Vector3(0,0.083,0.165),0.007,Color("735b37"),_cloth)
			_ring("PaperBundleKnot",center+Vector3(0.014,0.088,0),0.019,0.006,Color("917747"),_cloth)

func _bound_book(at: Vector3, width: float, height: float, depth: float, tone: Color, basis: Basis, seed_value: int) -> void:
	_block("CutPageBlock",at+basis*Vector3(0,height*0.5,-0.012),Vector3(width-0.032,height-0.036,depth-0.065),Color("b6a780").darkened((seed_value%3)*0.05),_cloth,0.010,basis)
	for side in [-1,1]:
		_block("LeatherBookBoard",at+basis*Vector3(side*(width*0.5-0.009),height*0.5,0),Vector3(0.018,height,depth),tone,_cloth,0.008,basis)
		for i in 7:
			_block("ExposedPageEdges",at+basis*Vector3(side*(width*0.5-0.023),0.047+i*(height-0.09)/7,-0.035),Vector3(0.006,0.005,depth-0.10),Color("8f825e"),_cloth,0.002,basis)
	_block("RoundedLeatherSpine",at+basis*Vector3(0,height*0.5,depth*0.5-0.011),Vector3(width,height,0.07),tone.lightened(0.07),_cloth,minf(0.027,width*0.2),basis)
	for y in [0.13,0.30,0.78,0.9]:
		_block("RaisedBindingCord",at+basis*Vector3(0,height*y,depth*0.5+0.024),Vector3(width-0.01,0.013,0.019),tone.lightened(0.22),_cloth,0.006,basis)
	_block("JournalSpineTicket",at+basis*Vector3(0,height*0.56,depth*0.5+0.027),Vector3(width*0.62,height*0.21,0.010),Color("b6a379"),_cloth,0.003,basis)
	for i in 2:
		_block("TicketInkRule",at+basis*Vector3(0,height*(0.52+i*0.07),depth*0.5+0.033),Vector3(width*(0.34+i*0.07),0.008,0.003),Color("685941"),_cloth,0.001,basis)

extends Node3D

# One continuous top for the building, carved by the UNION of playable spaces.
# Coordinate subdivision shares every edge exactly; no independently capped
# room boxes, overlaps, slits or camera-dependent section heights.
var openings: Array[Rect2] = []
var playable_openings: Array[Rect2] = []
var service_slots: Array[Rect2] = [Rect2(-0.8,-9.5,2.0,7.5),Rect2(1.35,-20.0,1.3,3.6),Rect2(-1.5,-44.0,3.0,6.0)]
var solid_cells: Array[Rect2] = []
var top_height := 3.4
var mesh_instance: MeshInstance3D

func build(rooms: Dictionary, links: Array, wall_width: float, height: float) -> void:
	top_height=height
	var xs: Array[float]=[-39.0,29.0]
	var zs: Array[float]=[-79.0,29.0]
	for room: Dictionary in rooms.values():
		var half: Vector2=room.half-Vector2.ONE*wall_width*0.5
		openings.append(Rect2(Vector2(room.center.x,room.center.z)-half,half*2))
	for link: Dictionary in links:
		var a := Vector2(link.path[0].x,link.path[0].z)
		var b := Vector2(link.path[-1].x,link.path[-1].z)
		var direction := (b-a).normalized()
		a-=direction*wall_width*0.5
		b+=direction*wall_width*0.5
		var across := Vector2(absf(direction.y),absf(direction.x))*(float(link.width)-wall_width)*0.5
		var lo := a.min(b)-across
		var hi := a.max(b)+across
		openings.append(Rect2(lo,hi-lo))
	playable_openings.assign(openings)
	for slot: Rect2 in service_slots:
		for playable: Rect2 in playable_openings:
			assert(not slot.grow(0.25).intersects(playable),"Service well intrudes into playable space")
		openings.append(slot)
	for opening: Rect2 in openings:
		for inset in [0.0,0.09,0.18,0.25]:
			for x in [opening.position.x-inset,opening.end.x+inset]:
				var snapped := snappedf(x,0.001)
				if not xs.has(snapped): xs.append(snapped)
			for z in [opening.position.y-inset,opening.end.y+inset]:
				var snapped := snappedf(z,0.001)
				if not zs.has(snapped): zs.append(snapped)
	xs.sort(); zs.sort()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(xs.size()-1):
		for j in range(zs.size()-1):
			var cell := Rect2(Vector2(xs[i],zs[j]),Vector2(xs[i+1]-xs[i],zs[j+1]-zs[j]))
			if _is_open(cell.get_center()): continue
			solid_cells.append(cell)
			var a := Vector3(cell.position.x,height,cell.position.y)
			var b := Vector3(cell.end.x,height,cell.position.y)
			var c := Vector3(cell.end.x,height,cell.end.y)
			var d := Vector3(cell.position.x,height,cell.end.y)
			var edge_distance := INF
			for opening: Rect2 in openings:
				var point := cell.get_center()
				var dx := maxf(maxf(opening.position.x-point.x,point.x-opening.end.x),0)
				var dz := maxf(maxf(opening.position.y-point.y,point.y-opening.end.y),0)
				edge_distance=minf(edge_distance,maxf(dx,dz))
			var tone := Color("252b25")
			if edge_distance<0.09: tone=Color("101919")
			elif edge_distance<0.18: tone=Color("31413b")
			elif edge_distance<0.25: tone=Color("101919")
			tone.a=clampf(edge_distance,0.0,1.0)
			_quad(tool,a,b,c,d,Vector3.UP,tone)
			for edge in [[a,b,Vector3.FORWARD],[b,c,Vector3.RIGHT],[c,d,Vector3.BACK],[d,a,Vector3.LEFT]]:
				var middle: Vector3=(edge[0]+edge[1])*0.5+edge[2]*0.003
				if _is_open(Vector2(middle.x,middle.z)):
					# Continuous cornice: one height, flush at every junction.
					_quad(tool,edge[0],edge[0]-Vector3.UP*0.065,edge[1]-Vector3.UP*0.065,edge[1],edge[2],Color("425351"))
					_quad(tool,edge[0]-Vector3.UP*0.065,edge[0]-Vector3.UP*0.18,edge[1]-Vector3.UP*0.18,edge[1]-Vector3.UP*0.065,edge[2],Color("182322"))
	tool.index()
	mesh_instance=MeshInstance3D.new()
	mesh_instance.name="ContinuousBuildingCrown"
	mesh_instance.mesh=tool.commit()
	var material := ShaderMaterial.new()
	material.shader=preload("res://shaders/keepers/building_crown.gdshader")
	mesh_instance.material_override=material
	add_child(mesh_instance)
	_build_service_wells()

func _build_service_wells() -> void:
	var kit := SlimeKeepersGeometry.new()
	kit.name="RecessedServiceWells"
	add_child(kit)
	kit._stone=kit._vertex_material(0.98)
	kit._metal=kit._vertex_material(0.83,0.35)
	var bottom := top_height-0.55
	for index in service_slots.size():
		var slot: Rect2=service_slots[index]
		var center := slot.get_center()
		var tone := Color("383a31") if index==0 else Color("283d39")
		kit._box("WellBed",Vector3(center.x,bottom-0.04,center.y),Vector3(slot.size.x,0.08,slot.size.y),Color("131e1c"),kit._stone,false,0)
		for sign_value in [-1,1]:
			kit._box("WellEnd",Vector3(center.x,top_height-0.35,center.y+sign_value*(slot.size.y*0.5-0.04)),Vector3(slot.size.x,0.4,0.08),tone,kit._stone,false,0.01)
			kit._box("WellLining",Vector3(center.x+sign_value*(slot.size.x*0.5-0.04),top_height-0.35,center.y),Vector3(0.08,0.4,slot.size.y-0.16),tone,kit._stone,false,0.01)
		var lines := 2 if slot.size.x>1.5 else 1
		for line in lines:
			var x := center.x+(float(line)-(lines-1)*0.5)*0.55
			var a := Vector3(x,bottom+0.18,slot.position.y+0.08)
			var b := Vector3(x,bottom+0.18,slot.end.y-0.08)
			kit._pipe(a,b,0.14,Color("71603c") if index==0 else Color("466960"))
			for z in range(int(ceil(slot.position.y+0.4)),int(floor(slot.end.y-0.3)),2):
				kit._pipe(Vector3(x,a.y,z-0.06),Vector3(x,a.y,z+0.06),0.17,Color("202e2b"))
				kit._box("PipeSeat",Vector3(x,bottom+0.065,z),Vector3(0.42,0.13,0.18),Color("292e29"),kit._metal,false,0.015)
		# Removable grating panels sit on the well's lip, with crossbars and
		# recessed pipes visibly supported below. Nothing floats over a doorway.
		for side in [-1,1]:
			kit._box("GrateRail",Vector3(center.x+side*(slot.size.x*0.5-0.1),top_height-0.06,center.y),Vector3(0.10,0.12,slot.size.y),Color("455149"),kit._metal,false,0.015)
		var count := int(ceil(slot.size.y/0.34))
		for step in count:
			var z := slot.position.y+(step+0.5)*slot.size.y/count
			kit._box("Grating",Vector3(center.x,top_height-0.06,z),Vector3(slot.size.x-0.12,0.10,0.055),Color("48564b"),kit._metal,false,0.01)
		for step in range(int(ceil(slot.size.y/1.8))+1):
			var z := lerpf(slot.position.y+0.05,slot.end.y-0.05,float(step)/ceil(slot.size.y/1.8))
			kit._box("GrateFrame",Vector3(center.x,top_height-0.06,z),Vector3(slot.size.x,0.12,0.09),Color("596254"),kit._metal,false,0.015)
	kit._flush_batches()

func _is_open(point: Vector2) -> bool:
	for opening: Rect2 in openings:
		if opening.has_point(point): return true
	return false

func _quad(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3,color: Color) -> void:
	for tri in [[a,b,c],[a,c,d]]:
		if (tri[1]-tri[0]).cross(tri[2]-tri[0]).dot(normal)>0: tri.reverse()
		for point: Vector3 in tri:
			tool.set_normal(normal)
			tool.set_color(color)
			tool.set_uv(Vector2(point.x,point.z))
			tool.add_vertex(point)

extends RefCounted

# The dungeon's reveal needs closed volumes. A discarded part of the legacy
# crown's horizontal sheet cannot supply side faces at its new cut edges.
const FOUNDATION_TOP := 0.18
const FOUNDATION_BOTTOM := -0.75
const CAP_HEIGHT := 0.18
# Keep the permanent foundation behind the mortar core of a restored wall.
# Sharing the dressed stone's face produces depth fighting along its bottom.
const FOUNDATION_RECESS := 0.05
const STONE_COLOR := Color("252b25")
const STONE_SHADER := preload("res://shaders/keepers/cutaway_stone.gdshader")


func build(geometry: Node3D) -> void:
	var crown: Node3D = geometry.building_crown
	crown.visible = false
	var foundation := _continuous_foundation(geometry, crown.playable_openings, crown.outer_bounds)
	for section: Dictionary in geometry.cutaway.structural_sections:
		if bool(section.get("keep_full", false)):
			continue
		var a: Vector3 = section.visual_a
		var b: Vector3 = section.visual_b
		var cap := _box(section.node, "OwnedWallCap", a, b, float(section.visual_width),
			float(section.top_height) - CAP_HEIGHT, float(section.top_height), section.get("cap_color", Color("283532")))
		section["cap_mesh"] = cap
		section["shared_foundation"] = float(section.base_height) < 0.001
		section["foundation_mesh"] = foundation
		if not section.shared_foundation:
			# Continue the raised room's footing down to the common mass. A short
			# rim at the upper floor alone would float above the lower foundation.
			section["foundation_mesh"] = _box(geometry, "RaisedWallFoundation", a, b,
				float(section.visual_width) - FOUNDATION_RECESS * 2.0, FOUNDATION_TOP,
				float(section.base_height) + FOUNDATION_TOP, STONE_COLOR, FOUNDATION_RECESS * 2.0)


func _box(parent: Node3D, label: String, a: Vector3, b: Vector3, width: float,
		bottom: float, top: float, color: Color, end_inset: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = Vector3(a.distance_to(b) - end_inset, top - bottom, width)
	instance.mesh = mesh
	instance.material_override = _material(color)
	parent.add_child(instance)
	var middle := (a + b) * 0.5
	instance.global_transform = Transform3D(Basis(Vector3.UP, -atan2(b.z-a.z, b.x-a.x)),
		Vector3(middle.x, (top+bottom)*0.5, middle.z))
	return instance


func _continuous_foundation(geometry: Node3D, openings: Array[Rect2], bounds: Rect2) -> MeshInstance3D:
	var clearances: Array[Rect2] = []
	for opening: Rect2 in openings:
		clearances.append(opening.grow(FOUNDATION_RECESS))
	var xs: Array[float] = [bounds.position.x, bounds.end.x]
	var zs: Array[float] = [bounds.position.y, bounds.end.y]
	for opening: Rect2 in clearances:
		for x: float in [opening.position.x, opening.end.x]:
			var snapped := snappedf(x, 0.001)
			if not xs.has(snapped): xs.append(snapped)
		for z: float in [opening.position.y, opening.end.y]:
			var snapped := snappedf(z, 0.001)
			if not zs.has(snapped): zs.append(snapped)
	xs.sort()
	zs.sort()
	var filled: Dictionary = {}
	for x in range(xs.size()-1):
		for z in range(zs.size()-1):
			var center := Vector2((xs[x]+xs[x+1])*0.5, (zs[z]+zs[z+1])*0.5)
			var open := false
			for opening: Rect2 in clearances:
				if opening.has_point(center):
					open = true
					break
			if not open: filled[Vector2i(x,z)] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in filled:
		var a := Vector3(xs[cell.x], FOUNDATION_TOP, zs[cell.y])
		var b := Vector3(xs[cell.x+1], FOUNDATION_TOP, zs[cell.y])
		var c := Vector3(xs[cell.x+1], FOUNDATION_TOP, zs[cell.y+1])
		var d := Vector3(xs[cell.x], FOUNDATION_TOP, zs[cell.y+1])
		var down := Vector3.DOWN * (FOUNDATION_TOP-FOUNDATION_BOTTOM)
		_quad(tool,a,b,c,d,Vector3.UP)
		_quad(tool,a+down,b+down,c+down,d+down,Vector3.DOWN)
		# Only the union's boundary has sides: shared cell edges remain inside
		# one solid mass, without seams, overlapping strips or internal faces.
		for edge: Array in [[a,b,Vector3.FORWARD,Vector2i(0,-1)],
				[b,c,Vector3.RIGHT,Vector2i(1,0)], [c,d,Vector3.BACK,Vector2i(0,1)],
				[d,a,Vector3.LEFT,Vector2i(-1,0)]]:
			if not filled.has(cell+edge[3]):
				_quad(tool,edge[0],edge[0]+down,edge[1]+down,edge[1],edge[2])
	tool.index()
	var instance := MeshInstance3D.new()
	instance.name = "ContinuousCutawayFoundation"
	instance.mesh = tool.commit()
	instance.material_override = _material(STONE_COLOR)
	geometry.add_child(instance)
	return instance


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for triangle: Array in [[a,b,c],[a,c,d]]:
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).dot(normal)>0:
			triangle.reverse()
		for point: Vector3 in triangle:
			tool.set_normal(normal)
			tool.set_uv(Vector2(point.x,point.z))
			tool.add_vertex(point)


func _material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STONE_SHADER
	material.set_shader_parameter("base_color", color)
	return material

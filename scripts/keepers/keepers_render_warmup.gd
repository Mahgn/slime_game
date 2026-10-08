extends RefCounted

# Compile first-use enemy/effect material variants before control is handed to
# the player. The offscreen world has no gameplay, audio or persistent actors.
static func prepare(route: SlimeKeepersWorld) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport := SubViewport.new()
	viewport.name = "RenderPreparation"
	viewport.size = Vector2i(192,192)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	route.add_child(viewport)
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	stage.add_child(camera)
	camera.position = Vector3(6,9,12)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.95,-0.55,0)
	light.shadow_enabled = true
	stage.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0,3,0)
	fill.omni_range = 18.0
	stage.add_child(fill)
	var actors: Array[Node3D] = [route.SPITTER_SCENE.instantiate(),route.ARMORER_SCENE.instantiate(),route.SPROUT_SCENE.instantiate(),route.WORLD_GUARDIAN.new()]
	for index in actors.size():
		var actor := actors[index]
		stage.add_child(actor)
		actor.position = Vector3(float(index%2)*4-2,0,float(index/2)*4-2)
		_reveal_and_detach_groups(actor)
	var source := route.SOURCE_SCENE.instantiate()
	stage.add_child(source)
	source.position = Vector3(0,0,4)
	_reveal_and_detach_groups(source)
	var whip := SlimeWhipVisual.new()
	stage.add_child(whip)
	whip.position = Vector3(0,2,3)
	whip.set_tendril_material(route.player._whip_visual._mesh_instance.material_override)
	whip.set_phase(&"active",0.04)
	whip._impact_mesh.show()
	for droplet in whip._impact_droplets: droplet.show()
	var trail := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	trail.mesh = plane
	trail.material_override = route.player._ground_trail.material_override
	stage.add_child(trail)
	for team: StringName in [&"player", &"enemy"]:
		var projectile := SpitProjectile.new()
		projectile.team = team
		stage.add_child(projectile)
		projectile.position = Vector3(-3 if team == &"player" else 3,2,3)
		_reveal_and_detach_groups(projectile)
		if team == &"player":
			projectile._spawn_player_splash({"normal":Vector3.BACK,"collider":actors[0]})
			var splash := stage.get_child(stage.get_child_count()-1) as MeshInstance3D
			splash.mesh = SphereMesh.new()
			splash.process_mode = Node.PROCESS_MODE_DISABLED
	# Build only the visual branch of spikes; build_line would deal damage.
	var spikes := SpikeLine.new()
	spikes.configure(actors[0],&"enemy",Vector3(0,0,-4),Vector3.FORWARD,"warmup",0)
	spikes._lifetime_left = 0.0
	stage.add_child(spikes)
	spikes._add_segment(Vector3(0,0,-4),0)
	spikes._add_combo_splash(Vector3(2,0,-4))
	_reveal_and_detach_groups(spikes)
	var gel_spike := MeshInstance3D.new()
	gel_spike.mesh = spikes._make_player_ridge_mesh(Vector3.FORWARD,1.14,0.42,0.18,0.3,0.1)
	var gel_material := ShaderMaterial.new()
	gel_material.shader = SpikeLine.PLAYER_GEL_SHADER
	gel_spike.material_override = gel_material
	gel_spike.position = Vector3(-2,0,-4)
	gel_spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(gel_spike)
	# Compile the actual building's material/light combinations as well. Merely
	# loading resources or warming actors misses rooms outside the start camera.
	var building := SubViewport.new()
	building.name = "BuildingRenderPreparation"
	building.size = Vector2i(192,192)
	building.world_3d = route.get_world_3d()
	building.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	route.add_child(building)
	var overview := Camera3D.new()
	building.add_child(overview)
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = 110.0
	overview.far = 250.0
	overview.position = Vector3(60,85,45)
	overview.look_at(Vector3(-5,0,-23))
	# Both the first draw and the next draw complete before removing the world.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	building.free()
	viewport.free()

static func _reveal_and_detach_groups(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for group in node.get_groups(): node.remove_from_group(group)
	if node is Node3D: node.visible = true
	for child in node.get_children(): _reveal_and_detach_groups(child)

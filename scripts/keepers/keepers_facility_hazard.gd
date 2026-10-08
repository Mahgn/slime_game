extends Node3D

# Collision-independent damage has an explicit visual footprint and one hit
# per actor per burst. A stop valve persists; retry grants a fresh safe phase.
const SAFE := 3.2
const WARNING := 1.4
const ACTIVE := 0.65
const PERIOD := SAFE+WARNING+ACTIVE
const ART_KIT = preload("res://scripts/keepers/keepers_facility_props.gd")
var route: SlimeKeepersWorld
var spec: Dictionary
var disabled := false
var introduced := false
var demonstrated := false
var clock := 0.0
var phase := "safe"
var cycle := 0
var hits: Dictionary = {}
var damage_events := 0
var warning_material: StandardMaterial3D
var plume: Node3D
var steam_material: ShaderMaterial
var returning := false
var head: MeshInstance3D
var piston: MeshInstance3D
var valve: MeshInstance3D
var audio_player: AudioStreamPlayer3D
var warning_sound: AudioStreamWAV
var active_sound: AudioStreamWAV

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "Hazard_"+String(spec.id)
	position = spec.at
	clock = float(spec.offset)
	warning_material = StandardMaterial3D.new()
	warning_material.albedo_color = Color("886342")
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("323f3d")
	dark.metallic = 0.6
	var size: Vector2 = spec.size
	# Border strips, not a full opaque overlay, leave the floor and feet readable.
	for sign_value in [-1,1]:
		_mesh_box(Vector3(0,0.025,sign_value*size.y*0.5),Vector3(size.x+0.12,0.035,0.09),warning_material)
		_mesh_box(Vector3(sign_value*size.x*0.5,0.025,0),Vector3(0.09,0.035,size.y),warning_material)
	for i in 9:
		_mesh_box(Vector3(-size.x*0.42+i*size.x*0.105,0.015,0),Vector3(0.05,0.03,size.y*0.90),dark)
	if spec.kind == "steam":
		plume = Node3D.new()
		plume.name = "SteamJets"
		steam_material = ShaderMaterial.new()
		steam_material.shader = preload("res://shaders/keepers/steam.gdshader")
		add_child(plume)
		for i in 3:
			var jet := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(minf(size.x,size.y)*0.95,1.9)
			jet.mesh = mesh
			jet.material_override = steam_material
			jet.position = Vector3((i-1)*size.x*0.29,0.95,0) if size.x>size.y else Vector3(0,0.95,(i-1)*size.y*0.29)
			jet.rotation.y = PI/4
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plume.add_child(jet)
	else:
		head = _mesh_box(Vector3(0,2.2,0),Vector3(size.x*0.92,0.5,size.y*0.92),dark)
		head.mesh = null
		var moving_kit := ART_KIT.new()
		moving_kit.name = "MovingPressArt"
		head.add_child(moving_kit)
		moving_kit.prepare()
		moving_kit.press_dressing(size,true)
		moving_kit.finish()
		var frame_kit := ART_KIT.new()
		frame_kit.name = "FixedPressArt"
		add_child(frame_kit)
		frame_kit.prepare()
		frame_kit.press_dressing(size,false)
		frame_kit.finish()
		piston = MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.11
		rod.bottom_radius = 0.11
		rod.height = 1.0
		rod.radial_segments = 16
		piston.mesh = rod
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color("aaa991")
		steel.metallic = 0.65
		steel.roughness = 0.42
		piston.material_override = steel
		add_child(piston)
		for side in [-1,1]:
			_mesh_box(Vector3(side*(size.x*0.5+0.14),1.55,0),Vector3(0.11,3.1,0.11),dark)
	valve = MeshInstance3D.new()
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.36
	wheel.outer_radius = 0.45
	valve.mesh = wheel
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("b09965")
	brass.metallic = 0.65
	brass.roughness = 0.5
	valve.material_override = brass
	valve.rotation.x = PI/2
	valve.position = spec.valve-spec.at+Vector3.UP*0.9
	add_child(valve)
	for i in 4:
		var spoke := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(0.37,0.055,0.055)
		spoke.mesh = bar
		spoke.material_override = brass
		spoke.position = Vector3(cos(i*PI/2)*0.18,0,sin(i*PI/2)*0.18)
		spoke.rotation.y = -i*PI/2
		valve.add_child(spoke)
	_mesh_box(spec.valve-spec.at+Vector3.UP*0.45,Vector3(0.18,0.9,0.18),dark)
	audio_player = AudioStreamPlayer3D.new()
	audio_player.max_distance = 15
	audio_player.unit_size = 5
	audio_player.volume_db = -15
	audio_player.bus = SlimeGameSettings.EFFECTS_BUS
	warning_sound = _sound(spec.kind == "steam",true)
	active_sound = _sound(spec.kind == "steam",false)
	audio_player.stream = active_sound
	add_child(audio_player)
	_refresh_visual()

func _physics_process(delta: float) -> void:
	if disabled or route.finished or route._transitioning:
		return
	if not introduced:
		if not route.visited.has(String(spec.room)) or route.player.global_position.distance_to(global_position)>8:
			return
		introduced = true
		clock = 0
	clock += delta
	if clock >= PERIOD:
		clock = fmod(clock,PERIOD)
		cycle += 1
		hits.clear()
	var next := "safe" if clock<SAFE else ("warning" if clock<SAFE+WARNING else "active")
	if next != phase:
		returning = phase == "active" and next == "safe"
		phase = next
		if phase == "warning":
			_play_cue(true)
		if phase == "active":
			demonstrated = true
			_play_cue()
	_refresh_visual()
	if phase != "active":
		return
	var actors: Array = [route.player]
	for id: String in route.room_roots:
		actors.append_array(route.alive_enemies(id))
	for actor: Node3D in actors:
		if not actor.is_alive() or hits.has(actor.get_instance_id()):
			continue
		var at := actor.global_position-global_position
		var radius := 0.24 if actor == route.player else 0.4
		if absf(at.x)>float(spec.size.x)*0.5+radius or absf(at.z)>float(spec.size.y)*0.5+radius or at.y < -0.3 or at.y > (1.7 if spec.kind == "steam" else 0.75):
			continue
		# Nearby actors cannot be hit through a wall or a machine.
		var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*0.35,actor.global_position+Vector3.UP*0.35,1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		hits[actor.get_instance_id()] = true
		var amount := 10 if spec.kind == "steam" else 14
		if actor == route.player:
			actor.apply_environment_damage(amount)
		else:
			actor.receive_environment_hit(amount,"%s:%s:%d" % [spec.id,get_instance_id(),cycle])
		damage_events += 1

func _refresh_visual() -> void:
	warning_material.albedo_color = Color("548976") if disabled else (Color("e8b465") if phase == "warning" else (Color("ff7443") if phase == "active" else Color("795f43")))
	if not disabled and phase == "warning":
		warning_material.albedo_color *= 0.82+0.18*cos((clock-SAFE)*TAU*3)
	if is_instance_valid(plume):
		plume.visible = not disabled and phase != "safe"
		plume.scale.y = 1.0 if phase == "active" else 0.20
		steam_material.set_shader_parameter("steam_time",clock)
		steam_material.set_shader_parameter("strength",0.65 if phase == "active" else 0.30)
	if is_instance_valid(head):
		head.position.y = _press_height()
		piston.position.y = (2.85+head.position.y+0.45)*0.5
		piston.scale.y = 2.85-head.position.y-0.45

func _press_height() -> float:
	if disabled:
		return 2.2
	if phase == "active":
		return 0.3
	if phase == "warning":
		var progress := clock-SAFE
		if progress<WARNING-0.16:
			return lerpf(2.2,2.33,smoothstep(0.0,0.3,progress))
		# The visible fall ends exactly when the damage window starts.
		var fall := clampf((progress-(WARNING-0.16))/0.16,0,1)
		return lerpf(2.33,0.3,fall*fall)
	if returning:
		return lerpf(0.3,2.2,smoothstep(0.0,0.55,clock))
	return 2.2

func disable() -> void:
	disabled = true
	audio_player.stop()
	valve.rotation.z += PI/2
	_refresh_visual()

func _play_cue(warning: bool = false) -> void:
	audio_player.stream = warning_sound if warning else active_sound
	audio_player.volume_db = -23 if warning else -15
	# Match the settings/ambience policy: the headless fixture has no playback
	# device. Actual audio is exercised with the native renderer/driver.
	if DisplayServer.get_name() != "headless":
		audio_player.play()

func _exit_tree() -> void:
	if is_instance_valid(audio_player):
		audio_player.stop()
		audio_player.stream = null
	warning_sound = null
	active_sound = null

func reset_cycle() -> void:
	clock = 0
	cycle += 1
	hits.clear()
	phase = "safe"
	returning = false
	audio_player.stop()
	_refresh_visual()

func _mesh_box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _sound(steam: bool, warning: bool) -> AudioStreamWAV:
	# Original synthesized cue, no third-party recording or network dependency.
	var data := PackedByteArray()
	var samples := 26460 if warning else 11025
	data.resize(samples*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 48271
	for i in samples:
		var t := float(i)/22050.0
		var noise := rng.randf_range(-1,1)
		var value := noise*exp(-t*5) if steam else (sin(t*TAU*127)+sin(t*TAU*311)*0.4+noise*0.2)*exp(-t*12)
		if warning:
			if steam:
				value = noise*smoothstep(0.0,0.2,t)*(0.16+0.30*t)*(1.0-smoothstep(1.05,1.2,t))
			else:
				var tick := fmod(t,0.4)
				value = (sin(tick*TAU*613)+noise*0.3)*exp(-tick*65)*(0.35+t*0.25)
		data.encode_s16(i*2,int(clampf(value*0.32,-1,1)*32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.data = data
	return sound

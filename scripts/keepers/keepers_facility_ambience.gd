extends Node3D

# Local sources belong to this level. The listener follows the hero, while
# its orientation follows the fixed camera so stereo agrees with the image.
var route: SlimeKeepersWorld
var listener: AudioListener3D
var sources: Array[Dictionary] = []
var mix_time := 0.0
var duck_gain := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	listener = AudioListener3D.new()
	listener.name = "HeroListener"
	add_child(listener)
	_sync_listener()
	listener.make_current()
	var streams := {"fire":_loop("fire"),"water":_loop("water"),"motor":_loop("motor")}
	for spec: Dictionary in [
		{"room":"furnace","kind":"fire","at":Vector3(-17.2,1,-8.0)},
		{"room":"cistern","kind":"water","at":Vector3(11,0,-3)},
		{"room":"pump_room","kind":"motor","at":Vector3(11,1,-22)},
		{"room":"hub","kind":"motor","at":Vector3(-10.7,1,-24)},
		{"room":"garden","kind":"water","at":Vector3(10,0,-38)}
	]:
		var player := AudioStreamPlayer3D.new()
		player.name = "Bed_"+String(spec.room)
		player.position = spec.at
		player.bus = SlimeGameSettings.AMBIENCE_BUS
		player.max_distance = 20
		player.unit_size = 8
		player.volume_db = -60
		player.stream = streams[spec.kind]
		add_child(player)
		sources.append({"player":player,"room":spec.room,"gain":0.0})
		if DisplayServer.get_name() != "headless":
			player.play()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(route.player):
		return
	_sync_listener()
	if route.finished:
		for source: Dictionary in sources:
			source.player.stop()
		return
	mix_time += delta
	var threatened := not route.alive_enemies().is_empty()
	for hazard in route.get("hazards"):
		if not hazard.disabled and hazard.phase != "safe" and hazard.global_position.distance_to(route.player.global_position)<10:
			threatened = true
	duck_gain = lerpf(duck_gain,0.35 if threatened else 1.0,1.0-exp(-delta*5.0))
	for source: Dictionary in sources:
		var room: Dictionary = route.rooms[source.room]
		var offset: Vector3 = route.player.global_position-room.center
		var outside := Vector2(maxf(0,absf(offset.x)-room.half.x),maxf(0,absf(offset.z)-room.half.y)).length()
		var target := (1.0-smoothstep(0.0,4.0,outside))*duck_gain
		# A fixed spatial blend covers the doorway on either side. Room entry
		# notifications never restart the loop or switch its volume abruptly.
		source.gain = lerpf(float(source.gain),target,1.0-exp(-delta*3.0))
		source.player.volume_db = -25.0+linear_to_db(maxf(0.001,float(source.gain)))

func _sync_listener() -> void:
	listener.global_transform = Transform3D(route.player.presentation.camera.global_basis,route.player.global_position+Vector3.UP*0.6)

func _exit_tree() -> void:
	if is_instance_valid(listener):
		listener.clear_current()
	for source: Dictionary in sources:
		if is_instance_valid(source.player):
			source.player.stop()
			source.player.stream = null
	sources.clear()

func _loop(kind: String) -> AudioStreamWAV:
	# Original 2-second periodic synthesis, no recording or imported sample.
	# Integer frequencies and a wrapped noise seam keep every loop continuous.
	const RATE := 22050
	const COUNT := RATE*2
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182 if kind == "fire" else (3371 if kind == "water" else 701)
	var values := PackedFloat32Array()
	values.resize(COUNT)
	var filtered := 0.0
	for i in COUNT:
		var t := float(i)/RATE
		filtered = lerpf(filtered,rng.randf_range(-1,1),0.11 if kind=="fire" else 0.045)
		var sample := filtered*0.45
		if kind == "fire":
			sample += sin(t*TAU*63.0)*0.09*(0.7+0.3*sin(t*TAU*2.0))
		elif kind == "water":
			sample += sin(t*TAU*431.0+sin(t*TAU*3.0))*0.07*pow(maxf(0,sin(t*TAU*4.0)),14)
		else:
			sample = (sin(t*TAU*54.0)*0.22+sin(t*TAU*108.0)*0.07)*(0.8+0.2*cos(t*TAU*3.0))+filtered*0.1
		values[i] = sample
	var data := PackedByteArray()
	data.resize(COUNT*2)
	for i in COUNT:
		var seam := smoothstep(float(COUNT-660),float(COUNT-1),float(i))
		data.encode_s16(i*2,int(clampf(lerpf(values[i],values[0],seam),-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = COUNT
	return stream

extends SlimeKeepersWorld

const HAZARD = preload("res://scripts/keepers/keepers_facility_hazard.gd")
const AMBIENCE = preload("res://scripts/keepers/keepers_facility_ambience.gd")
var hazards: Array[Node3D] = []
var ambience: Node3D
var introduced_encounters: Dictionary = {}

func encounter_focus(id: String) -> Vector3:
	return {"furnace":Vector3(-9,0,-9),"pump_room":Vector3(8,0,-25)}.get(id,rooms[id].spawn)

func _update_encounter(id: String, delta: float, inside: bool) -> void:
	# The first mechanism is visible from an empty approach. Crossing the
	# working area introduces combat; waiting at the door never spawns a wave.
	if id in ["furnace","pump_room"] and not introduced_encounters.has(id):
		if hazards.size()<2:
			return
		var lesson = hazards[0] if id == "furnace" else hazards[1]
		if not lesson.demonstrated and not lesson.disabled:
			return
		if not inside or player.global_position.distance_to(encounter_focus(id))>4.2:
			return
		introduced_encounters[id] = true
	super._update_encounter(id,delta,inside)

func _ready() -> void:
	await super._ready()
	for spec: Dictionary in [
		{"id":"firebox_relief","room":"furnace","kind":"steam","at":Vector3(-7,0,-4),"size":Vector2(1.5,3.4),"valve":Vector3(-15,0,-0.4),"offset":0.0},
		{"id":"pump_drive","room":"pump_room","kind":"press","at":Vector3(7,0,-20),"size":Vector2(2.5,2.1),"valve":Vector3(16.5,0,-25.4),"offset":1.8},
		{"id":"boiler_relief","room":"hub","kind":"steam","at":Vector3(-4,0,-29),"size":Vector2(3.0,1.6),"valve":Vector3(-18.4,0,-26.5),"offset":2.4},
		{"id":"gate_drive","room":"summit","kind":"press","at":Vector3(4,0,-55),"size":Vector2(2.4,2.4),"valve":Vector3(9,0,-56.5),"offset":0.7},
	]:
		var hazard := HAZARD.new()
		hazard.route = self
		hazard.spec = spec
		add_child(hazard)
		hazards.append(hazard)
	ambience = AMBIENCE.new()
	ambience.name = "FacilitySoundscape"
	ambience.route = self
	add_child(ambience)

func _update_visibility() -> void:
	# A compact building keeps its structural silhouette across room boundaries.
	for shell: Node3D in geometry.room_nodes.values():
		shell.visible = true

func _update_interaction() -> void:
	super._update_interaction()
	if is_instance_valid(player.get_nearest_absorb_source()):
		return
	for hazard in hazards:
		if not hazard.disabled and _near(hazard.spec.valve,1.5):
			interaction_hint = "E — перекрыть подачу пара" if hazard.spec.kind == "steam" else "E — остановить привод"

func try_interact() -> bool:
	if finished or _transitioning or get_tree().paused or not player.is_alive():
		return false
	if is_instance_valid(player.get_nearest_absorb_source()):
		return false
	for hazard in hazards:
		if not hazard.disabled and _near(hazard.spec.valve,1.5):
			hazard.disable()
			hud.show_notice("Механизм остановлен. Обратный путь останется безопасным.")
			return true
	return super.try_interact()

func _retry_room_deferred() -> void:
	super._retry_room_deferred()
	for hazard in hazards:
		if hazard.spec.room == room_id:
			hazard.reset_cycle()

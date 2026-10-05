extends Node3D
class_name AbsorbSource

signal claimed(source: AbsorbSource, claimed_ability_id: StringName)

@export var ability_id: StringName = &"sticky_spit"

@onready var visual_root: Node3D = $VisualRoot
@onready var focus_glow: MeshInstance3D = $VisualRoot/FocusGlow

var _claimed := false
var _focused := false
var _elapsed := 0.0
var _motes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"absorb_sources")
	focus_glow.visible = false
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.065
	mote_mesh.height = 0.13
	var mote_material := StandardMaterial3D.new()
	mote_material.albedo_color = Color(0.41, 0.96, 0.82)
	mote_material.emission_enabled = true
	mote_material.emission = Color(0.13, 0.78, 0.58)
	mote_material.emission_energy_multiplier = 1.4
	for index in 3:
		var mote := MeshInstance3D.new()
		mote.name = "OrbitMote%d" % index
		mote.mesh = mote_mesh
		mote.material_override = mote_material
		visual_root.add_child(mote)
		_motes.append(mote)


func _process(delta: float) -> void:
	_elapsed += delta
	visual_root.position.y = 1.12 + sin(_elapsed * 2.4) * 0.08
	visual_root.rotation.y += delta * 0.9
	focus_glow.visible = _focused and not _claimed
	for index in _motes.size():
		var angle := _elapsed * (2.6 if _focused else 1.4) + TAU * float(index) / 3.0
		var radius := 0.39 if _focused else 0.49
		_motes[index].position = Vector3(cos(angle) * radius, sin(angle * 1.7) * 0.17, sin(angle) * radius)


func set_focused(value: bool) -> void:
	_focused = value and not _claimed
	focus_glow.visible = _focused


func claim() -> bool:
	if _claimed or ability_id == &"":
		return false
	_claimed = true
	_focused = false
	remove_from_group(&"absorb_sources")
	visible = false
	set_process(false)
	claimed.emit(self, ability_id)
	return true


func is_claimed() -> bool:
	return _claimed

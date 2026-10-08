extends Node
class_name SlimeRoomCutaway

const SOLID_SHADER := preload("res://shaders/isometric/solid_cutaway.gdshader")
const FADE_SECONDS := 0.22
const LOWER_ENTER_Y := -0.20
const UPPER_RETURN_Y := 0.18

var sections: Dictionary = {}
var materials: Array[ShaderMaterial] = []
var enabled := true
var lower_route := false
var _bodies: Dictionary = {}


func register_section(id: StringName, meshes: Array[MeshInstance3D], floor_y: float, decorations: Array[Node3D] = []) -> void:
	assert(not sections.has(id), "Duplicate architectural section")
	var copies: Dictionary = {}
	var section_materials: Array[ShaderMaterial] = []
	for mesh in meshes:
		var source := mesh.material_override
		assert(source != null, "Section needs explicit surface materials")
		var key := source.get_instance_id()
		if not copies.has(key):
			var copy: ShaderMaterial
			if source is ShaderMaterial:
				copy = source.duplicate() as ShaderMaterial
			else:
				assert(source is StandardMaterial3D, "Unsupported section material")
				var solid := source as StandardMaterial3D
				copy = ShaderMaterial.new()
				copy.shader = SOLID_SHADER
				copy.set_shader_parameter("base_color", solid.albedo_color)
				copy.set_shader_parameter("roughness", solid.roughness)
				copy.set_shader_parameter("emission_color", solid.emission * solid.emission_energy_multiplier if solid.emission_enabled else Color.BLACK)
			copies[key] = copy
			section_materials.append(copy)
			materials.append(copy)
		mesh.material_override = copies[key]
		var ancestor := mesh.get_parent()
		while ancestor != null:
			if ancestor is CollisionObject3D:
				_bodies[ancestor.get_rid()] = id
				break
			ancestor = ancestor.get_parent()
	var light_energies: Dictionary = {}
	for decoration in decorations:
		if decoration is Light3D:
			light_energies[decoration] = decoration.light_energy
	sections[id] = {"meshes": meshes, "materials": section_materials,
		"decorations": decorations, "light_energies": light_energies,
		"floor_y": floor_y, "amount": 0.0}


func update_view(player: SlimeController, _camera: Camera3D, delta: float = 0.0) -> void:
	if sections.is_empty():
		lower_route = false
		return
	# An airborne jump from the lower path does not switch architectural floors.
	# Restore on the return ramp, before reaching A's landing.
	if player.global_position.y < LOWER_ENTER_Y:
		lower_route = true
	elif lower_route and player.is_on_floor() and player.global_position.y > UPPER_RETURN_Y:
		lower_route = false
	var target := 1.0 if enabled and lower_route else 0.0
	for id in sections:
		var section: Dictionary = sections[id]
		var amount := move_toward(float(section.amount), target, maxf(delta, 0.0) / FADE_SECONDS)
		_apply_amount(section, amount)


func _apply_amount(section: Dictionary, amount: float) -> void:
	section.amount = amount
	for material: ShaderMaterial in section.materials:
		material.set_shader_parameter("cutaway_amount", amount)
	for decoration: Node3D in section.decorations:
		if decoration is Light3D:
			decoration.light_energy = float(section.light_energies[decoration]) * (1.0 - amount)
		else:
			decoration.visible = amount < 1.0


func is_point_cut(collider: CollisionObject3D, _point: Vector3) -> bool:
	# Only an explicitly faded section can be passed by the camera aim ray.
	# A silhouette never makes a solid wall targetable through.
	return enabled and _bodies.has(collider.get_rid()) and float(sections[_bodies[collider.get_rid()]].amount) >= 0.5


func get_reveal_amount() -> float:
	# The current gallery's three sections share one occupied-floor state.
	for section: Dictionary in sections.values():
		return float(section.amount)
	return 0.0


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		for section: Dictionary in sections.values():
			_apply_amount(section, 0.0)

extends "res://scripts/dungeon/dungeon_geometry.gd"

const COMBAT_REVEAL = preload("res://scripts/visibility_combat/combat_reveal.gd")

func _configure_view_window(_rooms: Dictionary, _connections: Array) -> void:
	# Only this inherited comparison scene replaces the previous local window.
	pass

func build_world(rooms: Dictionary, connections: Array) -> void:
	super.build_world(rooms, connections)
	var authored: Array[Dictionary] = cutaway.structural_sections
	cutaway.free()
	cutaway = COMBAT_REVEAL.new()
	cutaway.name = "CombatArchitectureReveal"
	add_child(cutaway)
	cutaway.structural_sections = authored
	cutaway.configure_building(rooms, connections)
	WALL_ARCHITECTURE.new().build(self)
	# Identify authored masonry before fade/Ink replace the source materials.
	for section: Dictionary in cutaway.structural_sections:
		for mesh: MeshInstance3D in section.node.find_children("*", "MeshInstance3D", true, false):
			var material := mesh.material_override as ShaderMaterial
			if material != null and material.shader != null and material.shader.resource_path == "res://shaders/keepers/facility_stone.gdshader":
				mesh.set_meta(&"comparison_masonry", true)
	wall_fade_renderer = WALL_FADE_RENDERER.new()
	wall_fade_renderer.configure(self, rooms, connections)
	cutaway.setup(self, rooms, connections)

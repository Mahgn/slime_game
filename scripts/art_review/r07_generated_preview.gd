extends "res://scripts/r07_guardian.gd"

const GUARDIAN_ART := preload("res://assets/art/r07_review/guardian_cutout_candidate_v1.png")
const SLATE_ART := preload("res://assets/art/r07_review/slate_albedo_candidate_v1.png")


func _ready() -> void:
	super._ready()
	if not is_instance_valid(guardian):
		return
	var old_visual := guardian.get_node_or_null("VisualRoot")
	if old_visual:
		old_visual.hide()
	var portrait := Sprite3D.new()
	portrait.name = "GeneratedGuardianCandidate"
	portrait.texture = GUARDIAN_ART
	portrait.pixel_size = 0.002
	portrait.position.y = 1.32
	portrait.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	portrait.shaded = true
	portrait.double_sided = true
	guardian.add_child(portrait)
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = SLATE_ART
	stone.albedo_color = Color(0.98, 0.98, 1.0)
	stone.roughness = 0.9
	stone.vertex_color_use_as_albedo = true
	for label in ["FloorSlabsDark", "FloorSlabsMid", "FloorSlabsLight", "BackWallCourses", "SideWallCourses"]:
		var surface := get_node_or_null(label) as MultiMeshInstance3D
		if surface:
			surface.material_override = stone

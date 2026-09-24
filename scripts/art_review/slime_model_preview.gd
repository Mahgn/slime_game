extends "res://scripts/main.gd"

const SLIME_MODEL := preload("res://assets/models/slime_hero_v1.res")

var _model_instance: MeshInstance3D


func _ready() -> void:
	super._ready()
	for part in player.visual_root.get_children():
		if part is MeshInstance3D:
			part.hide()
	_model_instance = MeshInstance3D.new()
	_model_instance.name = "SlimeHeroModel"
	_model_instance.mesh = SLIME_MODEL
	player.visual_root.add_child(_model_instance)

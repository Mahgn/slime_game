extends "res://scripts/s4_trial.gd"


func _ready() -> void:
	super._ready()
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.get_parent() == self:
			enemy.queue_free()
	stage = &"ability_preview"
	player.grant_ability(&"slime_spikes")
	player.unlock_second_slot()
	player.equip_ability(1, &"sticky_spit")
	player.equip_ability(2, &"slime_spikes")
	_card_left = 0.0
	_card_panel.visible = false
	var target := StaticBody3D.new()
	target.set_script(TRAINING_TARGET_SCRIPT)
	target.name = "TrainingTarget"
	target.position = Vector3(0.0, 0.0, 0.6)
	target.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(target)
	_show_info("ПКМ — слизевой плевок · Q — шипы · атакуй мишень")


func _physics_process(_delta: float) -> void:
	# Keep the target available for repeated VFX review without trial progression.
	pass

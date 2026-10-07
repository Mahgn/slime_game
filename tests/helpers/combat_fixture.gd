extends Node3D

# Test-only physics fixture. No campaign layout or gameplay entry point.
const PLAYER = preload("res://scenes/player/slime_player.tscn")
const SPITTER = preload("res://scenes/enemies/spitter.tscn")
const COMBAT = preload("res://scripts/combat/combat_runtime.gd")

var player: SlimeController
var combat: SlimeCombatRuntime
var _pause_panel: SlimePauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	preload("res://scripts/input_setup.gd").install()
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.4, 40)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	player = PLAYER.instantiate() as SlimeController
	player.name = "SlimePlayer"
	player.position = Vector3(0, 0.05, 0)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	combat = COMBAT.new()
	add_child(combat)
	combat.bind_player(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_pause_panel = SlimePauseMenu.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_pause_panel.resume_requested.connect(_resume_game)
	canvas.add_child(_pause_panel)


func spawn_spitter(at: Vector3) -> Spitter:
	var enemy := SPITTER.instantiate() as Spitter
	enemy.position = at
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	combat.bind_enemy(enemy)
	return enemy


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if get_tree().paused:
			if not _pause_panel.dismiss_submenu():
				_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(player):
		_pause_game()


func _pause_game() -> void:
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	_pause_panel.reset_submenus()
	_pause_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_game() -> void:
	_pause_panel.visible = false
	player.clear_action_buffer()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

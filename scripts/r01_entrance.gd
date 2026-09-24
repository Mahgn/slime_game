extends Node3D

const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const R02_SCENE := "res://scenes/main.tscn"
const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")

@onready var player: SlimeController = $SlimePlayer

var _transitioning := false
var _save_retry_left := 0.0
var _pause_panel: ColorRect
var _hint: Label


func _enter_tree() -> void:
	INPUT_SETUP.install()


func _ready() -> void:
	get_tree().paused = false
	_build_room()
	_build_light()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and not (event is InputEventKey and event.echo):
		get_tree().paused = not get_tree().paused
		_pause_panel.visible = get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not get_tree().paused:
		get_tree().paused = true
		_pause_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_save_retry_left = maxf(0.0, _save_retry_left - delta)
	if _transitioning or get_tree().paused:
		return
	if player.global_position.y < -3.0:
		player.global_position = Vector3(0.0, 0.05, 3.6)
		player.velocity = Vector3.ZERO
	if _save_retry_left <= 0.0 and player.global_position.z < -4.7 and player.global_position.y > 1.0:
		_transitioning = true
		call_deferred("_enter_r02")


func _enter_r02() -> void:
	if get_tree().get_meta(&"checkpoint_active", false):
		var store: CheckpointStore = STORE_SCRIPT.new()
		var written := store.write_checkpoint(store.snapshot_for_room("R02", player))
		if not written["ok"]:
			_transitioning = false
			_save_retry_left = 3.0
			_hint.text = "Не удалось сохранить вход в R02: %s" % written["error"]
			return
	get_tree().paused = false
	var result := get_tree().change_scene_to_file(R02_SCENE)
	if result != OK:
		_transitioning = false
		push_error("R01: переход в R02 не удался: %d" % result)


func _build_room() -> void:
	var floor_color := Color(0.23, 0.29, 0.34)
	var wall_color := Color(0.31, 0.37, 0.39)
	var ledge_color := Color(0.42, 0.47, 0.46)
	_add_block("Floor", Vector3(0, -0.2, 1.2), Vector3(10, 0.4, 14.4), floor_color)
	_add_block("WestWall", Vector3(-5.2, 1.8, 1.2), Vector3(0.4, 3.6, 14.8), wall_color)
	_add_block("EastWall", Vector3(5.2, 1.8, 1.2), Vector3(0.4, 3.6, 14.8), wall_color)
	_add_block("SouthWall", Vector3(0, 1.8, 8.6), Vector3(10.4, 3.6, 0.4), wall_color)
	_add_block("NorthWall", Vector3(0, 1.8, -6.2), Vector3(10.4, 3.6, 0.4), wall_color)
	_add_block("AscentRamp", Vector3(0, 0.51, -0.2), Vector3(3.6, 0.24, 4.2), ledge_color, 18.0)
	_add_block("UpperLedge", Vector3(0, 1.13, -4.0), Vector3(4.3, 0.3, 3.8), ledge_color)
	_add_block("RubbleWest", Vector3(-3.8, 0.37, 1.5), Vector3(1.7, 0.74, 1.4), wall_color, 0.0)
	_add_block("RubbleEast", Vector3(3.6, 0.28, -0.4), Vector3(1.8, 0.56, 1.6), wall_color, 0.0)
	_add_block("StepWest", Vector3(-2.8, 0.24, -0.9), Vector3(1.0, 0.48, 1.0), ledge_color)
	_add_block("StepEast", Vector3(2.8, 0.42, -2.2), Vector3(1.2, 0.84, 1.2), ledge_color)
	_add_block("RouteLine", Vector3(0, 0.018, 3.0), Vector3(1.6, 0.035, 0.12), Color(0.83, 0.71, 0.40), 0.0, false, true)
	_add_block("ExitLine", Vector3(0, 1.30, -5.1), Vector3(3.4, 0.035, 0.18), Color(1.0, 0.81, 0.43), 0.0, false, true)
	# A repeated high light above the exit marks the direction of ascent.
	_add_block("LightShaft", Vector3(0, 3.02, -5.94), Vector3(3.0, 0.85, 0.08), Color(1.0, 0.83, 0.52), 0.0, false, true)
	_add_block("LightFrameTop", Vector3(0, 3.50, -5.85), Vector3(3.6, 0.12, 0.2), wall_color, 0.0, false)
	_add_block("LightFrameLeft", Vector3(-1.56, 2.99, -5.85), Vector3(0.12, 1.1, 0.2), wall_color, 0.0, false)
	_add_block("LightFrameRight", Vector3(1.56, 2.99, -5.85), Vector3(0.12, 1.1, 0.2), wall_color, 0.0, false)


func _add_block(block_name: String, center: Vector3, size: Vector3, tint: Color, angle_x: float = 0.0, solid: bool = true, glowing: bool = false) -> void:
	var block: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		block = body
	else:
		block = Node3D.new()
	block.name = block_name
	block.position = center
	block.rotation_degrees.x = angle_x
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.86
	if glowing:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 1.1
	mesh.material_override = material
	block.add_child(mesh)
	add_child(block)


func _build_light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.09, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.50, 0.57, 0.60)
	environment.ambient_light_energy = 0.62
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color(0.92, 0.91, 0.83)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0, 3.0, -5.4)
	beacon.light_color = Color(1.0, 0.77, 0.48)
	beacon.light_energy = 1.5
	beacon.omni_range = 9.0
	add_child(beacon)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_hint = Label.new()
	_hint.text = "ВХОД · R01\nПоднимись к свету. WASD — идти, Пробел — прыгать"
	_hint.position = Vector2(24, 20)
	_hint.add_theme_font_size_override("font_size", 25)
	_hint.add_theme_color_override("font_color", Color(0.97, 0.96, 0.88))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)
	var marker := Label.new()
	marker.text = "+"
	marker.anchor_left = 0.5
	marker.anchor_right = 0.5
	marker.anchor_top = 0.5
	marker.anchor_bottom = 0.5
	marker.offset_left = -7
	marker.offset_top = -14
	marker.add_theme_font_size_override("font_size", 25)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(marker)
	_pause_panel = ColorRect.new()
	_pause_panel.color = Color(0.02, 0.04, 0.07, 0.82)
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_pause_panel)
	var pause_text := Label.new()
	pause_text.text = "ПАУЗА\nEscape — продолжить"
	pause_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_text.add_theme_font_size_override("font_size", 30)
	pause_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_panel.add_child(pause_text)

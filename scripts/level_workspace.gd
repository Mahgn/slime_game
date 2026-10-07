extends Node3D
class_name SlimeLevelWorkspace

# Empty starting surface while the new route is built. No saved progression.
const SPAWN := Vector3(0, 0.05, 0)
const INPUT_SETUP = preload("res://scripts/input_setup.gd")

@onready var player: SlimeIsometricController = $SlimePlayer

var combat: SlimeCombatRuntime
var _pause_panel: SlimePauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	INPUT_SETUP.install()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.presentation.zoom_target = 10.0
	player.camera.size = 10.0
	combat = SlimeCombatRuntime.new()
	combat.name = "CombatRuntime"
	add_child(combat)
	combat.bind_player(player)
	_build_floor_grid()
	_build_ui()


func _physics_process(_delta: float) -> void:
	if not get_tree().paused and player.global_position.y < -4.0:
		player.global_position = SPAWN
		player.velocity = Vector3.ZERO
		player.clear_action_buffer()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if get_tree().paused:
			if not _pause_panel.dismiss_submenu():
				_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_pause_panel):
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


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var title := Label.new()
	title.text = "Слайм: путь наверх"
	title.position = Vector2(24, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(title)
	var controls := Label.new()
	controls.text = "WASD — движение · Мышь — прицел · ЛКМ — хлыст · Пробел: удержать и отпустить — прыжок · Esc — пауза"
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.anchor_right = 1.0
	controls.offset_left = 24
	controls.offset_top = -48
	controls.offset_right = -24
	controls.offset_bottom = -20
	controls.add_theme_font_size_override("font_size", 19)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(controls)
	_pause_panel = SlimePauseMenu.new()
	_pause_panel.name = "PauseMenu"
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_pause_panel.resume_requested.connect(_resume_game)
	canvas.add_child(_pause_panel)


func _build_floor_grid() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.36, 0.38)
	material.roughness = 1.0
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index in range(-3, 4):
		var offset := float(index) * 2.0
		var low := clampf(offset - 0.012, -6.0, 6.0)
		var high := clampf(offset + 0.012, -6.0, 6.0)
		_grid_quad(mesh, Vector3(low, 0.012, -6), Vector3(low, 0.012, 6), Vector3(high, 0.012, 6), Vector3(high, 0.012, -6))
		_grid_quad(mesh, Vector3(-6, 0.012, low), Vector3(-6, 0.012, high), Vector3(6, 0.012, high), Vector3(6, 0.012, low))
	mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "FloorGrid"
	grid.mesh = mesh
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)


func _grid_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot uses clockwise front faces; the grid must face up from the floor.
	for vertex in [a, c, b, a, d, c]:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_add_vertex(vertex)

extends Node3D

const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")
const SPITTER_SCENE = preload("res://scenes/enemies/spitter.tscn")
const SOURCE_SCENE = preload("res://scenes/interactables/absorb_source.tscn")
const PROJECTILE_SCENE = preload("res://scenes/abilities/spit_projectile.tscn")
const HIT_SOUND = preload("res://assets/audio/hit.wav")
const ABSORB_SOUND = preload("res://assets/audio/absorb.wav")
const CAST_SOUND = preload("res://assets/audio/cast.wav")
const WHIP_SOUND = preload("res://assets/audio/whip.wav")
const PLAYER_SPIT_SOUND = preload("res://assets/audio/player_spit.wav")
const ENEMY_CHARGE_SOUND = preload("res://assets/audio/enemy_charge.wav")
const ENEMY_SPIT_SOUND = preload("res://assets/audio/enemy_spit.wav")

@onready var player: SlimeController = $SlimePlayer

var _pause_overlay: CanvasLayer
var first_enemy: Spitter
var second_enemy: Spitter
var first_source: AbsorbSource
var stage: StringName = &"first_fight"
var _entered_second_zone := false
var _card_left := 0.0
var _info_left := 0.0
var _info_text := ""
var _hud_layer: CanvasLayer
var _health_label: Label
var _health_bar: ProgressBar
var _slot_label: Label
var _hint_label: Label
var _card_label: Label
var _card_back: ColorRect
var _absorb_progress: ProgressBar
var _end_overlay: ColorRect
var _end_title: Label
var _next_button: Button
var _hit_audio: AudioStreamPlayer3D
var _absorb_audio: AudioStreamPlayer3D
var _cast_audio: AudioStreamPlayer3D
var _whip_audio: AudioStreamPlayer3D
var _player_spit_audio: AudioStreamPlayer3D
var _enemy_charge_audio: AudioStreamPlayer3D
var _enemy_spit_audio: AudioStreamPlayer3D


func _enter_tree() -> void:
	INPUT_SETUP.install()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_create_pause_overlay()
	_create_hud()
	_create_audio()
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	player.ability_unlocked.connect(_on_ability_unlocked)
	player.absorb_progress_changed.connect(_on_absorb_progress)
	player.projectile_requested.connect(_on_player_projectile)
	player.whip_hit.connect(_on_whip_hit)
	player.action_started.connect(_on_action_started)
	player.info_requested.connect(_show_info)
	_spawn_first_enemy()
	_on_health_changed(player.health, player.MAX_HEALTH)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if stage == &"dead" or stage == &"complete":
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
			get_viewport().set_input_as_handled()
			_restart()
		return
	if event.is_action_pressed(&"pause") and not (event is InputEventKey and event.echo):
		if get_tree().paused:
			_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not get_tree().paused and stage != &"dead" and stage != &"complete":
		_pause_game()


func _pause_game() -> void:
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(_pause_overlay):
		_pause_overlay.visible = true


func _resume_game() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_pause_overlay):
		_pause_overlay.visible = false


func _create_pause_overlay() -> void:
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.07, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(shade)
	var message := Label.new()
	message.text = "ПАУЗА\nEscape — продолжить"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.add_theme_font_size_override("font_size", 28)
	shade.add_child(message)
	add_child(_pause_overlay)


func _physics_process(_delta: float) -> void:
	if get_tree().paused or stage == &"dead" or stage == &"complete":
		return
	if player.global_position.z <= -2.8:
		_entered_second_zone = true
	if is_instance_valid(first_source):
		first_source.set_focused(player.get_nearest_absorb_source() == first_source)
	_spawn_second_if_ready()
	if stage == &"clear_pending" and get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty() and get_tree().get_nodes_in_group(&"enemy_attacks").is_empty():
		_complete_run()


func _process(delta: float) -> void:
	if get_tree().paused or stage == &"dead" or stage == &"complete":
		return
	_card_left = maxf(0.0, _card_left - delta)
	_info_left = maxf(0.0, _info_left - delta)
	_card_back.visible = _card_left > 0.0
	if player.equipped_ability == &"":
		_slot_label.text = "ПКМ · ПУСТО"
	elif player.cooldown_remaining(&"sticky_spit") > 0.05:
		_slot_label.text = "ПКМ · ЛИПКИЙ ПЛЕВОК  %.1f с" % player.cooldown_remaining(&"sticky_spit")
	else:
		_slot_label.text = "ПКМ · ЛИПКИЙ ПЛЕВОК  ГОТОВ"
	if _info_left > 0.0:
		_hint_label.text = _info_text
	elif stage == &"first_fight":
		_hint_label.text = "ЛКМ — хлыст · уклоняйся от плевка"
	elif stage == &"absorb":
		_hint_label.text = "Подойди к сияющему остатку и удерживай E"
	elif stage == &"approach":
		_hint_label.text = "Иди к золотой отметке впереди"
	elif stage == &"clear_pending":
		_hint_label.text = "Уклоняйся от оставшихся атак"
	else:
		_hint_label.text = "ПКМ — липкий плевок · ЛКМ — хлыст"


func _spawn_first_enemy() -> void:
	first_enemy = _add_enemy(Vector3(0.0, 0.05, 0.0))


func _add_enemy(at: Vector3) -> Spitter:
	var enemy := SPITTER_SCENE.instantiate() as Spitter
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.position = at
	enemy.player_target = player
	add_child(enemy)
	enemy.projectile_requested.connect(_on_enemy_projectile)
	enemy.phase_changed.connect(_on_enemy_phase_changed)
	enemy.died.connect(_on_enemy_died)
	return enemy


func _on_enemy_died(enemy: Spitter, ability_id: StringName, at: Vector3) -> void:
	if enemy == first_enemy:
		stage = &"absorb"
		first_source = SOURCE_SCENE.instantiate() as AbsorbSource
		first_source.process_mode = Node.PROCESS_MODE_PAUSABLE
		first_source.ability_id = ability_id
		first_source.position = at
		add_child(first_source)
	elif enemy == second_enemy:
		stage = &"clear_pending"
		_show_info("Враг побежден. Осторожно: оставшиеся атаки еще летят")


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	if not is_instance_valid(enemy):
		return
	_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key, 1.0, 0.0)
	_play_audio(_enemy_spit_audio, origin)


func _on_enemy_phase_changed(enemy: Spitter, phase: StringName) -> void:
	if phase == &"windup" and is_instance_valid(enemy):
		_play_audio(_enemy_charge_audio, enemy.global_position)


func _on_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	_add_projectile(player, &"player", origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds)
	_play_audio(_player_spit_audio, origin)


func _add_projectile(owner_body: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> SpitProjectile:
	var projectile := PROJECTILE_SCENE.instantiate() as SpitProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner_body, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	add_child(projectile)
	projectile.global_position = origin
	projectile.resolved.connect(_on_projectile_resolved)
	return projectile


func _on_projectile_resolved(at: Vector3, damaged_target: bool) -> void:
	if damaged_target:
		_play_audio(_hit_audio, at)


func _on_whip_hit(at: Vector3) -> void:
	_play_audio(_hit_audio, at)


func _on_action_started(action_id: StringName) -> void:
	if action_id == &"slime_whip":
		_play_audio(_whip_audio, player.global_position)
	elif action_id == &"sticky_spit":
		_play_audio(_cast_audio, player.global_position)


func _on_health_changed(current: int, maximum: int) -> void:
	_health_label.text = "СЛАЙМ  %d / %d HP" % [current, maximum]
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_ability_unlocked(_ability_id: StringName) -> void:
	stage = &"approach"
	_card_left = 1.8
	_card_back.visible = true
	_play_audio(_absorb_audio, player.global_position)


func _on_absorb_progress(progress: float, _source: Node3D) -> void:
	_absorb_progress.value = progress
	_absorb_progress.visible = progress > 0.0


func _spawn_second_if_ready() -> void:
	if stage != &"approach" or _card_left > 0.0 or not _entered_second_zone:
		return
	if not get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty():
		return
	var points := [Vector3(0.0, 0.05, -8.4), Vector3(-5.3, 0.05, -7.2), Vector3(5.3, 0.05, -7.2), Vector3(0.0, 0.05, 4.0)]
	var spawn_at := Vector3.ZERO
	var found_spawn := false
	for candidate: Vector3 in points:
		if candidate.distance_to(player.global_position) >= 5.0:
			spawn_at = candidate
			found_spawn = true
			break
	if not found_spawn:
		return
	second_enemy = _add_enemy(spawn_at)
	stage = &"second_fight"
	_show_info("Новый Плевун. Попробуй плевок на расстоянии")


func _on_player_died() -> void:
	stage = &"dead"
	_show_end("Слайм рассыпался")


func _complete_run() -> void:
	stage = &"complete"
	_show_end("Цикл пройден")
	_next_button.visible = true


func _show_end(title: String) -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end_title.text = title
	_end_overlay.visible = true
	_pause_overlay.visible = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _enter_r03() -> void:
	if get_tree().get_meta(&"checkpoint_active", false):
		var store: CheckpointStore = STORE_SCRIPT.new()
		var written := store.write_checkpoint(store.snapshot_for_room("R03", player))
		if not written["ok"]:
			_end_title.text = "Не удалось сохранить вход в R03"
			return
	get_tree().paused = false
	var result := get_tree().change_scene_to_file("res://scenes/r03_armorer.tscn")
	if result != OK:
		get_tree().paused = true
		_end_title.text = "Не удалось открыть R03"


func _show_info(message: String) -> void:
	_info_text = message
	_info_left = 2.0
	_hint_label.text = message


func _create_audio() -> void:
	_hit_audio = _make_audio(HIT_SOUND)
	_absorb_audio = _make_audio(ABSORB_SOUND)
	_cast_audio = _make_audio(CAST_SOUND)
	_whip_audio = _make_audio(WHIP_SOUND)
	_player_spit_audio = _make_audio(PLAYER_SPIT_SOUND)
	_enemy_charge_audio = _make_audio(ENEMY_CHARGE_SOUND)
	_enemy_charge_audio.unit_size = 8.0
	_enemy_spit_audio = _make_audio(ENEMY_SPIT_SOUND)
	_enemy_spit_audio.unit_size = 7.0


func _make_audio(stream: AudioStream) -> AudioStreamPlayer3D:
	var player_3d := AudioStreamPlayer3D.new()
	player_3d.process_mode = Node.PROCESS_MODE_PAUSABLE
	player_3d.stream = stream
	player_3d.unit_size = 3.0
	add_child(player_3d)
	return player_3d


func _play_audio(audio_player: AudioStreamPlayer3D, at: Vector3) -> void:
	audio_player.global_position = at
	audio_player.play()


func _create_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(root)
	var status_back := ColorRect.new()
	status_back.color = Color(0.025, 0.08, 0.10, 0.80)
	status_back.position = Vector2(18.0, 16.0)
	status_back.size = Vector2(435.0, 106.0)
	status_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_back)
	var status_accent := ColorRect.new()
	status_accent.color = Color(0.25, 0.88, 0.70)
	status_accent.position = Vector2(18.0, 16.0)
	status_accent.size = Vector2(5.0, 106.0)
	status_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_accent)
	_health_label = _make_label(root, Vector2(32.0, 22.0), 24)
	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(32.0, 57.0)
	_health_bar.size = Vector2(404.0, 8.0)
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color(0.11, 0.22, 0.23)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.34, 0.92, 0.70)
	_health_bar.add_theme_stylebox_override("background", bar_back)
	_health_bar.add_theme_stylebox_override("fill", bar_fill)
	root.add_child(_health_bar)
	_slot_label = _make_label(root, Vector2(32.0, 77.0), 20)
	var crosshair := _make_label(root, Vector2.ZERO, 26)
	crosshair.text = "+"
	crosshair.add_theme_color_override("font_color", Color(1.0, 0.84, 0.52))
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -8.0
	crosshair.offset_top = -16.0
	var hint_back := ColorRect.new()
	hint_back.color = Color(0.025, 0.08, 0.10, 0.72)
	hint_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_back.anchor_left = 0.5
	hint_back.anchor_right = 0.5
	hint_back.anchor_top = 1.0
	hint_back.anchor_bottom = 1.0
	hint_back.offset_left = -425.0
	hint_back.offset_right = 425.0
	hint_back.offset_top = -78.0
	hint_back.offset_bottom = -20.0
	root.add_child(hint_back)
	_hint_label = _make_label(root, Vector2.ZERO, 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.2
	_hint_label.anchor_right = 0.8
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -74.0
	_hint_label.offset_bottom = -27.0
	_absorb_progress = ProgressBar.new()
	_absorb_progress.min_value = 0.0
	_absorb_progress.max_value = 1.0
	_absorb_progress.show_percentage = false
	_absorb_progress.anchor_left = 0.5
	_absorb_progress.anchor_right = 0.5
	_absorb_progress.anchor_top = 1.0
	_absorb_progress.anchor_bottom = 1.0
	_absorb_progress.offset_left = -150.0
	_absorb_progress.offset_right = 150.0
	_absorb_progress.offset_top = -100.0
	_absorb_progress.offset_bottom = -82.0
	_absorb_progress.visible = false
	root.add_child(_absorb_progress)
	_card_back = ColorRect.new()
	_card_back.color = Color(0.05, 0.14, 0.16, 0.85)
	_card_back.anchor_left = 0.5
	_card_back.anchor_right = 0.5
	_card_back.offset_left = -250.0
	_card_back.offset_right = 250.0
	_card_back.offset_top = 115.0
	_card_back.offset_bottom = 187.0
	root.add_child(_card_back)
	_card_label = _make_label(_card_back, Vector2(15.0, 8.0), 22)
	_card_label.text = "Липкий плевок получен\nПКМ — замедляет врага"
	_card_label.size = Vector2(470.0, 58.0)
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_back.visible = false
	_end_overlay = ColorRect.new()
	_end_overlay.color = Color(0.02, 0.04, 0.07, 0.87)
	_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_overlay.visible = false
	root.add_child(_end_overlay)
	var end_box := VBoxContainer.new()
	end_box.anchor_left = 0.5
	end_box.anchor_right = 0.5
	end_box.anchor_top = 0.5
	end_box.anchor_bottom = 0.5
	end_box.offset_left = -160.0
	end_box.offset_right = 160.0
	end_box.offset_top = -90.0
	end_box.offset_bottom = 100.0
	_end_overlay.add_child(end_box)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 30)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(_end_title)
	var repeat_button := Button.new()
	repeat_button.text = "Повторить (R)"
	repeat_button.custom_minimum_size.y = 46.0
	_style_button(repeat_button)
	repeat_button.pressed.connect(_restart)
	end_box.add_child(repeat_button)
	_next_button = Button.new()
	_next_button.text = "Продолжить: Панцирный проход"
	_next_button.custom_minimum_size.y = 46.0
	_next_button.visible = false
	_style_button(_next_button)
	_next_button.pressed.connect(_enter_r03)
	end_box.add_child(_next_button)
	var exit_button := Button.new()
	exit_button.text = "Выйти"
	exit_button.custom_minimum_size.y = 46.0
	_style_button(exit_button)
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	end_box.add_child(exit_button)


func _make_label(parent: Control, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.95, 0.98, 0.96))
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.03, 0.04, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label


func _style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.25, 0.25)
	normal.set_corner_radius_all(7)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.13, 0.38, 0.34)
	hover.set_corner_radius_all(7)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color.WHITE)

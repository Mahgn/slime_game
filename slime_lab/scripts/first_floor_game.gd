extends Node3D

const MENU_SCENE := "res://scenes/menu.tscn"
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/slime_player.tscn")
const SPITTER_SCENE: PackedScene = preload("res://scenes/enemies/spitter.tscn")
const ARMORER_SCENE: PackedScene = preload("res://scenes/enemies/armorer.tscn")
const SPROUT_SCENE: PackedScene = preload("res://scenes/enemies/stone_sprout.tscn")
const SOURCE_SCENE: PackedScene = preload("res://scenes/interactables/absorb_source.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/abilities/spit_projectile.tscn")
const BLOCKOUT_SCENE: PackedScene = preload("res://scenes/opening_blockout.tscn")
const INPUT_SETUP = preload("res://scripts/input_setup.gd")
const DRESSING = preload("res://scripts/dungeon_dressing.gd")
const ROUTE = preload("res://scripts/first_floor_route.gd")
const ROPE_TARGET = preload("res://scripts/first_floor_rope_target.gd")

const SOUNDS := {
	"whip": preload("res://assets/audio/whip.wav"),
	"hit": preload("res://assets/audio/hit.wav"),
	"cast": preload("res://assets/audio/cast.wav"),
	"spit": preload("res://assets/audio/player_spit.wav"),
	"absorb": preload("res://assets/audio/absorb.wav"),
	"charge": preload("res://assets/audio/enemy_charge.wav"),
}

var player: SlimeController
var _route_refs: Dictionary = {}
var _low_roof_visual: MeshInstance3D
var _checkpoint := Vector3(0.0, 0.05, 5.0)
var _current_zone := "R01 · Нижняя чаша"
var _objective := "Найди путь наверх и доберись до галереи"
var _bridge_open := false
var _completed := false
var _r02_followup_spawned := false
var _health_bar: ProgressBar
var _health_label: Label
var _zone_label: Label
var _objective_label: Label
var _slot_label: Label
var _hint_label: Label
var _absorb_progress: ProgressBar
var _overlay: ColorRect
var _overlay_title: Label
var _overlay_detail: Label
var _overlay_resume: Button
var _overlay_retry: Button
var _loadout: ColorRect
var _loadout_list: VBoxContainer
var _message := ""
var _message_left := 0.0
var _audio: Dictionary = {}


func _enter_tree() -> void:
	INPUT_SETUP.install()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_build_world()
	_build_player()
	_build_audio()
	_build_ui()
	_build_enemies()
	_connect_route()
	_on_health_changed(player.health, player.MAX_HEALTH)
	_show_message("Голос: новый герой зарегистрирован задним числом. Приятного экзамена.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and _overlay.visible and _overlay_retry.visible:
			_restart_at_checkpoint()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"pause") and not (event is InputEventKey and event.echo):
		if _loadout.visible:
			_close_loadout()
		elif _overlay.visible and _overlay_resume.visible:
			_resume_game()
		elif not _completed and player.is_alive():
			_pause_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"open_loadout") and not (event is InputEventKey and event.echo) and player.is_alive() and not _completed and not _overlay.visible:
		if _loadout.visible:
			_close_loadout()
		else:
			_open_loadout()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not get_tree().paused and not _completed and player.is_alive():
		_pause_game()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(_low_roof_visual):
		_low_roof_visual.visible = not player.is_compressed()
	if not get_tree().paused:
		_message_left = maxf(0.0, _message_left - delta)
		if player.global_position.y < _checkpoint.y - 5.0:
			player.revive_at_checkpoint(_checkpoint)
			_show_message("Служебная страховка вернула Слизи на последнюю отметку")
	_update_hud()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or get_tree().paused:
		return
	var passage := _route_refs.get("low_passage") as Node3D
	if passage == null:
		return
	var local := passage.to_local(player.global_position)
	var inside := absf(local.x) <= 1.12 and absf(local.z) <= 3.0
	var below_roof := local.y < 0.58
	player.set_low_passage_active(passage, inside and below_roof and (player.is_on_floor() or player.is_compressed()))


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.065, 0.085, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.64, 0.66)
	environment.ambient_light_energy = 0.78
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var blockout := BLOCKOUT_SCENE.instantiate()
	blockout.name = "OpeningCyclopsBlockout"
	add_child(blockout)
	DRESSING.build(self)
	_route_refs = ROUTE.build(self)
	_low_roof_visual = (_route_refs["low_passage"] as Node3D).get_node("LowRoof/Stone") as MeshInstance3D
	for at in [Vector3(0, 8, 5), Vector3(0, 6, -20), Vector3(2, 6, -37), Vector3(20, 8, -38), Vector3(27, 9, -16), Vector3(10, 10, -5), Vector3(0, 10, -32)]:
		var light := OmniLight3D.new()
		light.position = at
		light.light_color = Color(0.88, 0.73, 0.49)
		light.light_energy = 1.9
		light.omni_range = 13.0
		add_child(light)
	_build_imported_assets()


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate() as SlimeController
	player.name = "OurSlime"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.position = Vector3(0.0, 1.8, 5.0)
	add_child(player)
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	player.projectile_requested.connect(_on_player_projectile)
	player.spikes_requested.connect(_on_player_spikes)
	player.whip_hit.connect(func(at: Vector3) -> void: _play_audio("hit", at))
	player.action_started.connect(_on_action_started)
	player.ability_unlocked.connect(_on_ability_unlocked)
	player.absorb_progress_changed.connect(_on_absorb_progress)
	player.info_requested.connect(_show_message)

func _build_enemies() -> void:
	_spawn_spitter(Vector3(0, 2.65, -30))
	_spawn_borrowable(ARMORER_SCENE, Vector3(16, 3.25, -40))
	_spawn_spitter(Vector3(27, 4.85, -29))
	_spawn_borrowable(SPROUT_SCENE, Vector3(27, 6.25, -9))
	_spawn_spitter(Vector3(23, 6.25, -7))
	_spawn_spitter(Vector3(-3.5, 7.45, -22.5))
	_spawn_borrowable(ARMORER_SCENE, Vector3(-2.5, 7.45, -33))
	_spawn_spitter(Vector3(3.5, 7.45, -35))


func _spawn_spitter(at: Vector3) -> void:
	var enemy := SPITTER_SCENE.instantiate() as Spitter
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.player_target = player
	enemy.position = at
	add_child(enemy)
	enemy.projectile_requested.connect(_on_enemy_projectile)
	enemy.died.connect(_on_enemy_died)
	enemy.phase_changed.connect(_on_enemy_phase)


func _spawn_borrowable(scene: PackedScene, at: Vector3) -> void:
	var enemy := scene.instantiate() as BorrowableEnemy
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.player_target = player
	enemy.position = at
	add_child(enemy)
	enemy.died.connect(_on_enemy_died)
	enemy.spikes_requested.connect(_on_enemy_spikes)
	enemy.phase_changed.connect(_on_enemy_phase)


func _connect_route() -> void:
	for area in _route_refs["areas"]:
		area.body_entered.connect(_on_zone_entered.bind(String(area.get_meta("zone_code"))))
	var rope := ROPE_TARGET.new() as FirstFloorRopeTarget
	rope.name = "R09RopeTarget"
	rope.position = Vector3(0, 7.45, -37.5)
	add_child(rope)
	rope.released.connect(_lower_bridge)


func _on_zone_entered(body: Node3D, code: String) -> void:
	if body != player or _completed:
		return
	match code:
		"K1":
			_checkpoint = Vector3(-3.5, 2.7, -35)
			_show_message("Отметка К1: если расплющишься, вернёшься сюда")
		"R03":
			_current_zone = "R03 · Балкон наблюдения"
			_objective = "Впереди Панцирник: бей после его защиты"
			_show_message("Голос: наблюдение за экзаменатором пересдачей не считается")
		"R04":
			_current_zone = "R04 · Гнездо шлемов"
			_checkpoint = Vector3(11, 3.25, -43)
			_objective = "Победи Панцирника, поглоти панцирь удержанием E"
			_show_message("Голос: найденные шлемы просьба не присваивать. Панцирник оспаривает")
		"R05":
			_current_zone = "R05 · Проход плевка"
			_objective = "Проверь липкий плевок на расстоянии и перепрыгни разрыв"
			_show_message("Табличка: плевать в канцелярию запрещено. В цель — разрешено")
		"R06":
			_current_zone = "R06 · Верхний карниз"
			_objective = "Победи Ростка и поглоти слизевые шипы"
			_show_message("Голос: Росток вырос без согласования. Осторожно, он это слышит")
		"R07":
			_current_zone = "R07 · Смотровая площадка"
			_checkpoint = Vector3(11, 6.9, -1)
			_objective = "Передохни и выбери два навыка через Tab"
			_show_message("Отсюда видна точка падения. Комиссия считает это карьерным ростом")
		"R08":
			_current_zone = "R08 · Два обхода"
			_objective = "Слева низкий проход: сожмись. Справа короткий путь: прыгай"
			_show_message("Указатель: через низкий проход допускаются лица ростом со слизь")
		"K4":
			_checkpoint = Vector3(0, 7.45, -24)
			_show_message("Отметка К4: впереди выходной пролёт")
		"R09":
			_current_zone = "R09 · Выходной пролёт"
			_objective = "Доберись до каната и ударь по нему хлыстом"
			_show_message("Голос: выход по записи. Канат, к счастью, читать не умеет")
		"EXIT":
			if _bridge_open:
				_finish_floor()
		"R02":
			_current_zone = "R02 · Галерея находок"
			_objective = "Победи Плевуна, удерживай E у остатка, используй плевок на ПКМ"
			_show_message("Голос: найденное на полу считается найденным отделом находок")


func _on_enemy_died(_enemy: Node3D, ability_id: StringName, at: Vector3) -> void:
	_play_audio("hit", at)
	if player.has_learned(ability_id):
		return
	for source in get_tree().get_nodes_in_group(&"absorb_sources"):
		if source.get("ability_id") == ability_id:
			return
	var source := SOURCE_SCENE.instantiate() as AbsorbSource
	source.process_mode = Node.PROCESS_MODE_PAUSABLE
	source.ability_id = ability_id
	source.position = at
	add_child(source)
	_show_message("Остаток навыка! Подойди и удерживай E")


func _on_enemy_phase(enemy: Node3D, phase: StringName) -> void:
	if phase == &"windup" and enemy.global_position.distance_to(player.global_position) < 12.0:
		_play_audio("charge", enemy.global_position)


func _on_player_projectile(origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	_add_projectile(player, &"player", origin, direction, damage, speed, max_range, cast_key, slow_factor, slow_seconds)
	_play_audio("spit", origin)


func _on_enemy_projectile(enemy: Spitter, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String) -> void:
	_add_projectile(enemy, &"enemy", origin, direction, damage, speed, max_range, cast_key, 1.0, 0.0)


func _add_projectile(owner: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, damage: int, speed: float, max_range: float, cast_key: String, slow_factor: float, slow_seconds: float) -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as SpitProjectile
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.configure(owner, team, direction, speed, damage, max_range, cast_key, slow_factor, slow_seconds)
	add_child(projectile)
	projectile.global_position = origin
	projectile.resolved.connect(func(at: Vector3, hit: bool) -> void: if hit: _play_audio("hit", at))


func _on_player_spikes(origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(player, &"player", origin, direction, cast_key, 22)


func _on_enemy_spikes(enemy: BorrowableEnemy, origin: Vector3, direction: Vector3, cast_key: String) -> void:
	_add_spikes(enemy, &"enemy", origin, direction, cast_key, 14)


func _add_spikes(owner: CollisionObject3D, team: StringName, origin: Vector3, direction: Vector3, cast_key: String, damage: int) -> void:
	var line := SpikeLine.new()
	line.process_mode = Node.PROCESS_MODE_PAUSABLE
	line.configure(owner, team, origin, direction, cast_key, damage)
	add_child(line)
	line.hit_target.connect(func(at: Vector3, _empowered: bool) -> void: _play_audio("hit", at))


func _on_action_started(action_id: StringName) -> void:
	if action_id == &"slime_whip":
		_play_audio("whip", player.global_position)
	elif action_id != &"sticky_spit":
		_play_audio("cast", player.global_position)


func _on_ability_unlocked(ability_id: StringName) -> void:
	_play_audio("absorb", player.global_position)
	if ability_id == &"sticky_spit" and not _r02_followup_spawned:
		_r02_followup_spawned = true
		_spawn_spitter(Vector3(3.2, 2.65, -34))
		_show_message("Липкий плевок изучен. Второй Плевун пришёл на пересдачу — ПКМ")
		_objective = "Испытай липкий плевок на втором Плевуне — ПКМ"
		return
	if ability_id == &"elastic_shell" and player.unlocked_slots < 2:
		player.unlock_second_slot()
		_show_message("Панцирь изучен. Второй слот открыт — Q")
	else:
		_show_message("Изучено: %s. Выбрать навыки — Tab" % _ability_name(ability_id))
	match ability_id:
		&"sticky_spit": _objective = "ПКМ — липкий плевок. Испытай его на следующем враге"
		&"elastic_shell": _objective = "Q — панцирь. В коллекции Tab можно поменять оба слота"
		&"slime_spikes": _objective = "Поменяй один из слотов через Tab и испытай шипы"


func _on_absorb_progress(progress: float, _source: Node3D) -> void:
	if is_instance_valid(_absorb_progress):
		_absorb_progress.value = progress
		_absorb_progress.visible = progress > 0.0


func _lower_bridge() -> void:
	if _bridge_open:
		return
	_bridge_open = true
	var bridge := _route_refs["bridge"] as StaticBody3D
	bridge.process_mode = Node.PROCESS_MODE_PAUSABLE
	bridge.position.y = 10.5
	(_route_refs["bridge_mesh"] as MeshInstance3D).visible = true
	var tween := create_tween().bind_node(bridge)
	tween.tween_property(bridge, "position", Vector3(0, 7.15, -41), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: (_route_refs["bridge_shape"] as CollisionShape3D).set_deferred("disabled", false))
	_objective = "Мост опущен. Перейди на второй этаж"
	_show_message("Отдел технической безопасности искренне удивлён твоим успехом")


func _finish_floor() -> void:
	_completed = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_overlay("ПЕРВЫЙ ЭТАЖ ПРОЙДЕН", "Слизи поднялся. Хозяйственный этаж пока строится.", false, false)


func _on_player_died() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_overlay("СЛИЗИ РАСПЛЮЩЕН", "R — вернуться к последней отметке", false, true)


func _restart_at_checkpoint() -> void:
	for node in get_tree().get_nodes_in_group(&"projectiles") + get_tree().get_nodes_in_group(&"temporary_effects"):
		if is_instance_valid(node):
			node.queue_free()
	player.revive_at_checkpoint(_checkpoint)
	_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause_game() -> void:
	player.cancel_absorb_for_pause()
	player.clear_action_buffer()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_overlay("ПАУЗА", "Escape — продолжить · Tab — коллекция", true, false)


func _resume_game() -> void:
	_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_loadout() -> void:
	player.cancel_absorb_for_pause()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_loadout.visible = true
	_refresh_loadout()


func _close_loadout() -> void:
	_loadout.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_loadout() -> void:
	for child in _loadout_list.get_children():
		_loadout_list.remove_child(child)
		child.queue_free()
	for slot in range(1, player.unlocked_slots + 1):
		_loadout_list.add_child(_label("СЛОТ %d: %s" % [slot, _ability_name(player.get_slot_ability(slot))], 18, Color(0.98, 0.84, 0.54)))
		for ability_id in SlimeController.KNOWN_ABILITIES:
			if not player.has_learned(ability_id):
				continue
			var button := Button.new()
			button.text = _ability_name(ability_id)
			button.disabled = player.get_slot_ability(slot) == ability_id
			button.pressed.connect(_equip_ability.bind(slot, ability_id))
			_loadout_list.add_child(button)


func _equip_ability(slot: int, ability_id: StringName) -> void:
	if player.equip_ability(slot, ability_id):
		_refresh_loadout()


func _ability_name(id: StringName) -> String:
	match id:
		&"sticky_spit": return "Липкий плевок"
		&"elastic_shell": return "Упругий панцирь"
		&"slime_spikes": return "Слизевые шипы"
	return "пусто"


func _show_message(value: String) -> void:
	_message = value
	_message_left = 3.6


func _on_health_changed(current: int, maximum: int) -> void:
	if not is_instance_valid(_health_bar):
		return
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "СЛИЗИ   %d / %d" % [current, maximum]


func _update_hud() -> void:
	_zone_label.text = _current_zone
	_objective_label.text = _objective
	var slot_1 := player.get_slot_ability(1)
	var slot_2 := player.get_slot_ability(2)
	_slot_label.text = "ЛКМ  Хлыст    ·    ПКМ  %s    ·    Q  %s" % [_ability_name(slot_1), _ability_name(slot_2)]
	var source := player.get_nearest_absorb_source() if not get_tree().paused else null
	if is_instance_valid(source):
		_hint_label.text = "Удерживай E — поглотить %s" % _ability_name(source.ability_id)
	elif player.is_compressed():
		_hint_label.text = "Слизи сжался под потолком. Иди вперёд — снаружи распрямится"
	elif _message_left > 0.0:
		_hint_label.text = _message
	else:
		_hint_label.text = "WASD — движение · мышь — камера · удержи и отпусти пробел — прыжок · Tab — коллекция · Esc — пауза"


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameHud"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "StatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_left = 20
	panel.offset_top = 20
	panel.offset_right = 520
	panel.offset_bottom = 185
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.10, 0.88)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(13)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	panel.add_child(stack)
	stack.add_child(_label("ПРИЁМНОЕ ОТДЕЛЕНИЕ · ПЕРВЫЙ ЭТАЖ", 17, Color(0.55, 0.95, 0.81)))
	_health_label = _label("СЛИЗИ   100 / 100", 16, Color.WHITE)
	stack.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(0, 10)
	_health_bar.show_percentage = false
	stack.add_child(_health_bar)
	_zone_label = _label(_current_zone, 15, Color(0.98, 0.82, 0.48))
	stack.add_child(_zone_label)
	_objective_label = _label(_objective, 13, Color.WHITE)
	stack.add_child(_objective_label)
	_slot_label = _label("", 13, Color(0.63, 0.91, 0.84))
	stack.add_child(_slot_label)
	var crosshair := _label("+", 26, Color(0.85, 1.0, 0.92, 0.75))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -17)
	layer.add_child(crosshair)
	_hint_label = _label("", 15, Color(1.0, 0.92, 0.65))
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_left = 24
	_hint_label.offset_right = -24
	_hint_label.offset_top = -56
	_hint_label.offset_bottom = -20
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hint_label)
	_absorb_progress = ProgressBar.new()
	_absorb_progress.name = "AbsorbProgress"
	_absorb_progress.show_percentage = false
	_absorb_progress.max_value = 1.0
	_absorb_progress.value = 0.0
	_absorb_progress.visible = false
	_absorb_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_absorb_progress.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_absorb_progress.position = Vector2(-130, -70)
	_absorb_progress.custom_minimum_size = Vector2(260, 8)
	layer.add_child(_absorb_progress)
	_build_overlay(layer)
	_build_loadout(layer)


func _build_overlay(layer: CanvasLayer) -> void:
	_overlay = ColorRect.new()
	_overlay.name = "PauseOverlay"
	_overlay.color = Color(0.02, 0.04, 0.06, 0.84)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	layer.add_child(_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-230, -135)
	box.custom_minimum_size = Vector2(460, 270)
	box.add_theme_constant_override("separation", 16)
	_overlay.add_child(box)
	_overlay_title = _label("ПАУЗА", 32, Color(0.57, 0.95, 0.80))
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)
	_overlay_detail = _label("", 18, Color.WHITE)
	_overlay_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_detail)
	_overlay_resume = Button.new()
	_overlay_resume.text = "Продолжить"
	_overlay_resume.pressed.connect(_resume_game)
	box.add_child(_overlay_resume)
	_overlay_retry = Button.new()
	_overlay_retry.text = "Вернуться к отметке"
	_overlay_retry.pressed.connect(_restart_at_checkpoint)
	box.add_child(_overlay_retry)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "В меню"
	back.pressed.connect(_back_to_menu)
	box.add_child(back)


func _show_overlay(title: String, detail: String, resume: bool, retry: bool) -> void:
	_overlay_title.text = title
	_overlay_detail.text = detail
	_overlay_resume.visible = resume
	_overlay_retry.visible = retry
	_overlay.visible = true
	_loadout.visible = false


func _build_loadout(layer: CanvasLayer) -> void:
	_loadout = ColorRect.new()
	_loadout.name = "LoadoutOverlay"
	_loadout.color = Color(0.02, 0.04, 0.06, 0.90)
	_loadout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout.visible = false
	layer.add_child(_loadout)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -215)
	box.custom_minimum_size = Vector2(440, 430)
	box.add_theme_constant_override("separation", 10)
	_loadout.add_child(box)
	box.add_child(_label("КОЛЛЕКЦИЯ ПОВАДОК", 28, Color(0.57, 0.95, 0.80)))
	box.add_child(_label("Выбери до двух навыков. Хлыст всегда доступен.", 16, Color.WHITE))
	_loadout_list = VBoxContainer.new()
	_loadout_list.add_theme_constant_override("separation", 7)
	box.add_child(_loadout_list)
	var close := Button.new()
	close.text = "Вернуться в игру (Tab)"
	close.pressed.connect(_close_loadout)
	box.add_child(close)


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _back_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _build_audio() -> void:
	for key in SOUNDS:
		var sound := AudioStreamPlayer3D.new()
		sound.name = "Audio_" + key
		sound.process_mode = Node.PROCESS_MODE_PAUSABLE
		sound.stream = SOUNDS[key]
		sound.unit_size = 4.0
		add_child(sound)
		_audio[key] = sound


func _play_audio(key: String, at: Vector3) -> void:
	var sound := _audio.get(key) as AudioStreamPlayer3D
	if sound == null:
		return
	sound.global_position = at
	sound.play()


func _build_imported_assets() -> void:
	var crate := ResourceLoader.load("res://assets/first_floor/sample_crate.gltf") as PackedScene
	if crate != null:
		var instance := crate.instantiate() as Node3D
		instance.name = "ImportedSampleCrate"
		instance.position = Vector3(4.8, 0.05, 3.0)
		instance.scale = Vector3.ONE * 1.45
		add_child(instance)
	var marker := ResourceLoader.load("res://assets/first_floor/marker.svg") as Texture2D
	if marker != null:
		var sign := MeshInstance3D.new()
		sign.name = "ImportedSvgSign"
		var quad := QuadMesh.new()
		quad.size = Vector2(3.8, 1.9)
		sign.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_texture = marker
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sign.material_override = material
		sign.position = Vector3(5.15, 4.3, -22.94)
		add_child(sign)

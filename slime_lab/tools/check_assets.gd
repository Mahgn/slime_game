extends SceneTree

const ASSET_ROOT := "res://assets/first_floor"
const V5_MODEL := "res://assets/first_floor/slime_hero_v5.res"
const SUPPORTED_EXTENSIONS = ["png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "obj", "wav", "ogg", "mp3"]

var _checked := 0
var _failed: Array[String] = []


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	_scan(ASSET_ROOT)
	if _checked == 0:
		_failed.append("В assets/first_floor нет проверяемых файлов.")
	var v5_mesh := ResourceLoader.load(V5_MODEL) as ArrayMesh
	if v5_mesh == null or v5_mesh.get_surface_count() != 4:
		_failed.append("Модель слайма v5 не загрузилась или у неё нет четырёх поверхностей.")
	if _failed.is_empty():
		await _check_first_floor()
	if _failed.is_empty():
		print("PASS: импортировано %d ассетов; первый этаж открывается из меню с Cyclops-маршрутом, моделью v5 и новым контроллером." % _checked)
		quit(0)
		return
	for message in _failed:
		printerr("FAIL: " + message)
	quit(1)


func _check_first_floor() -> void:
	var menu_resource := ResourceLoader.load("res://scenes/menu.tscn") as PackedScene
	if menu_resource == null:
		_failed.append("Не загрузилось меню лаборатории.")
		return
	var menu := menu_resource.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var first_floor_button := menu.find_child("FirstFloorButton", true, false) as Button
	if first_floor_button == null:
		_failed.append("В меню нет кнопки первого этажа.")
		return
	first_floor_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/first_floor.tscn":
		_failed.append("Кнопка не открыла первый этаж.")
		return
	for node_name in ["OurSlime", "ImportedSampleCrate", "ImportedSvgSign"]:
		if current_scene.find_child(node_name, true, false) == null:
			_failed.append("На первом этаже нет узла " + node_name)
	var opening := current_scene.find_child("OpeningCyclopsBlockout", true, false)
	if opening == null or opening.get_child_count() < 20:
		_failed.append("На первом этаже не загружен Cyclops-макет шахты.")
	var slime_model := current_scene.find_child("SlimeHeroModelV5", true, false) as MeshInstance3D
	if slime_model == null or slime_model.mesh == null or slime_model.mesh.resource_path != V5_MODEL:
		_failed.append("На первом этаже не используется модель слайма v5.")
	else:
		for surface_index in range(slime_model.mesh.get_surface_count()):
			if not slime_model.get_surface_override_material(surface_index) is ShaderMaterial:
				_failed.append("У модели v5 не настроен анимируемый материал поверхности %d." % surface_index)
	var player := current_scene.find_child("OurSlime", true, false) as SlimeController
	if player != null:
		if player.get_node_or_null("CameraYaw/CameraPitch/SpringArm3D/Camera3D") == null:
			_failed.append("Не установлена третьеличная камера с SpringArm3D.")
		if not slime_model is SlimeHeroVisual:
			_failed.append("Модель v5 не использует обновлённый контроллер ползания.")
		if player.get_node_or_null("VisualRoot/SlimeHeroModelV5/SlimeWhip") == null:
			_failed.append("Новый хлыст не прикреплён к модели Слизи.")
		var ground_trail := player.get_node_or_null("GroundTrail") as SlimeGroundTrail
		if ground_trail == null:
			_failed.append("Новый слизевой след не подключён к персонажу.")
		for frame in range(25):
			await physics_frame
		var start_z := player.global_position.z
		Input.action_press("move_forward")
		for frame in range(25):
			await physics_frame
		Input.action_release("move_forward")
		if player.global_position.z > start_z - 0.5:
			_failed.append("Слайм не двигается по первому этажу.")
		if ground_trail != null and ground_trail.mesh.get_surface_count() == 0:
			_failed.append("Движение не оставило слизевой след на полу.")
	var back_button := current_scene.find_child("BackButton", true, false) as Button
	if back_button == null:
		_failed.append("На первом этаже нет возврата в меню.")
		return
	back_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/menu.tscn":
		_failed.append("Не удалось вернуться с первого этажа в меню.")


func _scan(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_failed.append("Не открылась папка " + directory_path)
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while filename != "":
		if filename.begins_with("."):
			filename = directory.get_next()
			continue
		var asset_path := directory_path.path_join(filename)
		if directory.current_is_dir():
			_scan(asset_path)
		elif SUPPORTED_EXTENSIONS.has(filename.get_extension().to_lower()):
			_checked += 1
			if not ResourceLoader.exists(asset_path) or ResourceLoader.load(asset_path) == null:
				_failed.append("Не загрузился " + asset_path)
		filename = directory.get_next()
	directory.list_dir_end()

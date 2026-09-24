class_name CheckpointStore
extends RefCounted

const VERSION := 1
const ABILITY_IDS := ["sticky_spit", "elastic_shell", "slime_spikes"]
const ROOM_IDS := ["R01", "R02", "R03", "R04", "R05", "R06", "R07"]
const CORE_ID := "r04_core"

var path: String


func _init(save_path: String = "user://checkpoint.json") -> void:
	path = save_path


func initial_snapshot() -> Dictionary:
	return {
		"save_version": VERSION,
		"checkpoint_room_id": "R01",
		"learned_abilities": [],
		"unlocked_slots": 1,
		"loadout": ["", ""],
		"collected_cores": [],
		"completed_rooms": [],
		"slice_complete": false,
	}


func snapshot_for_room(room_id: String, player: SlimeController) -> Dictionary:
	var learned: Array[String] = []
	for ability_id: String in ABILITY_IDS:
		if player.has_learned(StringName(ability_id)):
			learned.append(ability_id)
	var completed: Array[String] = []
	for known_room: String in ROOM_IDS:
		if known_room == room_id:
			break
		completed.append(known_room)
	return {
		"save_version": VERSION,
		"checkpoint_room_id": room_id,
		"learned_abilities": learned,
		"unlocked_slots": player.unlocked_slots,
		"loadout": [String(player.get_slot_ability(1)), String(player.get_slot_ability(2))],
		"collected_cores": [CORE_ID] if player.unlocked_slots == 2 else [],
		"completed_rooms": completed,
		"slice_complete": false,
	}


func validate(snapshot: Variant) -> String:
	if not snapshot is Dictionary:
		return "Корневое значение не является объектом"
	var required := ["save_version", "checkpoint_room_id", "learned_abilities", "unlocked_slots", "loadout", "collected_cores", "completed_rooms", "slice_complete"]
	if snapshot.size() != required.size():
		return "Неверный состав полей"
	for key: String in required:
		if not snapshot.has(key):
			return "Отсутствует поле " + key
	if not _whole_number(snapshot["save_version"]) or int(snapshot["save_version"]) != VERSION:
		return "Неподдерживаемая версия"
	if not snapshot["checkpoint_room_id"] is String or not ROOM_IDS.has(snapshot["checkpoint_room_id"]):
		return "Неизвестная комната"
	var room_id: String = snapshot["checkpoint_room_id"]
	if not _whole_number(snapshot["unlocked_slots"]):
		return "Неверное число слотов"
	var slot_count := int(snapshot["unlocked_slots"])
	if slot_count < 1 or slot_count > 2:
		return "Неверное число слотов"
	if not snapshot["slice_complete"] is bool:
		return "Неверный флаг завершения"
	if not snapshot["learned_abilities"] is Array or not snapshot["loadout"] is Array or not snapshot["collected_cores"] is Array or not snapshot["completed_rooms"] is Array:
		return "Неверный тип списка"
	var learned: Array = snapshot["learned_abilities"]
	var loadout: Array = snapshot["loadout"]
	var cores: Array = snapshot["collected_cores"]
	var completed: Array = snapshot["completed_rooms"]
	if loadout.size() != 2 or learned.size() > 3 or cores.size() > 1 or completed.size() > 7:
		return "Неверная длина списка"
	var expected_learned := ABILITY_IDS.slice(0, maxi(0, ROOM_IDS.find(room_id) - 1))
	var expected_completed := ROOM_IDS.slice(0, ROOM_IDS.find(room_id))
	if learned != expected_learned:
		return "Прогресс не соответствует комнате"
	if snapshot["slice_complete"]:
		if room_id != "R07" or completed != ROOM_IDS:
			return "Завершение не соответствует комнате"
	elif completed != expected_completed:
		return "Прогресс не соответствует комнате"
	var expected_slots := 2 if ROOM_IDS.find(room_id) >= ROOM_IDS.find("R05") else 1
	if slot_count != expected_slots or cores != ([CORE_ID] if expected_slots == 2 else []):
		return "Ядро и слоты не соответствуют комнате"
	for ability: Variant in loadout:
		if not ability is String or (ability != "" and not learned.has(ability)):
			return "Неизвестный навык в слоте"
	if slot_count == 1 and loadout[1] != "":
		return "Закрытый слот занят"
	if loadout[0] != "" and loadout[0] == loadout[1]:
		return "Навык продублирован"
	return ""


func read_checkpoint() -> Dictionary:
	var main := _read_file(path)
	if main["status"] == "ok":
		return main
	var backup := _read_file(path + ".bak")
	if backup["status"] == "ok":
		return {"status": "backup", "snapshot": backup["snapshot"], "main_status": main["status"]}
	return {"status": main["status"] if main["status"] != "missing" else backup["status"]}


func write_checkpoint(snapshot: Dictionary, allow_invalid_replacement: bool = false) -> Dictionary:
	var reason := validate(snapshot)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var main := _read_file(path)
	if main["status"] != "missing" and main["status"] != "ok" and not allow_invalid_replacement:
		return {"ok": false, "error": "Основной файл поврежден или имеет другую версию"}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть временный файл: %d" % FileAccess.get_open_error()}
	var stored := file.store_string(JSON.stringify(snapshot, "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK or _read_file(temp)["status"] != "ok":
		return {"ok": false, "error": "Временный файл не прошел проверку"}
	if main["status"] == "ok":
		var backup_temp := path + ".bak.tmp"
		var copied := DirAccess.copy_absolute(_absolute(path), _absolute(backup_temp))
		if copied != OK or _read_file(backup_temp)["status"] != "ok":
			return {"ok": false, "error": "Не удалось подготовить резервную копию"}
		var backup_move := DirAccess.rename_absolute(_absolute(backup_temp), _absolute(path + ".bak"))
		if backup_move != OK or _read_file(path + ".bak")["status"] != "ok":
			return {"ok": false, "error": "Не удалось подтвердить резервную копию"}
	elif main["status"] != "missing":
		var rejected := path + ".rejected"
		var preserved := DirAccess.copy_absolute(_absolute(path), _absolute(rejected))
		if preserved != OK or not FileAccess.file_exists(rejected):
			return {"ok": false, "error": "Не удалось сохранить поврежденный файл"}
	var moved := DirAccess.rename_absolute(_absolute(temp), _absolute(path))
	if moved != OK or _read_file(path)["status"] != "ok":
		return {"ok": false, "error": "Не удалось заменить основной файл"}
	return {"ok": true}


func complete_slice(player: SlimeController) -> Dictionary:
	var result := read_checkpoint()
	if result["status"] != "ok" or result["snapshot"]["checkpoint_room_id"] != "R07":
		return {"ok": false, "error": "Нет входного снимка R07"}
	var snapshot: Dictionary = result["snapshot"]
	snapshot["completed_rooms"] = ROOM_IDS.duplicate()
	snapshot["slice_complete"] = true
	snapshot["loadout"] = [String(player.get_slot_ability(1)), String(player.get_slot_ability(2))]
	return write_checkpoint(snapshot)


func update_saved_loadout(room_id: String, player: SlimeController) -> bool:
	var result := read_checkpoint()
	if result["status"] != "ok":
		return false
	var snapshot: Dictionary = result["snapshot"]
	if snapshot["checkpoint_room_id"] != room_id:
		return false
	var learned: Array = snapshot["learned_abilities"]
	if player.unlocked_slots != snapshot["unlocked_slots"]:
		return false
	for ability: Variant in player.learned_abilities.keys():
		if not learned.has(String(ability)):
			return false
	var first := String(player.get_slot_ability(1))
	var second := String(player.get_slot_ability(2))
	if (first != "" and not learned.has(first)) or (second != "" and not learned.has(second)):
		return false
	if snapshot["loadout"] == [first, second]:
		return true
	snapshot["loadout"] = [first, second]
	return write_checkpoint(snapshot)["ok"]


func scene_path(room_id: String) -> String:
	match room_id:
		"R01": return "res://scenes/r01_entrance.tscn"
		"R02": return "res://scenes/main.tscn"
		"R03": return "res://scenes/r03_armorer.tscn"
		"R04": return "res://scenes/r04_core_trial.tscn"
		"R05": return "res://scenes/r05_mixed.tscn"
		"R06": return "res://scenes/r06_press.tscn"
		"R07": return "res://scenes/r07_guardian.tscn"
	return ""


func _read_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"status": "missing"}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"status": "io_error"}
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return {"status": "corrupt"}
	var data: Variant = parser.data
	if data is Dictionary and data.has("save_version") and _whole_number(data["save_version"]) and int(data["save_version"]) > VERSION:
		return {"status": "future"}
	if not validate(data).is_empty():
		return {"status": "corrupt"}
	return {"status": "ok", "snapshot": data}


func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and value == int(value)


func _absolute(file_path: String) -> String:
	return ProjectSettings.globalize_path(file_path)

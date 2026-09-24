extends SceneTree

const STORE_SCRIPT = preload("res://scripts/progression/checkpoint_store.gd")
const ROOT := "res://output/S5/save_store_test.json"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: CheckpointStore = STORE_SCRIPT.new(ROOT)
	var missing := store.read_checkpoint()
	_check("SAVE_MISSING", missing["status"] == "missing")
	var first := store.initial_snapshot()
	_check("SAVE_SCHEMA", store.validate(first).is_empty())
	_check("SAVE_FIRST_WRITE", store.write_checkpoint(first)["ok"])
	var second := first.duplicate(true)
	second["checkpoint_room_id"] = "R02"
	second["completed_rooms"] = ["R01"]
	_check("SAVE_SECOND_WRITE", store.write_checkpoint(second)["ok"])
	var read_second := store.read_checkpoint()
	_check("SAVE_CURRENT", read_second["status"] == "ok" and read_second["snapshot"]["checkpoint_room_id"] == "R02")
	var backup: CheckpointStore = STORE_SCRIPT.new(ROOT + ".bak")
	_check("SAVE_BACKUP_PREVIOUS", backup.read_checkpoint()["status"] == "ok" and backup.read_checkpoint()["snapshot"]["checkpoint_room_id"] == "R01")
	var malformed := FileAccess.open(ROOT, FileAccess.WRITE)
	malformed.store_string("{broken")
	malformed.close()
	var recovered := store.read_checkpoint()
	_check("SAVE_CORRUPT_BACKUP", recovered["status"] == "backup" and recovered["snapshot"]["checkpoint_room_id"] == "R01")
	_check("SAVE_CORRUPT_GUARD", not store.write_checkpoint(second)["ok"] and FileAccess.get_file_as_string(ROOT) == "{broken")
	var repaired := store.write_checkpoint(second, true)
	_check("SAVE_EXPLICIT_REPAIR", repaired["ok"] and FileAccess.get_file_as_string(ROOT + ".rejected") == "{broken" and store.read_checkpoint()["status"] == "ok")
	var duplicate := second.duplicate(true)
	duplicate["checkpoint_room_id"] = "R05"
	duplicate["learned_abilities"] = ["sticky_spit", "elastic_shell", "slime_spikes"]
	duplicate["unlocked_slots"] = 2
	duplicate["collected_cores"] = ["r04_core"]
	duplicate["completed_rooms"] = ["R01", "R02", "R03", "R04"]
	duplicate["loadout"] = ["sticky_spit", "sticky_spit"]
	_check("SAVE_DUPLICATE_SKILL", store.validate(duplicate) == "Навык продублирован" and not store.write_checkpoint(duplicate)["ok"])
	var foreign := duplicate.duplicate(true)
	foreign["loadout"] = ["res://unknown.gd", ""]
	_check("SAVE_UNKNOWN_SKILL", store.validate(foreign) == "Неизвестный навык в слоте")
	var good_before := FileAccess.get_file_as_string(ROOT)
	var temp_dir_result := DirAccess.make_dir_absolute(ProjectSettings.globalize_path(ROOT + ".tmp"))
	var failed_write := store.write_checkpoint(first)
	_check("SAVE_WRITE_FAILURE", temp_dir_result == OK and not failed_write["ok"] and FileAccess.get_file_as_string(ROOT) == good_before)
	if temp_dir_result == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT + ".tmp"))
	var future: CheckpointStore = STORE_SCRIPT.new(ROOT + ".future")
	var future_data := first.duplicate(true)
	future_data["save_version"] = 99
	var future_file := FileAccess.open(future.path, FileAccess.WRITE)
	future_file.store_string(JSON.stringify(future_data))
	future_file.close()
	_check("SAVE_FUTURE", future.read_checkpoint()["status"] == "future")
	for suffix: String in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".future"]:
		var target: String = ROOT + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("SAVE_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(name: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + name)
	if not passed:
		failures += 1

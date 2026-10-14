extends SceneTree


func _initialize() -> void:
	var source: PackedScene = load("res://scenes/keepers/keepers_facility.tscn") as PackedScene
	var dungeon: Node3D = source.instantiate() as Node3D
	dungeon.name = "SlimeDungeon"
	dungeon.set_script(load("res://scripts/dungeon/dungeon_route.gd"))
	dungeon.set("layout_script",load("res://scripts/dungeon/dungeon_layout.gd"))
	dungeon.set("geometry_script",load("res://scripts/dungeon/dungeon_geometry.gd"))
	dungeon.set("combat_script",load("res://scripts/dungeon/dungeon_combat.gd"))
	dungeon.set("hud_script",load("res://scripts/dungeon/dungeon_hud.gd"))
	var player: Node = dungeon.get_node("SlimePlayer")
	player.set_script(load("res://scripts/dungeon/dungeon_player.gd"))
	var packed: PackedScene = PackedScene.new()
	var result: Error = packed.pack(dungeon)
	if result==OK:
		DirAccess.make_dir_recursive_absolute("res://scenes/dungeon")
		result = ResourceSaver.save(packed,"res://scenes/dungeon/dungeon_route.tscn")
	dungeon.free()
	print("DUNGEON_SCENE_BUILD result=%d" % result)
	quit(0 if result==OK else 1)

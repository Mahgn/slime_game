extends SceneTree

# Rebuilds the editable Cyclops geometry for the opening route.
# Run only when intentionally replacing scenes/opening_blockout.tscn.

const OUTPUT := "res://scenes/opening_blockout.tscn"

const BLOCKS := [
	# name, centre, size, palette key
	["LandingBasin", Vector3(0, -0.3, 7), Vector3(12, 0.6, 13), "floor"],
	["StartNook", Vector3(4.8, -0.3, 3), Vector3(3.8, 0.6, 4.5), "floor"],
	["SafetyFloor", Vector3(0, -3.3, -9), Vector3(18, 0.6, 37), "deep"],
	["WestWallBasin", Vector3(-7.2, 4.5, 7), Vector3(2.4, 9, 15), "wall"],
	["EastWallBasin", Vector3(7.2, 4.5, 7), Vector3(2.4, 9, 15), "wall"],
	["SouthWall", Vector3(0, 4.5, 14.5), Vector3(17, 9, 2), "wall"],
	["WestWallClimb", Vector3(-8.1, 5.0, -10), Vector3(2.6, 12, 33), "wall"],
	["EastWallClimbLower", Vector3(8.1, 5.0, -17), Vector3(2.6, 12, 19), "wall"],
	["EastWallClimbUpper", Vector3(8.1, 5.0, 4.5), Vector3(2.6, 12, 4), "wall"],
	["EastWallOverlookSill", Vector3(8.1, 1.5, -2.5), Vector3(2.6, 5, 10), "wall"],
	["Step01", Vector3(-2.5, 0.25, -0.3), Vector3(4.2, 0.5, 3.0), "ledge"],
	["Step02", Vector3(-4.0, 0.80, -3.0), Vector3(3.6, 0.5, 2.8), "ledge"],
	["Step03", Vector3(-1.4, 1.35, -5.5), Vector3(4.0, 0.5, 2.8), "ledge"],
	["Step04", Vector3(1.2, 1.90, -8.2), Vector3(4.0, 0.5, 3.0), "ledge"],
	["Overlook", Vector3(1.5, 1.90, -11.5), Vector3(8.0, 0.5, 4.0), "floor"],
	["UpperStep", Vector3(0, 2.35, -17.0), Vector3(6.0, 0.5, 7.0), "ledge"],
	["UpperLanding", Vector3(0, 2.35, -21.0), Vector3(8.0, 0.5, 3.0), "floor"],
	["UpperEndWallWest", Vector3(-6, 5.0, -24.0), Vector3(4, 10, 2), "wall"],
	["UpperEndWallEast", Vector3(6, 5.0, -24.0), Vector3(4, 10, 2), "wall"],
	# Four Cyclops slabs leave a daylight hole above the starting basin.
	["SkylightWest", Vector3(-5.0, 9.4, 7.0), Vector3(5.0, 0.9, 12.0), "roof"],
	["SkylightEast", Vector3(5.0, 9.4, 7.0), Vector3(5.0, 0.9, 12.0), "roof"],
	["SkylightNorth", Vector3(0, 9.4, 2.0), Vector3(5.0, 0.9, 2.0), "roof"],
	["SkylightSouth", Vector3(0, 9.4, 12.0), Vector3(5.0, 0.9, 2.0), "roof"],
	# R02-R09: one climb around the shaft, with a visible return above the start.
	["R02Gallery", Vector3(0, 2.35, -30), Vector3(10, 0.5, 12), "floor"],
	["R03Observation", Vector3(0, 2.95, -40), Vector3(10, 0.5, 8), "floor"],
	["R03EastWalk", Vector3(5.5, 2.95, -40), Vector3(11, 0.5, 4), "ledge"],
	["R04HelmetNest", Vector3(16, 2.95, -40), Vector3(14, 0.5, 12), "floor"],
	["R04ApproachStep", Vector3(22.3, 3.75, -35), Vector3(4.5, 0.5, 4.5), "ledge"],
	["R05CombatShelf", Vector3(28, 4.55, -29), Vector3(12, 0.5, 10), "ledge"],
	["R05LongJumpShelf", Vector3(28, 5.35, -19), Vector3(10, 0.5, 6), "ledge"],
	["R06UpperLedge", Vector3(27, 5.95, -9), Vector3(12, 0.5, 12), "floor"],
	["R07Overlook", Vector3(14, 6.55, -2), Vector3(14, 0.5, 8), "floor"],
	["R08Fork", Vector3(3, 7.15, -8), Vector3(12, 0.5, 6), "floor"],
	["R08LongRoute", Vector3(-3.5, 7.15, -16), Vector3(3.5, 0.5, 10), "ledge"],
	["R08ShortStepA", Vector3(6, 7.15, -14), Vector3(3.5, 0.5, 3.5), "ledge"],
	["R08ShortStepB", Vector3(6, 7.15, -19.5), Vector3(3.5, 0.5, 3.5), "ledge"],
	["R08Merge", Vector3(0, 7.15, -24), Vector3(12, 0.5, 6), "floor"],
	["R09FinalArena", Vector3(0, 7.15, -33), Vector3(12, 0.5, 10), "floor"],
	["R09ExitLanding", Vector3(0, 7.15, -47), Vector3(10, 0.5, 6), "floor"],
	["ExtendedPitFloor", Vector3(13, -4, -20), Vector3(48, 0.6, 70), "deep"],
	["NewWestWall", Vector3(-9, 5, -38), Vector3(2, 18, 28), "wall"],
	["NewEastWall", Vector3(36, 5, -20), Vector3(2, 18, 68), "wall"],
	["NewNorthWall", Vector3(13, 5, -53), Vector3(48, 18, 2), "wall"],
	["R02WestWall", Vector3(-6, 5.5, -30), Vector3(1, 6, 12), "wall"],
	["R03WestWall", Vector3(-6, 5.5, -40), Vector3(1, 6, 8), "wall"],
]

const COLORS := {
	"floor": Color(0.34, 0.34, 0.31),
	"ledge": Color(0.37, 0.36, 0.32),
	"wall": Color(0.24, 0.26, 0.25),
	"deep": Color(0.10, 0.12, 0.13),
	"roof": Color(0.18, 0.20, 0.20),
}


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var root := Node3D.new()
	root.name = "OpeningBlockout"
	var materials: Dictionary = {}
	for key in COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[key]
		material.roughness = 0.91
		materials[key] = material
	for record in BLOCKS:
		var block := CyclopsBlock.new()
		block.name = record[0]
		root.add_child(block)
		block.owner = root
		block.position = record[1]
		block.materials.append(materials[record[3]])
		var volume := ConvexVolume.new()
		volume.init_block(AABB(-record[2] * 0.5, record[2]), Transform2D.IDENTITY, 0)
		block.mesh_vector_data = volume.to_mesh_vector_data()
	var scene := PackedScene.new()
	var packed := scene.pack(root)
	if packed != OK:
		push_error("Could not pack Cyclops opening: %s" % packed)
		quit(1)
		return
	var saved := ResourceSaver.save(scene, OUTPUT)
	if saved != OK:
		push_error("Could not save Cyclops opening: %s" % saved)
		quit(1)
		return
	print("Saved ", OUTPUT, " with ", BLOCKS.size(), " Cyclops blocks")
	quit()

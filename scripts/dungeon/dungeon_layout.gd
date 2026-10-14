extends RefCounted

const BASE: Script = preload("res://scripts/keepers/keepers_run_layout.gd")
const PASSAGE_WIDTH: float = 3.4
const REGION_TITLES: Dictionary = {
	"brood": "Выводные залы", "garden": "Грибные сады", "water": "Водосбор",
	"service": "Служебные галереи", "trial": "Верхний рубеж"
}


static func rooms() -> Dictionary:
	var old: Dictionary = BASE.rooms()
	var result: Dictionary = {}
	for id: String in _specs():
		var spec: Dictionary = _specs()[id]
		var room: Dictionary = old[id].duplicate(true)
		room.merge(spec, true)
		room.region_title = REGION_TITLES[spec.region]
		room.footprint = PackedVector2Array([
			Vector2(-spec.half.x, -spec.half.y), Vector2(spec.half.x, -spec.half.y),
			Vector2(spec.half.x, spec.half.y), Vector2(-spec.half.x, spec.half.y)])
		room.spawn = spec.center + spec.spawn
		room.enemy_spawns = _global(spec.enemies, spec.center)
		room.walk_points = _global(spec.walk, spec.center)
		room.links = []
		room.exits = []
		room.ports = {}
		room.port_paths = {}
		room.erase("secret_exit")
		room.erase("secret")
		room.erase("reward")
		room.erase("lore")
		if id == "archive":
			room.secret = true
			room.reward = "core"
			room.lore = "Второй слот открыт. Его содержимое сохранится до конца этой попытки."
			room.reward_position = spec.center + Vector3(-1.5, 0, -1)
		result[id] = room
	result.summit.exit_point = result.summit.center + Vector3(0, 1, -7)
	for link: Dictionary in connections():
		for side: int in 2:
			var id: String = link.a if side == 0 else link.b
			var neighbor: String = link.b if side == 0 else link.a
			var at: Vector3 = link.path[side]
			var normal: Vector3 = (link.path[1-side] - at).normalized()
			result[id].ports[neighbor] = {"position": at, "normal": normal, "width": PASSAGE_WIDTH}
			result[id].links.append(neighbor)
			result[id].exits.append(neighbor)
			result[id].port_paths[neighbor] = [at - normal * 2.2, at]
	return result


static func _global(points: Array, origin: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		result.append(origin + point)
	return result


static func connections() -> Array:
	var result: Array = []
	for edge: Array in [
		["entry", "spring", Vector3(-8,0,14), Vector3(-9,0,14)],
		["entry", "barracks", Vector3(8,0,14), Vector3(9,0,14)],
		["entry", "junction", Vector3(0,0,8), Vector3(0,0,6)],
		["junction", "furnace", Vector3(-5,0,-6), Vector3(-5,0,-9)],
		["junction", "cistern", Vector3(5.5,0,-6), Vector3(5.5,0,-10)],
		["furnace", "cistern", Vector3(-3,0,-18), Vector3(4,0,-18)],
		["furnace", "hub", Vector3(-9,0,-27), Vector3(-9,0,-30)],
		["cistern", "hub", Vector3(9,0,-26), Vector3(9,0,-30)],
		["hub", "armory", Vector3(-8,0,-50), Vector3(-8,0,-52)],
		["hub", "garden", Vector3(7,0,-50), Vector3(7,0,-52)],
		["armory", "archive", Vector3(-22,0,-59), Vector3(-24,0,-59)],
		["armory", "summit", Vector3(-10,0,-66), Vector3(-10,0,-73)],
		["garden", "summit", Vector3(8.5,0,-70), Vector3(8.5,0,-73)]
	]:
		result.append({"a": edge[0], "b": edge[1], "path": [edge[2], edge[3]], "width": PASSAGE_WIDTH})
	return result


static func _specs() -> Dictionary:
	return {
		"entry": {"title":"Распределительный зал", "region":"brood", "subtitle":"Мастер принял тебя за авантюриста. Найди дорогу к своей семье.", "center":Vector3(0,0,14), "half":Vector2(8,6), "spawn":Vector3(0,0,3), "waves":[], "enemies":[], "walk":[Vector3(0,0,3),Vector3(0,0,0),Vector3(-5,0,0),Vector3(5,0,0),Vector3(0,0,-4)]},
		"spring": {"title":"Гнездовые камеры", "region":"brood", "subtitle":"Паучий секрет удерживает добычу и открытые приводы. E — поглотить или пройти мимо.", "center":Vector3(-13,0,14), "half":Vector2(4,4), "spawn":Vector3(2,0,0), "waves":[["sticky"]], "enemies":[Vector3(-1,0,-1)], "walk":[Vector3(2,0,0),Vector3(0,0,0),Vector3(-1,0,-1)]},
		"barracks": {"title":"Кормовой цех", "region":"brood", "subtitle":"Жуки разъедают корку пищи. Их кислота откроет органический служебный лаз.", "center":Vector3(13,0,14), "half":Vector2(4,4), "spawn":Vector3(-2,0,0), "waves":[["acid"]], "enemies":[Vector3(1,0,-1)], "walk":[Vector3(-2,0,0),Vector3(0,0,0),Vector3(1,0,-1)]},
		"junction": {"title":"Зал выпуска", "region":"brood", "subtitle":"За решёткой — сады и водосбор. Дождись открытия или удержи привод клеем.", "center":Vector3(0,0,0), "half":Vector2(8,6), "spawn":Vector3(0,0,4), "waves":[], "enemies":[], "walk":[Vector3(0,0,4),Vector3(0,0,1),Vector3(0,0,-2),Vector3(-5,0,-2),Vector3(-5,0,-4),Vector3(5.5,0,-4),Vector3(5.5,0,-2)]},
		"furnace": {"title":"Каменные гряды", "region":"garden", "subtitle":"Здесь растёт пища для выводных залов. Сады и водосбор сходятся в служебных галереях.", "center":Vector3(-13,0,-18), "half":Vector2(10,9), "spawn":Vector3(8,0,7), "waves":[["acid","acid"]], "enemies":[Vector3(2,0,-3),Vector3(5,0,3)], "walk":[Vector3(8,0,7),Vector3(5,0,4),Vector3(5,0,0),Vector3(5,0,-6),Vector3(4,0,-7),Vector3(8,0,0),Vector3(2,0,-3)]},
		"cistern": {"title":"Резервуар и шлюзы", "region":"water", "subtitle":"Вода питает гряды и гнёзда. Сухие мостки безопасны; в чаше тебя сносит поток.", "center":Vector3(12,0,-18), "half":Vector2(8,8), "spawn":Vector3(-5.5,0,6), "waves":[["sticky","sticky"]], "enemies":[Vector3(-4.5,0,-4),Vector3(4.5,0,3)], "walk":[Vector3(-5.5,0,6),Vector3(-4.5,0,3),Vector3(-4.5,0,-4),Vector3(0,0,-6),Vector3(4.5,0,-4),Vector3(4.5,0,4),Vector3(0,0,6),Vector3(0,-0.55,0)]},
		"hub": {"title":"Распределитель обслуживания", "region":"service", "subtitle":"Слуги доставляют корм, воду и запчасти. Оба пути ведут к верхнему рубежу.", "center":Vector3(0,0,-40), "half":Vector2(11,10), "spawn":Vector3(-9,0,8), "waves":[["acid","sticky"]], "enemies":[Vector3(-5,0,-5),Vector3(5,0,-5)], "walk":[Vector3(-9,0,8),Vector3(-5,0,5),Vector3(-5,0,0),Vector3(-5,0,-6),Vector3(-5,0,-8),Vector3(-8,0,-8),Vector3(5,0,-7),Vector3(7,0,-8),Vector3(7,0,0),Vector3(5,0,5),Vector3(9,0,8)]},
		"armory": {"title":"Мастерская слуг", "region":"service", "subtitle":"Здесь чинят устройства испытания. В боковой кладовой можно открыть второй слот.", "center":Vector3(-13,0,-59), "half":Vector2(9,7), "spawn":Vector3(5,0,5), "waves":[["sticky"]], "enemies":[Vector3(3,0,-3)], "walk":[Vector3(5,0,5),Vector3(0,0,0),Vector3(0,0,-5),Vector3(3,0,-5),Vector3(-6,0,0),Vector3(5,0,0)]},
		"garden": {"title":"Зал переработки", "region":"service", "subtitle":"Органические остатки возвращаются на грибные гряды. Настил обходит размытый канал.", "center":Vector3(12,0,-61), "half":Vector2(7,9), "spawn":Vector3(-5,0,7), "waves":[["acid"]], "enemies":[Vector3(3,0,-5)], "walk":[Vector3(-5,0,7),Vector3(0,0,6),Vector3(4.6,0,5),Vector3(4.6,0,0),Vector3(4.6,0,-5),Vector3(-1.5,0,-6)]},
		"archive": {"title":"Кладовая мастера", "region":"service", "subtitle":"E — принять ядро и открыть второй слот. Выбор пары — Tab вне боя.", "center":Vector3(-29,0,-59), "half":Vector2(5,5), "spawn":Vector3(3,0,0), "waves":[], "enemies":[], "walk":[Vector3(3,0,0),Vector3(0,0,0),Vector3(-1.5,0,-1)]},
		"summit": {"title":"Главное испытание", "region":"trial", "subtitle":"Пройди испытание у старого входа. Мастер снимет привязку, и путь к своим откроется.", "center":Vector3(-2,0,-83), "half":Vector2(13,10), "spawn":Vector3(-8,0,7), "waves":[["guardian"]], "enemies":[Vector3(0,1,-5)], "walk":[Vector3(-8,0,7),Vector3(-4,0,5),Vector3(0,0,3),Vector3(7,0,5),Vector3(0,0.5,-0.5),Vector3(0,1,-3),Vector3(0,1,-7)]}
	}

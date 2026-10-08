extends RefCounted

# A single service building: fuel and water feed the boiler, then two service
# routes join at the sluice. Coordinates describe construction, not teleport gates.
const BASE = preload("res://scripts/keepers/keepers_run_layout.gd")
const WIDTH := 3.4

static func rooms() -> Dictionary:
	var source: Dictionary = BASE.rooms()
	var result: Dictionary = {}
	var specs := _specs()
	for id: String in specs:
		var spec: Dictionary = specs[id]
		var room: Dictionary = source[id].duplicate(true)
		room.merge(spec, true)
		room.footprint = PackedVector2Array([Vector2(-spec.half.x,-spec.half.y),Vector2(spec.half.x,-spec.half.y),Vector2(spec.half.x,spec.half.y),Vector2(-spec.half.x,spec.half.y)])
		room.spawn = spec.center + spec.spawn
		room.enemy_spawns = _global(spec.enemies, spec.center)
		room.walk_points = _global(spec.walk, spec.center)
		room.links = []
		room.exits = []
		room.ports = {}
		room.port_paths = {}
		room.erase("secret_exit")
		room.reward_position = spec.center + Vector3(-1.5,0,-1)
		result[id] = room
	result.summit.exit_point = specs.summit.center + Vector3(0,1,-7)
	result.entry.secret_exit = "spring"
	result.armory.secret_exit = "archive"
	for link: Dictionary in connections():
		for side in 2:
			var id: String = link.a if side == 0 else link.b
			var neighbor: String = link.b if side == 0 else link.a
			var at: Vector3 = link.path[side]
			var normal: Vector3 = (link.path[1-side]-at).normalized()
			result[id].ports[neighbor] = {"position":at,"normal":normal,"width":WIDTH}
			result[id].links.append(neighbor)
			result[id].exits.append(neighbor)
			# Navigation checks every candidate against actual support and walls.
			result[id].port_paths[neighbor] = [at-normal*2.2, at]
	return result

static func _global(points: Array, origin: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		result.append(origin+point)
	return result

static func connections() -> Array:
	var result: Array = []
	for edge: Array in [
		["entry","furnace",Vector3(-5,0,6),Vector3(-5,0,5)],
		["entry","cistern",Vector3(5.5,0,6),Vector3(5.5,0,5)],
		["furnace","hub",Vector3(-9,0,-13),Vector3(-9,0,-14)],
		["cistern","pump_room",Vector3(11,0,-11),Vector3(11,0,-12)],
		["pump_room","hub",Vector3(3,0,-24),Vector3(1,0,-24)],
		["hub","armory",Vector3(-12,0,-34),Vector3(-12,0,-35)],
		["hub","garden",Vector3(1,0,-31),Vector3(3,0,-31)],
		["armory","summit",Vector3(-12,0,-49),Vector3(-12,0,-50)],
		["garden","summit",Vector3(8.5,0,-47),Vector3(8.5,0,-50)],
		["entry","spring",Vector3(-8,0,13),Vector3(-9,0,13)],
		["armory","archive",Vector3(-21,0,-43),Vector3(-22,0,-43)],
	]:
		result.append({"a":edge[0],"b":edge[1],"path":[edge[2],edge[3]],"width":WIDTH})
	return result

static func _specs() -> Dictionary:
	return {
		"entry":{"title":"Приёмный двор водосбора","subtitle":"Грузовой спуск. Уголь уходит влево, вода — вправо. Поглоти Плевуна: удерживай E.","center":Vector3(0,0,12),"half":Vector2(8,6),"spawn":Vector3(0,0,2),"waves":[["spitter"],["spitter","armorer"]],"enemies":[Vector3(0,0,-2),Vector3(4,0,0),Vector3(-4,0,0)],"walk":[Vector3(0,0,4),Vector3(0,0,0),Vector3(-5,0,0),Vector3(-5,0,-4),Vector3(5.5,0,-4),Vector3(5.5,0,0)]},
		"furnace":{"title":"Угольная топочная","subtitle":"Решётки шипят перед выбросом пара. Дождись паузы или обойди их по широкому проходу.","center":Vector3(-12,0,-4),"half":Vector2(10,9),"spawn":Vector3(7,0,6),"waves":[["armorer","spitter"],["armorer","spitter","spitter"]],"enemies":[Vector3(3,0,-4),Vector3(7,0,-4),Vector3(0,0,3)],"walk":[Vector3(7,0,6),Vector3(7,0,2),Vector3(7,0,-4),Vector3(3,0,-6),Vector3(3,0,2),Vector3(-3,0,2)]},
		"cistern":{"title":"Отстойник","subtitle":"Осевшая вода собирается внизу. У стен есть обход; из чаши ведёт пологий подъём.","center":Vector3(11,0,-3),"half":Vector2(8,8),"spawn":Vector3(-5.5,0,6),"waves":[["spitter","spitter"],["armorer","spitter"]],"enemies":[Vector3(-4.5,0,-4),Vector3(4.5,0,-4),Vector3(4.5,0,3)],"walk":[Vector3(-5.5,0,6),Vector3(-4.5,0,3),Vector3(-4.5,0,-4),Vector3(0,0,-6),Vector3(4.5,0,-4),Vector3(4.5,0,4),Vector3(0,0,6),Vector3(0,-0.55,0)]},
		"pump_room":{"title":"Насосная","subtitle":"Привод опускается после металлического щелчка. Обходи противовес или проходи после удара.","center":Vector3(11,0,-20),"half":Vector2(8,8),"spawn":Vector3(0,0,6),"waves":[["armorer","spitter"],["sprout","spitter"]],"enemies":[Vector3(-4,0,-4),Vector3(4,0,-4),Vector3(4,0,3)],"walk":[Vector3(0,0,6),Vector3(-4.5,0,4),Vector3(-4.5,0,0),Vector3(-4.5,0,-4),Vector3(0,0,-5),Vector3(4.5,0,-4),Vector3(4.5,0,4)]},
		"hub":{"title":"Сердце котельной","subtitle":"Топочная и насосы питают общий котёл. За ним — мастерская и аварийный коллектор.","center":Vector3(-10,0,-24),"half":Vector2(11,10),"spawn":Vector3(1,0,8),"waves":[["sprout","spitter"],["armorer","sprout","spitter"]],"enemies":[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(6,0,3)],"walk":[Vector3(1,0,8),Vector3(-5,0,5),Vector3(-5,0,0),Vector3(-5,0,-6),Vector3(-2,0,-7),Vector3(5,0,-7),Vector3(8,0,-7),Vector3(7,0,0),Vector3(5,0,5)]},
		"armory":{"title":"Ремонтная мастерская","subtitle":"Запасные детали заслонки. В стенной кладовой остались записи смотрителя.","route_hint":"Через мастерскую","center":Vector3(-12,0,-42),"half":Vector2(9,7),"spawn":Vector3(0,0,5),"waves":[["armorer","armorer"],["sprout","spitter"]],"enemies":[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(4,0,2)],"walk":[Vector3(0,0,5),Vector3(0,0,0),Vector3(0,0,-5),Vector3(-5,0,0),Vector3(-6,0,-1),Vector3(5,0,0)]},
		"garden":{"title":"Аварийный коллектор","subtitle":"Протечка размыла старую кладку. Перепрыгни провал или обойди по восточному настилу.","route_hint":"Через коллектор","center":Vector3(10,0,-38),"half":Vector2(7,9),"spawn":Vector3(-5,0,7),"waves":[["sprout","spitter"],["armorer","sprout"]],"enemies":[Vector3(-3,0,-5),Vector3(3,0,-5),Vector3(3,0,5)],"walk":[Vector3(-5,0,7),Vector3(0,0,6),Vector3(4.6,0,5),Vector3(4.6,0,0),Vector3(4.6,0,-5),Vector3(-1.5,0,-6),Vector3(-3,0,-5)]},
		"summit":{"title":"Зал верхней заслонки","subtitle":"Приводы поднимают заслонку. Победи Стража и поднимись к следам стаи.","center":Vector3(-2,0,-60),"half":Vector2(13,10),"spawn":Vector3(-8,0,7),"waves":[["armorer","spitter"],["guardian"]],"enemies":[Vector3(-4,1,-5),Vector3(4,1,-5),Vector3(0,1,-5)],"walk":[Vector3(-8,0,7),Vector3(-4,0,5),Vector3(0,0,3),Vector3(7,0,5),Vector3(10.5,0,7),Vector3(0,0.5,-0.5),Vector3(0,1,-3),Vector3(-4,1,-5),Vector3(0,1,-7),Vector3(4,1,-5)]},
		"spring":{"title":"Осмотровая ниша","subtitle":"За грузовой кладкой скрыта старая труба. Здесь осталась упругая оболочка.","center":Vector3(-13,0,13),"half":Vector2(4,3),"spawn":Vector3(2,0,0),"waves":[],"enemies":[],"walk":[Vector3(2,0,0),Vector3(0,0,0),Vector3(-1.5,0,-1)]},
		"archive":{"title":"Кладовая мастера","subtitle":"Слизевое ядро среди журналов ремонта. E — открыть второй слот.","center":Vector3(-27,0,-43),"half":Vector2(5,5),"spawn":Vector3(3,0,0),"waves":[],"enemies":[],"walk":[Vector3(3,0,0),Vector3(0,0,0),Vector3(-1.5,0,-1)]}
	}

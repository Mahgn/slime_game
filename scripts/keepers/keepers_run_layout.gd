extends RefCounted

# Authored graph, not a generator. Runtime state belongs to KeepersRun.
static func rooms() -> Dictionary:
	return {
		"entry": {"title": "Служебный спуск", "theme": "entry", "subtitle": "Сквозняк идёт сверху. Найди проход через котельные.", "exits": ["junction"], "waves": []},
		"junction": {"title": "Приёмный водосбор", "theme": "junction", "subtitle": "Победи Плевуна. Удерживай E возле его следа, чтобы поглотить навык.", "exits": ["furnace", "cistern"], "secret_exit": "spring", "waves": [["spitter"], ["spitter", "spitter"]]},
		"furnace": {"title": "Угольная топочная", "theme": "furnace", "subtitle": "Бей панцирника после его выпада. Не стой перед Плевунами.", "route_hint": "Тёплый путь · ближний бой", "exits": ["cinder_gallery"], "waves": [["armorer", "spitter"], ["spitter", "spitter"], ["armorer", "spitter"]]},
		"cistern": {"title": "Холодный отстойник", "theme": "cistern", "subtitle": "Двигайся поперёк плевков. Между залпами можно сблизиться.", "route_hint": "Холодный путь · дальние атаки", "exits": ["pump_room"], "waves": [["spitter", "spitter"], ["armorer", "spitter"], ["spitter", "armorer"]]},
		"cinder_gallery": {"title": "Галерея углей", "theme": "cinder_gallery", "subtitle": "Разделяй защитников. Липкий плевок задержит того, кто подходит сбоку.", "exits": ["hub"], "waves": [["armorer", "spitter"], ["armorer", "armorer"], ["armorer", "spitter", "spitter"]]},
		"pump_room": {"title": "Старая насосная", "theme": "pump_room", "subtitle": "Три направления атаки. Меняй место после каждого залпа.", "exits": ["hub"], "waves": [["spitter", "spitter"], ["armorer", "armorer"], ["spitter", "armorer", "spitter"]]},
		"hub": {"title": "Сердце котельной", "theme": "hub", "subtitle": "Уходи в сторону от линии шипов. Оба пути ведут к верхней заслонке.", "exits": ["armory", "garden"], "secret_exit": "archive", "waves": [["sprout", "spitter"], ["armorer", "sprout"]]},
		"armory": {"title": "Старая оружейная", "theme": "armory", "subtitle": "Не отдавай угол панцирникам. Отступай в свободный центр.", "route_hint": "Через оружейную · панцирники", "exits": ["barracks"], "waves": [["armorer", "armorer"], ["spitter", "armorer"], ["sprout", "armorer"]]},
		"garden": {"title": "Заросшая галерея", "theme": "garden", "subtitle": "Не беги вдоль трещин. Шипы требуют бокового уклонения.", "route_hint": "Через оранжерею · шипы", "exits": ["root_cellar"], "waves": [["sprout", "spitter"], ["sprout", "armorer"], ["spitter", "sprout"]]},
		"barracks": {"title": "Казарма смотрителей", "theme": "barracks", "subtitle": "Собери преследователей перед собой. Хлыст задевает несколько близких целей.", "exits": ["gauntlet"], "waves": [["armorer", "sprout"], ["armorer", "armorer"], ["armorer", "sprout", "spitter"]]},
		"root_cellar": {"title": "Корневой погреб", "theme": "root_cellar", "subtitle": "Ростки держат дистанцию. Шипы и хлыст помогут разорвать их строй.", "exits": ["gauntlet"], "waves": [["sprout", "sprout"], ["armorer", "spitter"], ["sprout", "armorer", "spitter"]]},
		"gauntlet": {"title": "Палата печатей", "theme": "gauntlet", "subtitle": "Последний общий рубеж. Сначала убери тех, кто мешает уклоняться.", "exits": ["summit"], "waves": [["spitter", "armorer", "spitter"], ["sprout", "armorer", "spitter"], ["armorer", "sprout", "armorer"]]},
		"summit": {"title": "Верхняя заслонка", "theme": "summit", "subtitle": "За Стражем — путь к своим. Следи за полосой, дугой и кругом его атак.", "exits": [], "waves": [["spitter", "spitter"], ["guardian"]]},
		"spring": {"title": "Ниша смотрителя", "theme": "spring", "subtitle": "Здесь прятался панцирник. Его оболочка может пригодиться раньше времени.", "secret": true, "exits": [], "waves": [], "reward": "shell", "lore": "Свежий след стаи тянется вверх по старой трубе."},
		"archive": {"title": "Забытый архив", "theme": "archive", "subtitle": "В глубине светится слизевое ядро. Оно откроет второй слот.", "secret": true, "exits": [], "waves": [], "reward": "core", "lore": "Два отпечатка на полке. Свои уже прошли через верхнюю заслонку."},
	}

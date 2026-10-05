"use strict";

const STORAGE_KEY = "slizi-dungeon-map-v1";
const WORLD_WIDTH = 2400;
const WORLD_HEIGHT = 1600;
const CARD_WIDTH = 204;
const CARD_HEIGHT = 132;
const IsoMap = globalThis.IsoMap;

function room(id, code, title, type, minutes, x, y, summary, gameplay, story, humor, status = "prototype") {
  return { id, code, title, type, minutes, x, y, summary, gameplay, story, humor, notes: "", status };
}

const DEFAULT_PROJECT = {
  version: 1,
  title: "Слизи и Подземелье положенных подвигов",
  interludeMinutes: 20,
  floors: [
    {
      id: "floor-1", name: "Приёмное отделение", minutes: 45, designRevision: 4,
      goal: "Подъём вокруг шахты: хлыст, поглощение плевка, панциря и шипов, два слота и мост на второй этаж.",
      rooms: [
        room("r01", "R01", "Нижняя чаша", "entrance", 5, 100, 900, "Падение, свет сверху, широкие уступы.", "Освоить камеру мышью, движение и короткий прыжок; удержание пробела даёт более высокий.", "Слизи слышит стадо и видит закрытый люк высоко над собой.", "Голос: новый герой зарегистрирован; жалобы после выхода.", "prototype"),
        room("r02", "R02", "Галерея находок", "combat", 7, 370, 900, "Два Плевуна, хлыст, липкий плевок, К1.", "Прочитать подготовку выстрела, победить хлыстом, удержать E у остатка и применить новый навык на ПКМ.", "У старой починки остаётся метка слайма-ремонтника.", "Плевун сортирует трофеи по степени невостребованности.", "prototype"),
        room("r03", "R03", "Балкон наблюдения", "story", 3, 640, 900, "С высоты виден Панцирник и гнездо шлемов.", "Заранее увидеть защитную фазу следующего врага.", "Старинный экзамен давно заброшен, но местные живут по расписанию.", "Шлемы в гнезде разложены как награды за участие.", "prototype"),
        room("r04", "R04", "Гнездо шлемов", "combat", 5, 910, 900, "Панцирник, панцирь, старое ядро, К2.", "Победить после защиты, поглотить панцирь удержанием E и открыть второй слот Q.", "Старое ядро слайма сохранилось среди чужих шлемов.", "Панцирник носит больше шлемов, чем ему положено по технике безопасности.", "prototype"),
        room("r05", "R05", "Проход плевка", "puzzle", 7, 910, 600, "Плевун на полке и два обычных прыжка.", "Применить плевок на расстоянии, затем пройти уступы без нового движения.", "Слизь оказывается полезнее старой инструкции по обходу.", "Табличка: не плевать в канцелярию.", "prototype"),
        room("r06", "R06", "Верхний карниз", "combat", 4, 640, 600, "Росток и Плевун; слизевые шипы.", "Поглотить шипы и проверить сочетание с липким плевком.", "Внизу узнаются пройденные площадки.", "Росток пытается спрятаться за табличкой размером с него.", "prototype"),
        room("r07", "R07", "Смотровая площадка", "rest", 3, 370, 600, "Вид на точку падения, коллекция, К3.", "Передохнуть и выбрать два навыка через Tab.", "Короткая реплика Голоса и ремонтный знак без обязательной записки.", "На выходе висит табличка «ПО ЗАПИСИ».", "prototype"),
        room("r08", "R08", "Два обхода", "puzzle", 4, 100, 600, "Низкий проход со сжатием или два коротких прыжка, К4.", "Слева пройти под потолком и встретить Плевуна на выходе; справа прыгнуть по плитам. Маршруты сходятся.", "Слизи использует свою форму для обхода, а не получает новый навык.", "Табличка: только для лиц ростом со слизь.", "prototype"),
        room("r09", "R09", "Выходной пролёт", "combat", 7, 100, 300, "Панцирник, Плевун, канат и мост.", "Пройти смешанную встречу, ударить хлыстом по канату и перейти по мосту.", "Слизи поднялся, но поверхность ещё выше; Голос вежливо объявляет следующий этаж.", "Выход открыт. Приём посетителей временно продолжается.", "prototype")
      ]
    },
    {
      id: "floor-2", name: "Хозяйственный", minutes: 55,
      goal: "Следы прежних слаймов и применение навыков вне боя.",
      rooms: [
        room("f2-01", "F2-01", "Служебный вход", "entrance", 10, 80, 340, "Следы ремонтников.", "Осмотр и короткий обход.", "Слизи находит старые слизевые метки.", "Посторонним вход воспрещён. Сотрудникам тоже.", "plan"),
        room("f2-02", "F2-02", "Склад обходов", "puzzle", 18, 345, 340, "Задача с навыками.", "Использовать знакомый приём для открытия пути.", "Карта прежних слаймов спрятана среди инвентаря.", "Нарушение маршрута ведёт к кратчайшему пути.", "plan"),
        room("f2-03", "F2-03", "Комнаты смотрителей", "story", 17, 610, 340, "Почему подземелье работало.", "Исследование, встреча, новый боевой контекст.", "Голос называет карту несанкционированной.", "Вопросы к персоналу подавайте персоналу.", "plan"),
        room("f2-04", "F2-04", "Хозяйственный шлюз", "boss", 10, 875, 340, "Переход к машинам.", "Кульминация этажа — пока открытое решение.", "Путь наверх лежит через источник ловушек.", "", "plan")
      ]
    },
    {
      id: "floor-3", name: "Машинный", minutes: 60,
      goal: "Увидеть, как подземелье работает без хозяев, и остановить часть системы.",
      rooms: [
        room("f3-01", "F3-01", "Тепловой колодец", "entrance", 10, 80, 340, "Вход в машинный этаж.", "Исследование и ориентир подъёма.", "Ловушки получают питание снизу.", "", "plan"),
        room("f3-02", "F3-02", "Цех повторения", "combat", 20, 345, 340, "Испытание зациклилось.", "Новый боевой сценарий — конкретику спроектировать.", "Обитатели живут среди бесконечных упражнений.", "Перерыв начнётся после окончания перерыва.", "plan"),
        room("f3-03", "F3-03", "Главный привод", "puzzle", 20, 610, 340, "Первое отключение системы.", "Применить освоенные навыки в механизме.", "Голос инструкций впервые сомневается в правилах.", "Не выключать. Включено по ошибке.", "plan"),
        room("f3-04", "F3-04", "Подъёмный мост", "story", 10, 875, 340, "Открывается архивный путь.", "Переход и передышка.", "Слизи видит, что его действия изменили подземелье.", "", "plan")
      ]
    },
    {
      id: "floor-4", name: "Архивный", minutes: 60,
      goal: "Найти историю гильдии, ядер и потерянного приказа.",
      rooms: [
        room("f4-01", "F4-01", "Каталог входящих", "entrance", 10, 80, 340, "Архив встречает Слизи.", "Исследование и новый ориентир.", "Всё записано, но не там, где нужно.", "Вы уже подали заявление о входе, войдя.", "plan"),
        room("f4-02", "F4-02", "Память слаймов", "story", 20, 345, 340, "История старых помощников.", "Задача и находка — уточнить при проектировании.", "Ядра хранят знания прежних слаймов.", "", "plan"),
        room("f4-03", "F4-03", "Потерянный приказ", "puzzle", 20, 610, 340, "Раскрытие причины запертого выхода.", "Найти документ через игровое действие, не длинную записку.", "Приказ закрыть курс попал в ящик продолжения.", "Срочно. Хранить до востребования.", "plan"),
        room("f4-04", "F4-04", "Лестница к свету", "combat", 10, 875, 340, "Последняя преграда перед верхом.", "Короткое закрепление освоенного.", "Слизи знает, зачем нужно открыть выход.", "", "plan")
      ]
    },
    {
      id: "floor-5", name: "Верхний, выходной", minutes: 60,
      goal: "Открыть безопасный выход и вернуться к стаду.",
      rooms: [
        room("f5-01", "F5-01", "Верхний порог", "entrance", 10, 80, 340, "Свет поверхности рядом.", "Исследование и подготовка.", "Слизи снова слышит своё стадо.", "", "plan"),
        room("f5-02", "F5-02", "Последний экзамен", "combat", 20, 345, 340, "Проверка освоенных навыков.", "Сценарий боя определить после прототипов этажей 2–4.", "Смотритель отказывается принять приказ из другого ящика.", "Документ верный. Ящик неверный.", "plan"),
        room("f5-03", "F5-03", "Смотритель", "boss", 20, 610, 340, "Финальная встреча.", "Бой и решение с аварийным выходом.", "Слизи ломает замкнутое правило, а не всё подземелье.", "Поздравляем. Вы отменили порядок отмены.", "plan"),
        room("f5-04", "F5-04", "Большая лужа", "story", 10, 875, 340, "Возвращение домой.", "Тихий финал.", "Стадо ждёт на поверхности.", "", "plan")
      ]
    }
  ],
  links: []
};

for (const floor of DEFAULT_PROJECT.floors) {
  for (let index = 0; index < floor.rooms.length - 1; index += 1) {
    DEFAULT_PROJECT.links.push({ id: `link-${floor.rooms[index].id}-${floor.rooms[index + 1].id}`, from: floor.rooms[index].id, to: floor.rooms[index + 1].id, type: "main" });
  }
}
for (let index = 0; index < DEFAULT_PROJECT.floors.length - 1; index += 1) {
  const from = DEFAULT_PROJECT.floors[index].rooms.at(-1).id;
  const to = DEFAULT_PROJECT.floors[index + 1].rooms[0].id;
  DEFAULT_PROJECT.links.push({ id: `link-${from}-${to}`, from, to, type: "main" });
}
for (const floor of DEFAULT_PROJECT.floors) {
  floor.rooms.forEach((item, index) => { item.iso = IsoMap.normalize(null, item.id, index); });
}

const $ = (selector) => document.querySelector(selector);
const floorList = $("#floor-list");
const viewport = $("#map-viewport");
const world = $("#map-world");
const roomLayer = $("#room-layer");
const lineLayer = $("#line-layer");
const overviewMap = $("#overview-map");
const isoSvg = $("#iso-svg");
const isoScene = $("#iso-scene");
const inspector = $("#inspector");
const saveState = $("#save-state");

function copyDefault() { return JSON.parse(JSON.stringify(DEFAULT_PROJECT)); }
function withUpdatedFirstFloor(source) {
  const next = JSON.parse(JSON.stringify(source));
  const floorIndex = next.floors.findIndex((floor) => floor.id === "floor-1");
  if (floorIndex < 0) throw new Error("Первый этаж отсутствует.");
  const oldIds = new Set(next.floors[floorIndex].rooms.map((item) => item.id));
  next.links = next.links.filter((link) => !oldIds.has(link.from) && !oldIds.has(link.to));
  next.floors[floorIndex] = JSON.parse(JSON.stringify(DEFAULT_PROJECT.floors[0]));
  next.links.push(...DEFAULT_PROJECT.links.filter((link) => link.from.startsWith("r0") && link.to.startsWith("r0")));
  const nextRoom = next.floors[floorIndex + 1]?.rooms[0];
  if (nextRoom) next.links.push({ id: `link-r09-${nextRoom.id}`, from: "r09", to: nextRoom.id, type: "main" });
  return next;
}
function escapeHtml(value) { return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]); }
function uid(prefix) { return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`; }
function clamp(value, min, max) { return Math.min(max, Math.max(min, value)); }
function floorById(id) { return project.floors.find((floor) => floor.id === id); }
function roomById(id) { for (const floor of project.floors) { const found = floor.rooms.find((item) => item.id === id); if (found) return { room: found, floor }; } return null; }
function currentFloor() { return floorById(activeFloorId) || project.floors[0]; }
function selectedRoom() { return roomById(selectedRoomId)?.room || null; }
function statusText(status) { return status === "prototype" ? "Прототип" : status === "ready" ? "Готово" : "План"; }
function typeText(type) { return ({ entrance: "Вход", combat: "Бой", puzzle: "Задача", story: "История", boss: "Босс", rest: "Передышка" })[type] || "Комната"; }
function typeGlyph(type) { return ({ entrance: "↘", combat: "⚔", puzzle: "◇", story: "✦", boss: "♛", rest: "☼" })[type] || "•"; }

function validateProject(input) {
  if (!input || input.version !== 1 || !Array.isArray(input.floors) || input.floors.length < 1 || input.floors.length > 30 || !Array.isArray(input.links)) throw new Error("Это не файл карты версии 1.");
  const ids = new Set();
  const roomIds = new Set();
  for (const floor of input.floors) {
    if (typeof floor.id !== "string" || ids.has(floor.id) || typeof floor.name !== "string" || !Array.isArray(floor.rooms) || floor.rooms.length > 200) throw new Error("Повреждены данные этажа.");
    ids.add(floor.id);
    floor.name = floor.name.slice(0, 100);
    floor.goal = String(floor.goal ?? "").slice(0, 1000);
    floor.minutes = clamp(Number(floor.minutes) || 0, 0, 600);
    for (const [index, item] of floor.rooms.entries()) {
      if (typeof item.id !== "string" || ids.has(item.id) || typeof item.title !== "string" || !Number.isFinite(Number(item.x)) || !Number.isFinite(Number(item.y))) throw new Error("Повреждены данные комнаты.");
      ids.add(item.id);
      roomIds.add(item.id);
      item.code = String(item.code ?? "").slice(0, 30);
      item.title = item.title.slice(0, 100);
      item.type = ["entrance", "combat", "puzzle", "story", "boss", "rest"].includes(item.type) ? item.type : "story";
      item.status = ["prototype", "plan", "ready"].includes(item.status) ? item.status : "plan";
      item.minutes = clamp(Number(item.minutes) || 0, 0, 300);
      item.x = clamp(Number(item.x), 0, WORLD_WIDTH - CARD_WIDTH);
      item.y = clamp(Number(item.y), 0, WORLD_HEIGHT - CARD_HEIGHT);
      item.iso = IsoMap.normalize(item.iso, item.id, index);
      for (const field of ["summary", "gameplay", "story", "humor", "notes"]) item[field] = String(item[field] ?? "").slice(0, 3000);
    }
  }
  input.links = input.links.filter((link) => roomIds.has(link.from) && roomIds.has(link.to) && link.from !== link.to).slice(0, 2000).map((link) => ({ id: String(link.id || uid("link")), from: link.from, to: link.to, type: link.type === "optional" ? "optional" : "main" }));
  input.title = String(input.title ?? "Карта подземелья").slice(0, 100);
  input.interludeMinutes = clamp(Number(input.interludeMinutes) || 0, 0, 600);
  return input;
}

function loadProject() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) return validateProject(JSON.parse(saved));
  } catch (error) { console.warn("Не удалось прочитать сохранённую карту:", error); }
  return copyDefault();
}

let project = loadProject();
let activeFloorId = project.floors[0].id;
let activeView = "iso";
let selectedRoomId = null;
let view = { x: 0, y: 0, scale: 1 };
let isoCamera = { x: -520, y: -260, w: 1040, h: 720, baseW: 1040 };
let toastTimer;

function save() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(project)); saveState.textContent = "Сохранено здесь"; }
  catch (error) { saveState.textContent = "Скачайте JSON"; console.warn("Локальное сохранение недоступно:", error); }
}
function toast(message) {
  const element = $("#toast");
  element.textContent = message;
  element.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => element.classList.remove("show"), 2800);
}
function minutesText(minutes) { return `${minutes} мин`; }

function renderFloorList() {
  $("#overview-button").classList.toggle("active", activeView === "overview");
  $("#overview-button").setAttribute("aria-current", activeView === "overview" ? "true" : "false");
  floorList.innerHTML = project.floors.map((floor, index) => `<button type="button" class="floor-button ${activeView !== "overview" && floor.id === activeFloorId ? "active" : ""}" data-floor-id="${escapeHtml(floor.id)}" aria-current="${activeView !== "overview" && floor.id === activeFloorId ? "true" : "false"}"><span class="floor-number">${index + 1}</span><span class="floor-copy"><strong>${escapeHtml(floor.name)}</strong><small>${floor.rooms.length} комнат · ${floor.minutes} мин</small></span></button>`).join("");
  const floorTotal = project.floors.reduce((total, floor) => total + floor.minutes, 0);
  $("#floor-total").textContent = minutesText(floorTotal);
  $("#interlude-total").textContent = minutesText(project.interludeMinutes);
  $("#game-total").textContent = `${minutesText(floorTotal + project.interludeMinutes)} · ${((floorTotal + project.interludeMinutes) / 60).toFixed(1)} ч`;
}

function renderToolbar() {
  const overview = activeView === "overview";
  $("#overview-viewport").hidden = !overview;
  $("#iso-viewport").hidden = activeView !== "iso";
  $("#map-viewport").hidden = activeView !== "floor";
  $("#floor-actions").hidden = overview;
  $("#map-footer").hidden = overview;
  $("#iso-view-button").setAttribute("aria-pressed", activeView === "iso" ? "true" : "false");
  $("#plan-view-button").setAttribute("aria-pressed", activeView === "floor" ? "true" : "false");
  if (overview) {
    const total = project.floors.reduce((sum, floor) => sum + floor.minutes, project.interludeMinutes);
    $("#floor-kicker").textContent = "Разрез · от люка до стада";
    $("#floor-title").textContent = project.title;
    $("#floor-goal").textContent = `${project.floors.length} этажей · ${total} минут по плану · нажмите на комнату для её схемы`;
    return;
  }
  const floor = currentFloor();
  $("#update-first-floor-button").hidden = floor.id !== "floor-1" || Number(floor.designRevision || 0) >= 4;
  $("#floor-kicker").textContent = `Этаж ${project.floors.indexOf(floor) + 1} · ${activeView === "iso" ? "диорама" : "план"}`;
  $("#floor-title").textContent = floor.name;
  $("#floor-goal").textContent = floor.goal;
  $("#room-count").textContent = `${floor.rooms.length} комнат · ${floor.rooms.reduce((sum, item) => sum + item.minutes, 0)} мин по комнатам`;
  $("#iso-note").textContent = project.floors.indexOf(floor) === 0 ? "Первый этаж · пространственный эскиз" : "Условная геометрия · уточнить при проектировании";
}

function renderOverview() {
  const symbols = ["◈", "⚒", "⚙", "▤", "☀"];
  const slabs = project.floors.map((floor, index) => {
    const counts = ["combat", "puzzle", "story", "boss"].map((type) => {
      const count = floor.rooms.filter((item) => item.type === type).length;
      return count ? `${typeGlyph(type)} ${typeText(type).toLowerCase()}: ${count}` : "";
    }).filter(Boolean);
    const rooms = floor.rooms.map((item) => `<button class="mini-room" type="button" data-open-room="${escapeHtml(item.id)}" title="${escapeHtml(item.summary)}"><span class="mini-glyph" aria-hidden="true">${typeGlyph(item.type)}</span><span><strong>${escapeHtml(item.code)}</strong><small>${escapeHtml(item.title)}</small></span></button>`).join("") || "<small>Добавьте первую комнату на плане этажа.</small>";
    return `<section class="overview-floor" data-level="${index + 1}"><span class="depth-marker" aria-label="Этаж ${index + 1}">${index + 1}</span><div class="floor-slab"><div class="slab-header"><div class="slab-name"><span class="slab-icon" aria-hidden="true">${symbols[index % symbols.length]}</span><div><small>ЭТАЖ ${index + 1} · ${floor.minutes} МИН</small><h3>${escapeHtml(floor.name)}</h3></div></div><button class="slab-open" type="button" data-open-floor="${escapeHtml(floor.id)}">Открыть план →</button></div><p class="slab-goal">${escapeHtml(floor.goal)}</p><div class="mini-route" aria-label="Комнаты этажа ${index + 1} по порядку">${rooms}</div><div class="slab-foot"><span>${floor.rooms.length} комнат</span>${counts.map((value) => `<span>${value}</span>`).join("")}</div></div></section>`;
  }).reverse().join("");
  overviewMap.innerHTML = `<div class="surface-cap"><span class="surface-icon" aria-hidden="true">☀</span><div><small>Поверхность · цель пути</small><h3>Стадо ждёт Слизи</h3></div></div>${slabs}<div class="fall-cap"><span class="fall-icon" aria-hidden="true">◕</span><div><small>Глубина · начало истории</small><h3>Слизи падает через служебный люк</h3></div></div>`;
}

function connectionPath(from, to) {
  const fx = from.x + CARD_WIDTH / 2, fy = from.y + CARD_HEIGHT / 2;
  const tx = to.x + CARD_WIDTH / 2, ty = to.y + CARD_HEIGHT / 2;
  const dx = tx - fx, dy = ty - fy;
  if (Math.abs(dx) > Math.abs(dy)) {
    const sign = Math.sign(dx) || 1;
    const sx = fx + sign * CARD_WIDTH / 2, ex = tx - sign * CARD_WIDTH / 2;
    const bend = Math.max(45, Math.abs(ex - sx) * .45);
    return `M ${sx} ${fy} C ${sx + sign * bend} ${fy}, ${ex - sign * bend} ${ty}, ${ex} ${ty}`;
  }
  const sign = Math.sign(dy) || 1;
  const sy = fy + sign * CARD_HEIGHT / 2, ey = ty - sign * CARD_HEIGHT / 2;
  const bend = Math.max(45, Math.abs(ey - sy) * .45);
  return `M ${fx} ${sy} C ${fx} ${sy + sign * bend}, ${tx} ${ey - sign * bend}, ${tx} ${ey}`;
}

function renderCanvas() {
  const floor = currentFloor();
  const floorRoomIds = new Set(floor.rooms.map((item) => item.id));
  lineLayer.innerHTML = project.links.filter((link) => floorRoomIds.has(link.from) && floorRoomIds.has(link.to)).map((link) => {
    const from = floor.rooms.find((item) => item.id === link.from);
    const to = floor.rooms.find((item) => item.id === link.to);
    return `<path class="connection ${link.type === "optional" ? "optional" : ""}" d="${connectionPath(from, to)}"></path>`;
  }).join("");
  roomLayer.innerHTML = floor.rooms.map((item) => {
    const crossFloorLink = project.links.find((link) => link.from === item.id && roomById(link.to)?.floor.id !== floor.id);
    const nextFloor = crossFloorLink ? project.floors.indexOf(roomById(crossFloorLink.to).floor) + 1 : null;
    return `<div class="room-card ${selectedRoomId === item.id ? "selected" : ""}" data-room-id="${escapeHtml(item.id)}" data-type="${escapeHtml(item.type)}" style="left:${item.x}px;top:${item.y}px" role="button" tabindex="0" aria-label="${escapeHtml(item.code)} ${escapeHtml(item.title)}, ${escapeHtml(item.minutes)} минут"><div class="room-top"><span class="room-code">${escapeHtml(item.code || "КОМНАТА")}</span><span class="room-status ${item.status === "plan" ? "plan" : ""}">${statusText(item.status)}</span></div><div class="room-name-row"><span class="room-glyph" aria-hidden="true">${typeGlyph(item.type)}</span><h3>${escapeHtml(item.title)}</h3></div><p>${escapeHtml(item.summary || "Добавьте описание комнаты")}</p><div class="room-meta"><span>${typeText(item.type)}${nextFloor ? ` · ↑ этаж ${nextFloor}` : ""}</span><span>${item.minutes} мин</span></div></div>`;
  }).join("");
  renderOverview();
  renderIso();
}

function renderIso() {
  const scene = IsoMap.scene(currentFloor(), project.links, selectedRoomId, project.floors.indexOf(currentFloor()), escapeHtml);
  isoScene.innerHTML = scene.markup;
  return scene.bounds;
}

function textField(label, field, value, scope = "room", rows = 0) {
  const control = rows ? `<textarea data-scope="${scope}" data-field="${field}" rows="${rows}">${escapeHtml(value)}</textarea>` : `<input data-scope="${scope}" data-field="${field}" value="${escapeHtml(value)}">`;
  return `<label class="field"><span>${label}</span>${control}</label>`;
}
function numberField(label, field, value, scope = "room") { return `<label class="field"><span>${label}</span><input type="number" min="0" max="600" data-scope="${scope}" data-field="${field}" value="${value}"></label>`; }
function isoNumberField(label, field, value) { return `<label class="field"><span>${label}</span><input type="number" min="${field === "u" || field === "v" ? -4 : field === "w" || field === "d" ? 0.8 : 0}" max="${field === "h" ? 8 : field === "w" || field === "d" ? 4 : 20}" step="0.25" data-scope="iso" data-field="${field}" value="${value}"></label>`; }
function selectField(label, field, value, options) { return `<label class="field"><span>${label}</span><select data-scope="room" data-field="${field}">${options.map(([key, name]) => `<option value="${key}" ${value === key ? "selected" : ""}>${name}</option>`).join("")}</select></label>`; }

function renderInspector() {
  if (activeView === "overview") {
    selectedRoomId = null;
    const totalRooms = project.floors.reduce((sum, floor) => sum + floor.rooms.length, 0);
    const totalMinutes = project.floors.reduce((sum, floor) => sum + floor.minutes, project.interludeMinutes);
    inspector.innerHTML = `<div class="inspector-heading"><div><span class="eyebrow">Вся игра</span><h2>Путь Слизи наверх</h2></div></div><p class="inspector-intro">Нижний этаж — внизу разреза. Выше находятся новые части подземелья; в самом верху — выход к стаду.</p><div class="overview-stat"><strong>${project.floors.length}</strong><span>этажей</span><strong>${totalRooms}</strong><span>комнат</span><strong>${(totalMinutes / 60).toFixed(1)} ч</strong><span>по плану</span></div>${textField("Рабочее название", "title", project.title, "project")}${numberField("Переходы и финал, мин", "interludeMinutes", project.interludeMinutes, "project")}<div class="inspector-section"><h3>Как читать разрез</h3><p>Нажмите на комнату, чтобы открыть её план и заметки. Этажи и их время можно менять. Цвета и значки помогают отличать бой, задачу, сюжет и босса.</p></div><div class="bottom-actions"><button id="reset-button" type="button">Вернуть исходный пример</button></div>`;
    return;
  }
  const item = selectedRoom();
  if (!item || !currentFloor().rooms.includes(item)) {
    selectedRoomId = null;
    const floor = currentFloor();
    const roomMinutes = floor.rooms.reduce((total, roomItem) => total + roomItem.minutes, 0);
    inspector.innerHTML = `<div class="inspector-heading"><div><span class="eyebrow">Настройки этажа</span><h2>${escapeHtml(floor.name)}</h2></div></div><p class="inspector-intro">Выберите комнату на схеме или настройте этаж здесь.</p>${textField("Название", "name", floor.name, "floor")}${textField("Сюжетная цель", "goal", floor.goal, "floor", 3)}<div class="field-row">${numberField("План, мин", "minutes", floor.minutes, "floor")}${numberField("Между этажами, мин", "interludeMinutes", project.interludeMinutes, "project")}</div><small>Сумма времени комнат: ${roomMinutes} мин. План этажа: ${floor.minutes} мин.</small><div class="inspector-section"><h3>Как работать с картой</h3><p>Добавляйте комнаты, двигайте их мышью и связывайте в карточке комнаты. Изменения сохраняются в этом браузере. Для передачи проекта скачайте JSON.</p></div><div class="bottom-actions"><button id="reset-button" type="button">Вернуть исходный пример</button><button id="delete-floor-button" type="button" class="danger-button" ${project.floors.length === 1 ? "disabled" : ""}>Удалить этаж</button></div>`;
    return;
  }
  const outgoing = project.links.filter((link) => link.from === item.id);
  const incoming = project.links.filter((link) => link.to === item.id);
  const outgoingMarkup = outgoing.length ? outgoing.map((link) => {
    const target = roomById(link.to);
    return `<div class="link-item"><span>→ ${escapeHtml(target?.floor.name || "?")} / ${escapeHtml(target?.room.code || "?")} ${escapeHtml(target?.room.title || "?")} ${link.type === "optional" ? "· побочный" : ""}</span><button type="button" data-remove-link="${escapeHtml(link.id)}" aria-label="Удалить переход">×</button></div>`;
  }).join("") : "<small>Переходов пока нет.</small>";
  const incomingMarkup = incoming.length ? incoming.map((link) => {
    const source = roomById(link.from);
    return `<div class="link-item"><span>← ${escapeHtml(source?.floor.name || "?")} / ${escapeHtml(source?.room.code || "?")} ${escapeHtml(source?.room.title || "?")}</span><button type="button" data-remove-link="${escapeHtml(link.id)}" aria-label="Удалить входящий переход">×</button></div>`;
  }).join("") : "<small>Входящих переходов нет.</small>";
  const targetOptions = project.floors.flatMap((floor, index) => floor.rooms.filter((target) => target.id !== item.id).map((target) => `<option value="${escapeHtml(target.id)}">${index + 1} · ${escapeHtml(target.code)} ${escapeHtml(target.title)}</option>`)).join("");
  inspector.innerHTML = `<div class="inspector-heading"><div><span class="eyebrow">Комната · ${escapeHtml(item.code)}</span><h2>${escapeHtml(item.title)}</h2></div><button id="close-inspector" class="icon-button" type="button" aria-label="Закрыть карточку">×</button></div>
    <div class="field-row">${textField("Код", "code", item.code)}${numberField("Время, мин", "minutes", item.minutes)}</div>
    ${textField("Название", "title", item.title)}
    <div class="field-row">${selectField("Тип", "type", item.type, [["entrance", "Вход"], ["combat", "Бой"], ["puzzle", "Задача"], ["story", "История"], ["boss", "Босс"], ["rest", "Передышка"]])}${selectField("Состояние", "status", item.status, [["prototype", "Прототип"], ["plan", "План"], ["ready", "Готово"]])}</div>
    <div class="inspector-section"><h3>Площадка в диораме</h3><p>Условные единицы: две оси пола, высота и размер площадки. Площадку можно перетащить в изометрическом виде.</p><div class="field-row">${isoNumberField("Ось A", "u", item.iso.u)}${isoNumberField("Ось B", "v", item.iso.v)}</div><div class="field-row">${isoNumberField("Высота", "h", item.iso.h)}${isoNumberField("Ширина", "w", item.iso.w)}</div>${isoNumberField("Глубина", "d", item.iso.d)}</div>
    ${textField("Кратко на карте", "summary", item.summary, "room", 2)}
    ${textField("Что делает игрок", "gameplay", item.gameplay, "room", 3)}
    ${textField("Сюжет и находки", "story", item.story, "room", 3)}
    ${textField("Шутка или деталь", "humor", item.humor, "room", 2)}
    ${textField("Заметки и вопросы", "notes", item.notes, "room", 3)}
    <div class="inspector-section"><h3>Переходы из комнаты</h3><div class="link-list">${outgoingMarkup}</div><div class="link-controls"><select id="link-target" aria-label="Целевая комната"><option value="">Выберите целевую комнату</option>${targetOptions}</select><select id="link-type" aria-label="Тип перехода"><option value="main">Основной путь</option><option value="optional">Побочный путь</option></select><button id="add-link-button" type="button">＋ Добавить переход</button></div><h3 class="incoming-heading">Переходы сюда</h3><div class="link-list">${incomingMarkup}</div></div>
    <div class="bottom-actions"><button id="delete-room-button" class="danger-button" type="button">Удалить комнату</button></div>`;
}

function renderAll() { renderFloorList(); renderToolbar(); renderCanvas(); renderInspector(); applyView(); applyIsoCamera(); }
function applyView() { world.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`; $("#zoom-label").textContent = `${Math.round(view.scale * 100)}%`; }
function applyIsoCamera() {
  isoSvg.setAttribute("viewBox", `${isoCamera.x} ${isoCamera.y} ${isoCamera.w} ${isoCamera.h}`);
  if (activeView === "iso") $("#zoom-label").textContent = `${Math.round(isoCamera.baseW / isoCamera.w * 100)}%`;
}
function fitIso() {
  const bounds = renderIso();
  isoCamera = { ...bounds, baseW: bounds.w };
  applyIsoCamera();
}
function isoScreenScale() {
  const rect = isoSvg.getBoundingClientRect();
  return Math.min(rect.width / isoCamera.w, rect.height / isoCamera.h) || 1;
}
function zoomIso(factor, clientX, clientY) {
  const rect = isoSvg.getBoundingClientRect();
  const scale = isoScreenScale();
  const offsetX = (rect.width - isoCamera.w * scale) / 2;
  const offsetY = (rect.height - isoCamera.h * scale) / 2;
  const worldX = isoCamera.x + (clientX - rect.left - offsetX) / scale;
  const worldY = isoCamera.y + (clientY - rect.top - offsetY) / scale;
  const nextW = clamp(isoCamera.w / factor, isoCamera.baseW / 2.2, isoCamera.baseW * 2.1);
  const ratio = nextW / isoCamera.w;
  isoCamera.x = worldX - (worldX - isoCamera.x) * ratio;
  isoCamera.y = worldY - (worldY - isoCamera.y) * ratio;
  isoCamera.h *= ratio;
  isoCamera.w = nextW;
  applyIsoCamera();
}

function fitMap() {
  const rooms = currentFloor().rooms;
  const width = viewport.clientWidth, height = viewport.clientHeight;
  if (!width || !height) return;
  if (!rooms.length) { view = { x: width / 2 - 200, y: height / 2 - 150, scale: 1 }; applyView(); return; }
  const left = Math.min(...rooms.map((item) => item.x)) - 35;
  const top = Math.min(...rooms.map((item) => item.y)) - 35;
  const right = Math.max(...rooms.map((item) => item.x + CARD_WIDTH)) + 35;
  const bottom = Math.max(...rooms.map((item) => item.y + CARD_HEIGHT)) + 35;
  const scale = clamp(Math.min(width / (right - left), height / (bottom - top)), .48, 1.12);
  view = { scale, x: (width - (left + right) * scale) / 2, y: (height - (top + bottom) * scale) / 2 };
  applyView();
}

function zoomAt(factor, clientX, clientY) {
  const rect = viewport.getBoundingClientRect();
  const px = clientX - rect.left, py = clientY - rect.top;
  const next = clamp(view.scale * factor, .35, 1.8);
  const wx = (px - view.x) / view.scale, wy = (py - view.y) / view.scale;
  view.x = px - wx * next; view.y = py - wy * next; view.scale = next;
  applyView();
}

function switchFloor(id, roomId = null, mode = activeView === "floor" ? "floor" : "iso") {
  if (!floorById(id)) return;
  activeView = mode; activeFloorId = id; selectedRoomId = roomId;
  renderAll();
  requestAnimationFrame(mode === "iso" ? fitIso : fitMap);
}

function showOverview() { activeView = "overview"; selectedRoomId = null; renderAll(); }
function setFloorView(mode) {
  if (activeView === mode) return;
  activeView = mode;
  renderAll();
  requestAnimationFrame(mode === "iso" ? fitIso : fitMap);
}

function addRoom() {
  const floor = currentFloor();
  const index = project.floors.indexOf(floor) + 1;
  const code = index === 1 ? `R${String(floor.rooms.length + 1).padStart(2, "0")}` : `F${index}-${String(floor.rooms.length + 1).padStart(2, "0")}`;
  const previous = floor.rooms.at(-1);
  const x = activeView === "floor" ? clamp(Math.round((viewport.clientWidth / 2 - view.x) / view.scale - CARD_WIDTH / 2), 0, WORLD_WIDTH - CARD_WIDTH) : clamp((previous?.x ?? 80) + 235, 0, WORLD_WIDTH - CARD_WIDTH);
  const y = activeView === "floor" ? clamp(Math.round((viewport.clientHeight / 2 - view.y) / view.scale - CARD_HEIGHT / 2), 0, WORLD_HEIGHT - CARD_HEIGHT) : clamp((previous?.y ?? 340) - 80, 0, WORLD_HEIGHT - CARD_HEIGHT);
  const item = room(uid("room"), code, "Новая комната", "story", 5, x, y, "", "", "", "", "plan");
  item.iso = IsoMap.normalize(null, item.id, floor.rooms.length);
  floor.rooms.push(item); selectedRoomId = item.id;
  save(); renderAll(); requestAnimationFrame(activeView === "iso" ? fitIso : fitMap); toast("Комната добавлена");
}

function addFloor() {
  const floor = { id: uid("floor"), name: `Этаж ${project.floors.length + 1}`, minutes: 45, goal: "Новая цель этажа", rooms: [] };
  project.floors.push(floor); save(); switchFloor(floor.id); toast("Этаж добавлен");
}

function deleteRoom() {
  const item = selectedRoom(); if (!item) return;
  if (!confirm(`Удалить комнату «${item.title}» и все её переходы?`)) return;
  const floor = currentFloor();
  floor.rooms = floor.rooms.filter((candidate) => candidate.id !== item.id);
  project.links = project.links.filter((link) => link.from !== item.id && link.to !== item.id);
  selectedRoomId = null; save(); renderAll(); requestAnimationFrame(activeView === "iso" ? fitIso : fitMap); toast("Комната удалена");
}

function deleteFloor() {
  if (project.floors.length === 1) return;
  const floor = currentFloor();
  if (!confirm(`Удалить этаж «${floor.name}» со всеми комнатами и переходами?`)) return;
  const ids = new Set(floor.rooms.map((item) => item.id));
  project.links = project.links.filter((link) => !ids.has(link.from) && !ids.has(link.to));
  const index = project.floors.indexOf(floor);
  project.floors.splice(index, 1);
  save(); switchFloor(project.floors[Math.max(0, index - 1)].id); toast("Этаж удалён");
}

floorList.addEventListener("click", (event) => { const button = event.target.closest("[data-floor-id]"); if (button) switchFloor(button.dataset.floorId); });
$("#overview-button").addEventListener("click", showOverview);
$("#iso-view-button").addEventListener("click", () => setFloorView("iso"));
$("#plan-view-button").addEventListener("click", () => setFloorView("floor"));
overviewMap.addEventListener("click", (event) => {
  const roomButton = event.target.closest("[data-open-room]");
  if (roomButton) { const found = roomById(roomButton.dataset.openRoom); if (found) switchFloor(found.floor.id, found.room.id); return; }
  const floorButton = event.target.closest("[data-open-floor]");
  if (floorButton) switchFloor(floorButton.dataset.openFloor);
});
$("#add-room-button").addEventListener("click", addRoom);
$("#update-first-floor-button").addEventListener("click", () => {
  if (!project.floors.some((floor) => floor.id === "floor-1") || !confirm("Заменить только первый этаж новой боевой версией? Остальные этажи сохранятся. Перед заменой скачается резервная копия всей текущей карты.")) return;
  downloadProject("slizi-dungeon-map-before-floor-1-update.json");
  project = withUpdatedFirstFloor(project);
  save(); switchFloor("floor-1"); toast("Первый этаж обновлён до боевой версии");
});
$("#add-floor-button").addEventListener("click", addFloor);
$("#fit-button").addEventListener("click", () => { if (activeView === "iso") fitIso(); else fitMap(); });
$("#zoom-in-button").addEventListener("click", () => { const target = activeView === "iso" ? isoSvg : viewport; const rect = target.getBoundingClientRect(); if (activeView === "iso") zoomIso(1.2, rect.left + rect.width / 2, rect.top + rect.height / 2); else zoomAt(1.2, rect.left + rect.width / 2, rect.top + rect.height / 2); });
$("#zoom-out-button").addEventListener("click", () => { const target = activeView === "iso" ? isoSvg : viewport; const rect = target.getBoundingClientRect(); if (activeView === "iso") zoomIso(1 / 1.2, rect.left + rect.width / 2, rect.top + rect.height / 2); else zoomAt(1 / 1.2, rect.left + rect.width / 2, rect.top + rect.height / 2); });
viewport.addEventListener("wheel", (event) => { event.preventDefault(); zoomAt(event.deltaY < 0 ? 1.1 : 1 / 1.1, event.clientX, event.clientY); }, { passive: false });

let drag = null;
viewport.addEventListener("pointerdown", (event) => {
  const card = event.target.closest(".room-card");
  if (card) {
    const found = roomById(card.dataset.roomId);
    if (!found) return;
    selectedRoomId = found.room.id;
    renderInspector();
    roomLayer.querySelectorAll(".room-card").forEach((element) => element.classList.toggle("selected", element.dataset.roomId === selectedRoomId));
    drag = { kind: "room", pointerId: event.pointerId, room: found.room, card, x: event.clientX, y: event.clientY, startX: found.room.x, startY: found.room.y, moved: false };
    card.classList.add("dragging");
    card.setPointerCapture(event.pointerId);
  } else {
    selectedRoomId = null; renderInspector();
    roomLayer.querySelectorAll(".room-card").forEach((element) => element.classList.remove("selected"));
    drag = { kind: "pan", pointerId: event.pointerId, x: event.clientX, y: event.clientY, startX: view.x, startY: view.y };
    viewport.classList.add("panning"); viewport.setPointerCapture(event.pointerId);
  }
});
viewport.addEventListener("pointermove", (event) => {
  if (!drag || drag.pointerId !== event.pointerId) return;
  if (drag.kind === "pan") { view.x = drag.startX + event.clientX - drag.x; view.y = drag.startY + event.clientY - drag.y; applyView(); return; }
  const nextX = clamp(Math.round(drag.startX + (event.clientX - drag.x) / view.scale), 0, WORLD_WIDTH - CARD_WIDTH);
  const nextY = clamp(Math.round(drag.startY + (event.clientY - drag.y) / view.scale), 0, WORLD_HEIGHT - CARD_HEIGHT);
  if (nextX !== drag.room.x || nextY !== drag.room.y) drag.moved = true;
  drag.room.x = nextX; drag.room.y = nextY;
  drag.card.style.left = `${nextX}px`; drag.card.style.top = `${nextY}px`;
  const floor = currentFloor();
  lineLayer.innerHTML = project.links.filter((link) => floor.rooms.some((item) => item.id === link.from) && floor.rooms.some((item) => item.id === link.to)).map((link) => `<path class="connection ${link.type === "optional" ? "optional" : ""}" d="${connectionPath(roomById(link.from).room, roomById(link.to).room)}"></path>`).join("");
});
function finishDrag(event) {
  if (!drag || drag.pointerId !== event.pointerId) return;
  if (drag.kind === "room") { drag.card.classList.remove("dragging"); if (drag.moved) save(); }
  else viewport.classList.remove("panning");
  drag = null;
}
viewport.addEventListener("pointerup", finishDrag);
viewport.addEventListener("pointercancel", finishDrag);
roomLayer.addEventListener("keydown", (event) => { if ((event.key === "Enter" || event.key === " ") && event.target.classList.contains("room-card")) { event.preventDefault(); selectedRoomId = event.target.dataset.roomId; renderCanvas(); renderInspector(); } });

let isoDrag = null;
isoSvg.addEventListener("pointerdown", (event) => {
  const group = event.target.closest("[data-iso-room]");
  if (group) {
    const found = roomById(group.dataset.isoRoom);
    if (!found) return;
    selectedRoomId = found.room.id;
    isoDrag = { kind: "room", pointerId: event.pointerId, room: found.room, x: event.clientX, y: event.clientY, u: found.room.iso.u, v: found.room.iso.v, moved: false };
    renderInspector(); renderIso();
  } else {
    isoDrag = { kind: "pan", pointerId: event.pointerId, x: event.clientX, y: event.clientY, cameraX: isoCamera.x, cameraY: isoCamera.y };
    isoSvg.classList.add("panning");
  }
  isoSvg.setPointerCapture(event.pointerId);
});
isoSvg.addEventListener("pointermove", (event) => {
  if (!isoDrag || isoDrag.pointerId !== event.pointerId) return;
  const dx = (event.clientX - isoDrag.x) / isoScreenScale();
  const dy = (event.clientY - isoDrag.y) / isoScreenScale();
  if (isoDrag.kind === "pan") { isoCamera.x = isoDrag.cameraX - dx; isoCamera.y = isoDrag.cameraY - dy; applyIsoCamera(); return; }
  const du = (dx / IsoMap.STEP_X + dy / IsoMap.STEP_Y) / 2;
  const dv = (dy / IsoMap.STEP_Y - dx / IsoMap.STEP_X) / 2;
  const nextU = clamp(Math.round((isoDrag.u + du) * 4) / 4, -4, 20);
  const nextV = clamp(Math.round((isoDrag.v + dv) * 4) / 4, -4, 20);
  if (nextU !== isoDrag.room.iso.u || nextV !== isoDrag.room.iso.v) isoDrag.moved = true;
  isoDrag.room.iso.u = nextU; isoDrag.room.iso.v = nextV;
  renderIso();
});
function finishIsoDrag(event) {
  if (!isoDrag || isoDrag.pointerId !== event.pointerId) return;
  if (isoDrag.kind === "room" && isoDrag.moved) { save(); renderInspector(); }
  isoSvg.classList.remove("panning");
  isoDrag = null;
}
isoSvg.addEventListener("pointerup", finishIsoDrag);
isoSvg.addEventListener("pointercancel", finishIsoDrag);
isoSvg.addEventListener("wheel", (event) => { event.preventDefault(); zoomIso(event.deltaY < 0 ? 1.1 : 1 / 1.1, event.clientX, event.clientY); }, { passive: false });
isoSvg.addEventListener("keydown", (event) => {
  const group = event.target.closest("[data-iso-room]");
  if (group && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); selectedRoomId = group.dataset.isoRoom; renderIso(); renderInspector(); }
});

inspector.addEventListener("input", (event) => {
  const field = event.target.dataset.field, scope = event.target.dataset.scope;
  if (!field || !scope) return;
  const target = scope === "iso" ? selectedRoom()?.iso : scope === "room" ? selectedRoom() : scope === "floor" ? currentFloor() : project;
  if (!target) return;
  const numeric = ["minutes", "interludeMinutes"].includes(field);
  if (scope === "iso") target[field] = clamp(Number(event.target.value) || 0, field === "u" || field === "v" ? -4 : field === "w" || field === "d" ? 0.8 : 0, field === "h" ? 8 : field === "w" || field === "d" ? 4 : 20);
  else target[field] = numeric ? clamp(Number(event.target.value) || 0, 0, 600) : event.target.value;
  save(); renderFloorList(); renderToolbar(); renderCanvas();
  if (field === "title" || field === "name") { const heading = inspector.querySelector(".inspector-heading h2"); if (heading) heading.textContent = target[field]; }
});
inspector.addEventListener("change", (event) => {
  if (event.target.dataset.field === "type" || event.target.dataset.field === "status") { renderCanvas(); save(); }
});
inspector.addEventListener("click", (event) => {
  const remove = event.target.closest("[data-remove-link]");
  if (remove) { project.links = project.links.filter((link) => link.id !== remove.dataset.removeLink); save(); renderCanvas(); renderInspector(); return; }
  if (event.target.id === "close-inspector") { selectedRoomId = null; renderCanvas(); renderInspector(); }
  if (event.target.id === "delete-room-button") deleteRoom();
  if (event.target.id === "delete-floor-button") deleteFloor();
  if (event.target.id === "reset-button") { if (confirm("Заменить текущую карту исходным примером? Сначала скачайте JSON, если хотите сохранить свои изменения.")) { project = copyDefault(); save(); switchFloor(project.floors[0].id); toast("Исходная карта восстановлена"); } }
  if (event.target.id === "add-link-button") {
    const targetId = $("#link-target").value;
    const type = $("#link-type").value;
    if (!targetId || !selectedRoomId) { toast("Сначала выберите целевую комнату"); return; }
    if (project.links.some((link) => link.from === selectedRoomId && link.to === targetId)) { toast("Такой переход уже есть"); return; }
    project.links.push({ id: uid("link"), from: selectedRoomId, to: targetId, type });
    save(); renderCanvas(); renderInspector(); toast("Переход добавлен");
  }
});

function downloadProject(filename) {
  const blob = new Blob([JSON.stringify(project, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url; anchor.download = filename;
  document.body.append(anchor); anchor.click(); anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
$("#export-button").addEventListener("click", () => {
  downloadProject(`slizi-dungeon-map-${new Date().toISOString().slice(0, 10)}.json`);
  toast("Карта скачана в JSON");
});
$("#import-button").addEventListener("click", () => $("#import-file").click());
$("#import-file").addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;
  try {
    const next = validateProject(JSON.parse(await file.text()));
    if (!confirm("Заменить текущую карту данными из файла?")) return;
    project = next; save(); switchFloor(project.floors[0].id); toast("Карта загружена");
  } catch (error) { toast(`Не удалось загрузить: ${error.message}`); }
});

renderAll();
requestAnimationFrame(fitIso);
window.addEventListener("resize", () => requestAnimationFrame(activeView === "iso" ? fitIso : fitMap));
save();

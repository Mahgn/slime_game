"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const uid = (prefix) => `${prefix}-${crypto.randomUUID()}`;
  const WIDTH = 290, HEIGHT = 96, LANE = 400;
  const KINDS = {story:"Сюжет",combat:"Столкновение",discovery:"Открытие",choice:"Выбор пути",rest:"Передышка",finale:"Финал"};
  const STATUSES = {draft:"Предложение",question:"Открытый вопрос",prototype:"Основа в прототипе",canon:"Принято вами"};
  const EDGE_KINDS = {main:"Основной путь",branch:"Альтернативный путь",return:"Возврат"};
  const DRAFT_KEY = `slizi-hero-journey-draft:${location.origin}`;
  let project = null, revision = "", selected = null, chapter = null, view = "map";
  let transform = {x:30,y:20,k:.85}, drag = null, linking = false, linkSource = null;
  let history = [], future = [], dirty = false, generation = 0, saving = false, paused = false;
  let saveTimer, toastTimer, conflict = null, activeField = null, suppressClick = false, renderedSelection = "", pendingChapterId = null, editingChapterId = null;
  const orderedChapters = () => [...project.chapters].sort((a,b) => a.order-b.order);
  const nodeById = (id) => project.nodes.find((n) => n.id === id);
  const edgeById = (id) => project.edges.find((e) => e.id === id);
  const chapterById = (id) => project.chapters.find((c) => c.id === id);
  const color = (value) => /^#[0-9a-f]{6}$/i.test(value) ? value : "#8ae1b8";
  const isTextInput = (target) => target instanceof Element && Boolean(target.closest("input,textarea,select,[contenteditable]"));
  function toast(message) { $("toast").textContent=message; $("toast").classList.add("visible"); clearTimeout(toastTimer); toastTimer=setTimeout(() => $("toast").classList.remove("visible"),3200); }
  function saveState(message, error=false) { $("save-state").textContent=message; $("save-state").classList.toggle("error",error); }
  function showNotice(message, actions=[]) {
    const box=$("notice"); box.replaceChildren(); const text=document.createElement("span"); text.textContent=message; box.append(text);
    for(const [label,fn] of actions){const b=document.createElement("button"); b.textContent=label;b.onclick=fn;box.append(b);} box.hidden=false;
  }
  function hideNotice(){ $("notice").hidden=true; }
  function remember(){history.push(clone(project)); if(history.length>80)history.shift();future=[]; updateHistory();}
  function updateHistory(){ $("undo").disabled=!history.length;$("redo").disabled=!future.length; }
  function writeDraft(){try{localStorage.setItem(DRAFT_KEY,JSON.stringify({revision,project}));}catch{ /* Server remains authoritative when storage is unavailable. */ }}
  function changed(){dirty=true;generation++;writeDraft();saveState(paused?"Выберите версию":"Сохраняю…",paused);clearTimeout(saveTimer);saveTimer=setTimeout(save,650);updateHistory();}
  function mutate(fn){if(!project)return;remember();fn();changed();render();}
  function undo(){if(!history.length)return;future.push(clone(project));project=history.pop();selected=null;changed();render();toast("Изменение отменено");}
  function redo(){if(!future.length)return;history.push(clone(project));project=future.pop();selected=null;changed();render();toast("Изменение повторено");}
  async function fetchProject(){const response=await fetch("/api/project",{cache:"no-store"});if(!response.ok)throw new Error(`Сервер: ${response.status}`);return response.json();}
  function conflictNotice(remote){
    conflict=remote;paused=true;saveState("Разные версии",true);
    showNotice("Файл изменён в другом окне или Codex. Ваши правки сохранены в черновике. Выберите версию:",[
      ["Принять файл",()=>{remember();project=clone(conflict.project);revision=conflict.revision;dirty=false;paused=false;conflict=null;localStorage.removeItem(DRAFT_KEY);hideNotice();render();saveState("Сохранено в проект");}],
      ["Сохранить мою",()=>{revision=conflict.revision;paused=false;conflict=null;hideNotice();changed();save();}],
      ["Скачать мою копию",exportProject]
    ]);
  }
  async function save(){
    if(!project||!dirty||saving||paused)return;
    saving=true;const sentGeneration=generation;const snapshot=clone(project);
    try{
      const response=await fetch("/api/project",{method:"PUT",headers:{"Content-Type":"application/json"},body:JSON.stringify({project:snapshot,revision})});
      const result=await response.json();
      if(response.status===409){conflictNotice(result);return;}
      if(!response.ok)throw new Error(result.error||`Ошибка ${response.status}`);
      revision=result.revision;
      if(generation===sentGeneration){dirty=false;localStorage.removeItem(DRAFT_KEY);saveState("Сохранено в проект");if(!paused)hideNotice();}
      else{writeDraft();saveState("Сохраняю…");}
    }catch(error){
      saveState("Не сохранено",true);
      showNotice(`Не удалось записать файл: ${error.message}. Черновик остаётся в этом браузере.`,[["Повторить",save],["Скачать JSON",exportProject]]);
    }finally{saving=false;if(dirty&&!paused&&generation!==sentGeneration){clearTimeout(saveTimer);saveTimer=setTimeout(save,350);}}
  }
  async function poll(){
    if(!project||saving||paused||document.hidden||drag||$("delete-chapter-dialog").open)return;
    const startedGeneration=generation,startedRevision=revision;
    try{const remote=await fetchProject();if(generation!==startedGeneration||revision!==startedRevision||saving||paused||drag||$("delete-chapter-dialog").open)return;if(remote.revision===revision)return;if(dirty){conflictNotice(remote);return;}project=validate(remote.project);revision=remote.revision;history=[];future=[];render();saveState("Обновлено из файла");toast("Карта обновлена из общего файла");}catch{/* Offline writes show a persistent, actionable error in save(). */}
  }
  function validate(data){
    const keys=(value,list)=>{if(!value||typeof value!=="object"||Array.isArray(value)||Object.keys(value).sort().join("|")!==list.split(",").sort().join("|"))throw new Error("Неполный или неизвестный набор полей в карте.");};
    const text=(value,limit=6000)=>{if(typeof value!=="string"||value.length>limit)throw new Error(`Текстовое поле должно содержать не более ${limit} символов.`);};
    const id=(value)=>{if(typeof value!=="string"||!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(value))throw new Error("ID: до 80 английских букв, цифр, дефисов и подчёркиваний.");};
    keys(data,"schemaVersion,id,title,subtitle,chapters,nodes,edges");id(data.id);text(data.title,300);text(data.subtitle);
    if(data.schemaVersion!==1||!Array.isArray(data.chapters)||!Array.isArray(data.nodes)||!Array.isArray(data.edges))throw new Error("Нужен файл карты пути героя версии 1.");
    if(!data.chapters.length||data.chapters.length>30||data.nodes.length>500||data.edges.length>2000)throw new Error("Допустимо 1–30 глав, до 500 этапов и 2000 переходов.");
    const ids=(items)=>{const set=new Set();for(const item of items){if(!item)throw new Error("Пустой объект в карте.");id(item.id);if(set.has(item.id))throw new Error("Повторяющиеся ID.");set.add(item.id);}return set;};
    const chapters=ids(data.chapters),nodes=ids(data.nodes);ids(data.edges);
    for(const c of data.chapters){keys(c,"id,title,subtitle,color,order");text(c.title,300);text(c.subtitle,3000);text(c.color,7);if(!/^#[0-9a-f]{6}$/i.test(c.color)||!Number.isFinite(c.order)||c.order<0||c.order>10000)throw new Error("Некорректные свойства главы.");}
    for(const n of data.nodes){keys(n,"id,chapterId,x,y,title,kind,status,location,goal,action,change,emotion,reveal,requires,notes,sources");if(!chapters.has(n.chapterId)||!Number.isFinite(n.x)||!Number.isFinite(n.y)||Math.abs(n.x)>100000||Math.abs(n.y)>100000||!Object.hasOwn(KINDS,n.kind)||!Object.hasOwn(STATUSES,n.status))throw new Error("Некорректный этап или его координаты.");text(n.title,300);for(const key of ["location","goal","action","change","emotion","reveal","requires","notes"]){text(n[key]);}if(!Array.isArray(n.sources)||n.sources.length>30)throw new Error("Допустимо до 30 источников этапа.");for(const s of n.sources){keys(s,"label,path");text(s.label,300);text(s.path,1000);}}
    for(const e of data.edges){keys(e,"id,from,to,label,kind");text(e.label,1000);if(!nodes.has(e.from)||!nodes.has(e.to)||e.from===e.to||!Object.hasOwn(EDGE_KINDS,e.kind))throw new Error("Переход ссылается на отсутствующий этап или на себя.");}
    return data;
  }
  function exportProject(){if(!project)return;const blob=new Blob([JSON.stringify(project,null,2)+"\n"],{type:"application/json"});const a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download=`slizi-journey-${new Date().toISOString().slice(0,10)}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);toast("Копия карты скачана");}
  async function importProject(file){if(!file)return;try{if(file.size>2*1024*1024)throw new Error("Файл больше 2 МБ.");const incoming=validate(JSON.parse(await file.text()));if(!confirm(`Заменить текущую карту на «${incoming.title}» (${incoming.nodes.length} этапов)? Действие можно отменить.`))return;mutate(()=>{project=clone(incoming);selected=null;chapter=null;});fit();toast("Карта импортирована. Доступна отмена.");}catch(error){toast(`Импорт отменён: ${error.message}`);}finally{$("import-file").value="";}}
  function renderNavigation(){
    $("total-count").textContent=project.nodes.length;$("overview").classList.toggle("active",!chapter);
    $("chapters").innerHTML=orderedChapters().map((c,i)=>`<button class="chapter-button ${chapter===c.id?"active":""}" data-chapter="${esc(c.id)}" style="--accent:${color(c.color)}"><span class="chapter-number">${i===0?"П":i}</span><span class="chapter-copy"><strong>${esc(c.title)}</strong><small>${project.nodes.filter(n=>n.chapterId===c.id).length} этапов</small></span></button>`).join("");
    renderSearch();
  }
  function searchMatches(){const query=$("search").value.trim().toLocaleLowerCase("ru");return query?project.nodes.filter(n=>[n.title,n.location,n.goal,n.action,n.reveal,n.notes].join(" ").toLocaleLowerCase("ru").includes(query)):null;}
  function renderSearch(){const matches=searchMatches();$("search-results").innerHTML=matches?(matches.length?matches.slice(0,20).map(n=>`<button data-select-node="${esc(n.id)}">${esc(n.title)}</button>`).join(""):"<p class='intro-copy'>Ничего не найдено</p>"):"";}
  function canvasSize(){return {w:Math.max(orderedChapters().length*LANE,...project.nodes.map(n=>n.x+WIDTH+100)),h:Math.max(1150,...project.nodes.map(n=>n.y+HEIGHT+120))};}
  function renderCanvas(){
    const size=canvasSize();$("world").style.width=size.w+"px";$("world").style.height=size.h+"px";
    $("lanes").innerHTML=orderedChapters().map((c,i)=>`<section class="lane ${chapter===c.id?"chapter-selected":""}" data-lane="${esc(c.id)}" style="left:${i*LANE}px;--accent:${color(c.color)}"><button class="lane-head" data-lane-chapter="${esc(c.id)}" aria-label="Изменить главу: ${esc(c.title)}" aria-expanded="${editingChapterId===c.id}" aria-controls="chapter-popover"><span class="lane-title">${esc(c.title)}</span><span class="lane-description">${esc(c.subtitle)}</span></button></section>`).join("");
    const matches=searchMatches();const matched=matches&&new Set(matches.map(n=>n.id));
    $("nodes").innerHTML=project.nodes.map(n=>`<button class="node ${chapter===n.chapterId?"chapter-member":""} ${selected?.type==="node"&&selected.id===n.id?"selected":""} ${matched&&!matched.has(n.id)?"dim":""} ${linkSource===n.id?"link-source":""}" data-node="${esc(n.id)}" style="left:${n.x}px;top:${n.y}px" aria-label="${esc(n.title)} — ${esc(STATUSES[n.status])}"><div class="node-meta"><span>${esc(KINDS[n.kind])}</span><span><i class="dot ${esc(n.status)}"></i>${esc(STATUSES[n.status])}</span></div><h3>${esc(n.title)}</h3><p>${esc(n.location||n.change||n.goal)}</p><i class="port" aria-hidden="true"></i></button>`).join("");
    renderEdges();applyTransform();$("empty").hidden=project.nodes.length>0;$("map-stats").textContent=`${project.nodes.length} этапов · ${project.edges.length} переходов`;
  }
  function edgeGeometry(edge){
    const from=nodeById(edge.from),to=nodeById(edge.to);if(!from||!to)return null;
    let ax=from.x+WIDTH/2,ay=from.y+HEIGHT,bx=to.x+WIDTH/2,by=to.y;
    if(Math.abs(bx-ax)>250){const right=bx>ax;ax=from.x+(right?WIDTH:0);ay=from.y+HEIGHT/2;bx=to.x+(right?0:WIDTH);by=to.y+HEIGHT/2;const offset=Math.max(60,Math.abs(bx-ax)*.5);return {d:`M${ax},${ay} C${ax+(right?offset:-offset)},${ay} ${bx+(right?-offset:offset)},${by} ${bx},${by}`,x:(ax+bx)/2,y:(ay+by)/2-9};}
    if(by<ay){const side=Math.max(from.x,to.x)+WIDTH+30;return {d:`M${from.x+WIDTH},${from.y+HEIGHT/2} C${side+100},${from.y+HEIGHT/2} ${side+100},${to.y+HEIGHT/2} ${to.x+WIDTH},${to.y+HEIGHT/2}`,x:side+54,y:(from.y+to.y+HEIGHT)/2};}
    const offset=Math.max(25,(by-ay)/2);return {d:`M${ax},${ay} C${ax},${ay+offset} ${bx},${by-offset} ${bx},${by}`,x:(ax+bx)/2+7,y:(ay+by)/2-4};
  }
  function renderEdges(){
    $("edge-layer").innerHTML=project.edges.map(e=>{const g=edgeGeometry(e);if(!g)return "";const highlight=selected?.type==="edge"&&selected.id===e.id;return `<g class="edge-group" data-edge="${esc(e.id)}"><path class="edge-path ${esc(e.kind)} ${highlight?"selected":""}" d="${g.d}"/><path class="edge-hit" d="${g.d}"/>${e.label?`<text class="edge-label" x="${g.x}" y="${g.y}" text-anchor="middle">${esc(e.label.length>30?e.label.slice(0,29)+"…":e.label)}</text>`:""}</g>`;}).join("");
  }
  function applyTransform(){ $("world").style.transform=`translate(${transform.x}px,${transform.y}px) scale(${transform.k})`;$("zoom").textContent=Math.round(transform.k*100)+"%";positionChapterPopover(); }
  function fit(targetChapter=chapter){
    if(!project)return;const items=targetChapter?project.nodes.filter(n=>n.chapterId===targetChapter):project.nodes;const box=$("viewport").getBoundingClientRect();
    if(!items.length){const index=Math.max(0,orderedChapters().findIndex(c=>c.id===targetChapter));transform={x:30-index*LANE*.85,y:20,k:.85};applyTransform();return;}
    const minX=Math.min(...items.map(n=>n.x))-30,minY=Math.min(0,...items.map(n=>n.y))-20,maxX=Math.max(...items.map(n=>n.x+WIDTH))+30,maxY=Math.max(...items.map(n=>n.y+HEIGHT))+30;
    transform.k=Math.max(.18,Math.min(.95,(box.width-40)/(maxX-minX),(box.height-40)/(maxY-minY)));transform.x=(box.width-(maxX-minX)*transform.k)/2-minX*transform.k;transform.y=20-minY*transform.k;applyTransform();
  }
  function focusNode(id){const n=nodeById(id);if(!n)return;closeChapterPopover();selected={type:"node",id};chapter=n.chapterId;document.body.classList.add("inspector-open");const box=$("viewport").getBoundingClientRect();transform.k=Math.max(.75,Math.min(1,transform.k));transform.x=box.width/2-(n.x+WIDTH/2)*transform.k;transform.y=Math.max(30,box.height*.33)-n.y*transform.k;render();}
  function selectNode(id){closeChapterPopover();if(linking){if(!linkSource){linkSource=id;renderCanvas();$("map-hint").textContent="Выберите этап, к которому ведёт переход";}else{addEdge(linkSource,id);}}else{selected={type:"node",id};document.body.classList.add("inspector-open");render();}}
  function addEdge(from,to){if(!nodeById(from)||!nodeById(to)){toast("Сначала добавьте другой этап");return;}if(project.edges.length>=2000){toast("Достигнут предел: 2000 переходов");return;}if(from===to){toast("Выберите другой этап");return;}if(project.edges.some(e=>e.from===from&&e.to===to)){toast("Этот переход уже есть");return;}mutate(()=>{const edge={id:uid("edge"),from,to,label:"",kind:project.edges.some(e=>e.from===from)?"branch":"main"};project.edges.push(edge);selected={type:"edge",id:edge.id};});setLinking(false);document.body.classList.add("inspector-open");render();toast("Переход создан. Уточните условие справа.");}
  function setLinking(value){linking=value;linkSource=null;$("connect").setAttribute("aria-pressed",String(value));$("map-hint").textContent=value?"Выберите начало перехода, затем его конец":"Нажмите этап для подробностей. Перетаскивайте, чтобы перестроить карту.";renderCanvas();}
  function options(values,current){return Object.entries(values).map(([value,label])=>`<option value="${esc(value)}" ${value===current?"selected":""}>${esc(label)}</option>`).join("");}
  function field(label,key,value,type="textarea",values=null){const limit=key==="title"?300:key==="label"?1000:6000;return `<div class="field"><label for="field-${key}">${esc(label)}</label>${type==="select"?`<select id="field-${key}" data-field="${key}">${options(values,value)}</select>`:type==="input"?`<input id="field-${key}" data-field="${key}" maxlength="${limit}" value="${esc(value)}">`:`<textarea id="field-${key}" data-field="${key}" maxlength="${limit}">${esc(value)}</textarea>`}</div>`;}
  const closeButton=()=>`<button class="quiet mobile-back" data-action="close-inspector">Закрыть</button>`;
  function renderInspector(){
    activeField=null;
    if(!selected)document.body.classList.remove("inspector-open");
    const selectionKey=selected?`${selected.type}:${selected.id||""}`:"none";
    if(selectionKey!==renderedSelection){$("inspector").scrollTop=0;renderedSelection=selectionKey;}
    if(selected?.type==="node"){
      const n=nodeById(selected.id);if(!n){selected=null;return renderInspector();}
      const outgoing=project.edges.filter(e=>e.from===n.id),incoming=project.edges.filter(e=>e.to===n.id);
      $("inspector").innerHTML=`<div class="inspector-heading"><div><h2>Этап истории</h2><small>${esc(chapterById(n.chapterId)?.title)}</small></div>${closeButton()}</div><p class="intro-copy">Что происходит здесь и как это меняет Слизи.</p>${field("Название","title",n.title,"input")}${field("Глава / этаж","chapterId",n.chapterId,"select",Object.fromEntries(orderedChapters().map(c=>[c.id,c.title])))}<div class="field-row">${field("Тип этапа","kind",n.kind,"select",KINDS)}${field("Статус решения","status",n.status,"select",STATUSES)}</div>${field("Где происходит","location",n.location,"input")}${field("Чего хочет герой","goal",n.goal)}${field("Что делает игрок / как проходит этап","action",n.action)}${field("Как меняется герой","change",n.change)}${field("Эмоция / состояние","emotion",n.emotion,"input")}${field("Что узнаёт игрок","reveal",n.reveal)}${field("Условие входа / что необходимо","requires",n.requires)}${field("Заметки и открытые вопросы","notes",n.notes)}<section class="inspector-section"><div class="section-title"><h3>Куда дальше</h3><button data-action="connect-from">Добавить связь</button></div>${outgoing.length?outgoing.map(e=>edgeItem(e,true)).join(""):"<p class='question-note'>Нет переходов. Это финал или незаконченный путь?</p>"}<div class="field-row" style="margin-top:12px"><select id="quick-target" aria-label="Следующий этап">${project.nodes.filter(other=>other.id!==n.id).map(other=>`<option value="${esc(other.id)}">${esc(other.title)}</option>`).join("")}</select><button data-action="quick-link">Связать</button></div></section>${incoming.length?`<section class="inspector-section"><h3>Откуда приходит</h3>${incoming.map(e=>edgeItem(e,false)).join("")}</section>`:""}<section class="inspector-section"><h3>Основание</h3><ul class="sources">${n.sources.length?n.sources.map(s=>`<li>${esc(s.label)}<code>${esc(s.path)}</code></li>`).join(""):"<li>Новый этап, добавленный в редакторе.</li>"}</ul></section><div class="actions-row"><button data-action="duplicate">Дублировать</button><button class="danger" data-action="delete-node">Удалить этап</button></div>`;
      const details=document.createElement("details");details.className="extra-details";details.innerHTML="<summary>Ещё детали</summary>";
      for(const key of ["chapterId","kind","status","goal","emotion","reveal","requires","notes"]){const container=$("field-"+key)?.closest(".field");if(container)details.append(container);}
      const sourceList=$("inspector").querySelector(".sources");if(sourceList)details.append(sourceList.closest(".inspector-section"));
      for(const row of $("inspector").querySelectorAll(".field-row")){if(!row.children.length)row.remove();}
      $("inspector").insertBefore(details,$("inspector").querySelector(".inspector-section"));
      const nodeActions=$("inspector").querySelector(".actions-row");nodeActions.classList.add("node-actions");$("inspector").insertBefore(nodeActions,$("field-title").closest(".field"));
    }else if(selected?.type==="edge"){
      const e=edgeById(selected.id);if(!e){selected=null;return renderInspector();}const nodeOptions=Object.fromEntries(project.nodes.map(n=>[n.id,n.title]));
      $("inspector").innerHTML=`<div class="inspector-heading"><h2>Переход</h2>${closeButton()}</div><p class="intro-copy">Задайте направление и условие. Несколько выходов из этапа образуют развилку.</p>${field("Из этапа","from",e.from,"select",nodeOptions)}${field("В этап","to",e.to,"select",nodeOptions)}${field("Тип пути","kind",e.kind,"select",EDGE_KINDS)}${field("Подпись / условие перехода","label",e.label,"input")}<div class="actions-row"><button data-action="reverse">Развернуть</button><button class="danger" data-action="delete-edge">Удалить переход</button></div>`;
    }else if(selected?.type==="project"){
      $("inspector").innerHTML=`<div class="inspector-heading"><h2>История</h2>${closeButton()}</div>${field("Название истории","title",project.title,"input")}${field("Описание","subtitle",project.subtitle)}`;
    }else{
      const problems=project.nodes.filter(n=>!project.edges.some(e=>e.from===n.id||e.to===n.id));
      $("inspector").innerHTML=`<div class="empty-mark"><svg viewBox="0 0 32 32"><rect x="3" y="3" width="10" height="7" rx="2"/><rect x="19" y="22" width="10" height="7" rx="2"/><path d="M8 10v7h16v5m-4-5 4 5 4-5"/></svg></div><h2>От стада — и обратно</h2><p class="intro-copy">${esc(project.subtitle)}</p><div class="guide-step"><strong>Место и событие</strong>Выберите карточку, чтобы увидеть цель, действие, изменение героя и раскрытие.</div><div class="guide-step"><strong>Другой путь</strong>Связывайте любые этапы. Меняйте направление стрелки или добавляйте альтернативу.</div><div class="guide-step"><strong>Общий файл</strong>Ваши правки сохраняются в проект. Изменения Codex появятся здесь автоматически.</div><button data-action="help">Краткая справка</button><section class="inspector-section"><h3>Требует решения</h3>${project.nodes.filter(n=>n.status==="question").map(n=>`<button class="health-item" data-select-node="${esc(n.id)}">${esc(n.title)}</button>`).join("")||"<p class='intro-copy'>Нет этапов с открытыми вопросами.</p>"}${problems.length?`<h3 style="margin-top:24px">Без связей</h3>${problems.map(n=>`<button class="health-item" data-select-node="${esc(n.id)}">${esc(n.title)}</button>`).join("")}`:""}</section>`;
    }
  }
  function edgeItem(e,out){return `<div class="edge-item"><button data-select-edge="${esc(e.id)}">${esc(nodeById(out?e.to:e.from)?.title||"Этап удалён")}<small>${esc(EDGE_KINDS[e.kind])}${e.label?` · ${esc(e.label)}`:""}</small></button><button class="quiet" data-select-node="${esc(out?e.to:e.from)}" aria-label="Перейти к этапу">Открыть</button></div>`;}
  function renderOutline(){
    $("outline").innerHTML=orderedChapters().filter(c=>!chapter||chapter===c.id).map(c=>`<section class="outline-chapter ${chapter===c.id?"chapter-selected":""}" style="--accent:${color(c.color)}"><h2><button data-outline-chapter="${esc(c.id)}" aria-expanded="${editingChapterId===c.id}" aria-controls="chapter-popover">${esc(c.title)}</button></h2>${project.nodes.filter(n=>n.chapterId===c.id).sort((a,b)=>a.y-b.y||a.x-b.x).map((n,i)=>`<button class="outline-row ${selected?.id===n.id?"selected":""}" data-select-node="${esc(n.id)}"><span class="muted">${String(i+1).padStart(2,"0")}</span><div><strong>${esc(n.title)}</strong><p>${esc(n.location)} · ${esc(n.action)}</p><small>${esc(n.change||n.goal)}</small></div></button>`).join("")}</section>`).join("");
  }
  function render(){if(!project)return;if(chapter&&!chapterById(chapter))chapter=null;if(editingChapterId&&!chapterById(editingChapterId))editingChapterId=null;if(linkSource&&!nodeById(linkSource))linkSource=null;renderNavigation();renderCanvas();renderInspector();renderOutline();renderChapterPopover();updateHistory();document.title=`${project.title} — редактор пути героя`;}
  function newNode(){if(!project||project.nodes.length>=500)return;const chapterId=chapter||orderedChapters()[1]?.id||orderedChapters()[0].id;const siblings=project.nodes.filter(n=>n.chapterId===chapterId);const index=orderedChapters().findIndex(c=>c.id===chapterId);const n={id:uid("stage"),chapterId,x:index*LANE+40,y:siblings.length?Math.max(...siblings.map(n=>n.y))+190:140,title:"Новый этап",kind:"story",status:"draft",location:"",goal:"",action:"",change:"",emotion:"",reveal:"",requires:"",notes:"",sources:[]};mutate(()=>{project.nodes.push(n);selected={type:"node",id:n.id};});focusNode(n.id);$("field-title").focus();$("field-title").select();}
  function reorderChapter(id,delta){const ordered=orderedChapters();const i=ordered.findIndex(c=>c.id===id);if(i<0||i+delta<0||i+delta>=ordered.length)return;const other=ordered[i+delta];if(project.nodes.some(n=>Math.abs(n.x+(n.chapterId===id?delta*LANE:n.chapterId===other.id?-delta*LANE:0))>100000)){toast("Не хватает места для перестановки. Передвиньте крайние этапы ближе к карте.");return;}mutate(()=>{[ordered[i],ordered[i+delta]]=[ordered[i+delta],ordered[i]];for(const n of project.nodes){if(n.chapterId===id)n.x+=delta*LANE;else if(n.chapterId===other.id)n.x-=delta*LANE;}ordered.forEach((c,index)=>c.order=index);if(editingChapterId===id)transform.x-=delta*LANE*transform.k;});$("chapter-popover").querySelector(`[data-order][data-delta="${delta}"]:not(:disabled)`)?.focus({preventScroll:true});}
  function chapterAnchor(){return [...document.querySelectorAll(view==="map"?"[data-lane-chapter]":"[data-outline-chapter]")].find(el=>(el.dataset.laneChapter||el.dataset.outlineChapter)===editingChapterId);}
  function positionChapterPopover(){
    const popup=$("chapter-popover");if(popup.hidden||!editingChapterId)return;
    const anchor=chapterAnchor();if(!anchor)return;const box=anchor.getBoundingClientRect(),viewport=$(view==="map"?"viewport":"outline").getBoundingClientRect();
    const gap=8,topLimit=Math.max(gap,viewport.top+gap),bottomLimit=window.innerHeight-gap;
    popup.style.maxHeight=Math.max(100,bottomLimit-topLimit)+"px";
    const width=popup.offsetWidth,height=popup.offsetHeight;
    const beside=box.right+gap+width<=window.innerWidth-gap;
    let left=beside?box.right+gap:box.left,top=beside?box.top:box.bottom+gap;
    if(!beside&&top+height>bottomLimit&&box.top-height-gap>=topLimit)top=box.top-height-gap;
    popup.style.left=Math.max(gap,Math.min(left,window.innerWidth-width-gap))+"px";
    popup.style.top=Math.max(topLimit,Math.min(top,bottomLimit-height))+"px";
  }
  function renderChapterPopover(){
    const popup=$("chapter-popover"),c=chapterById(editingChapterId);popup.hidden=!c;if(!c)return;
    const i=orderedChapters().findIndex(item=>item.id===c.id);
    popup.innerHTML=`<div class="chapter-popover-heading"><label for="chapter-title-${esc(c.id)}">Название главы</label><button data-action="close-chapter" aria-label="Закрыть действия главы">Закрыть</button></div><input id="chapter-title-${esc(c.id)}" maxlength="300" data-chapter-title="${esc(c.id)}" value="${esc(c.title)}"><label for="chapter-description-${esc(c.id)}">Описание</label><textarea id="chapter-description-${esc(c.id)}" maxlength="3000" rows="2" data-chapter-subtitle="${esc(c.id)}">${esc(c.subtitle)}</textarea><div class="chapter-actions"><button data-order="${esc(c.id)}" data-delta="-1" ${i===0?"disabled":""}>Раньше</button><button data-order="${esc(c.id)}" data-delta="1" ${i===project.chapters.length-1?"disabled":""}>Позже</button><button class="danger" data-delete-chapter="${esc(c.id)}" ${project.chapters.length===1?"disabled title='Последнюю главу нельзя удалить'":""}>Удалить</button></div><div class="chapter-add-actions"><button data-action="chapter-add-node">Добавить этап</button><button data-action="add-chapter" ${project.chapters.length>=30?"disabled":""}>Добавить главу после</button></div>`;
    positionChapterPopover();
  }
  function closeChapterPopover(restoreFocus=false){const anchor=chapterAnchor();editingChapterId=null;$("chapter-popover").hidden=true;document.querySelectorAll("[aria-controls='chapter-popover']").forEach(el=>el.setAttribute("aria-expanded","false"));if(restoreFocus)anchor?.focus({preventScroll:true});}
  function openChapterEditor(id){
    if(!chapterById(id))return;chapter=id;editingChapterId=id;selected=null;linking=false;linkSource=null;$("connect").setAttribute("aria-pressed","false");document.body.classList.remove("inspector-open");render();
    $("chapter-popover").querySelector("input").focus({preventScroll:true});
  }
  function navigateChapter(id){
    closeChapterPopover();chapter=id;selected=null;render();const index=orderedChapters().findIndex(c=>c.id===id);
    transform={k:.85,x:24-index*LANE*.85,y:20};applyTransform();
  }
  function addChapter(){
    if(project.chapters.length>=30){toast("Достигнут предел: 30 глав");return;}
    const ordered=orderedChapters(),index=ordered.findIndex(c=>c.id===editingChapterId)+1,id=uid("chapter");
    if(project.nodes.some(n=>ordered.findIndex(c=>c.id===n.chapterId)>=index&&n.x+LANE>100000)){toast("Не хватает места для новой главы. Передвиньте крайние этапы ближе к карте.");return;}
    mutate(()=>{for(const n of project.nodes){if(ordered.findIndex(c=>c.id===n.chapterId)>=index)n.x+=LANE;}ordered.splice(index,0,{id,title:"Новая глава",subtitle:"",color:"#8ae1b8",order:index});ordered.forEach((c,i)=>c.order=i);project.chapters=ordered;chapter=id;selected=null;editingChapterId=id;});
    navigateChapter(id);openChapterEditor(id);$("chapter-popover").querySelector("input").select();
  }
  function beginChapterDeletion(id){
    if(project.chapters.length<=1){toast("В карте должна остаться хотя бы одна глава");return;}
    const item=chapterById(id);if(!item)return;pendingChapterId=id;
    const count=project.nodes.filter(n=>n.chapterId===id).length;
    $("delete-chapter-summary").textContent=`«${item.title}» · этапов: ${count}`;
    $("delete-chapter-target").innerHTML=options(Object.fromEntries(orderedChapters().filter(c=>c.id!==id).map(c=>[c.id,c.title])),"");
    $("delete-chapter-options").hidden=count===0;$("delete-chapter-mode").value=count?"move":"delete";
    updateChapterDeletion();$("delete-chapter-dialog").showModal();
  }
  function updateChapterDeletion(){
    const ids=new Set(project.nodes.filter(n=>n.chapterId===pendingChapterId).map(n=>n.id));
    const moving=ids.size>0&&$("delete-chapter-mode").value==="move";
    $("delete-chapter-destination").hidden=!moving;
    const edgeCount=project.edges.filter(e=>ids.has(e.from)||ids.has(e.to)).length;
    $("delete-chapter-consequence").textContent=moving?"Этапы появятся ниже существующих в выбранной главе. Все их связи сохранятся.":ids.size?`Будут удалены этапы: ${ids.size}, связанные переходы: ${edgeCount}. Остальные главы сохранятся.`:"Пустая глава будет удалена. Этапы и связи сохранятся.";
    $("confirm-delete-chapter").textContent=moving?"Перенести и удалить главу":"Удалить главу";
  }
  function confirmChapterDeletion(){
    const id=pendingChapterId;if(!id||!chapterById(id)||project.chapters.length<=1)return;
    const ordered=orderedChapters(),before=new Map(ordered.map((c,i)=>[c.id,i]));
    const removed=project.nodes.filter(n=>n.chapterId===id),removedIds=new Set(removed.map(n=>n.id));
    const moving=removed.length>0&&$("delete-chapter-mode").value==="move";
    const targetId=$("delete-chapter-target").value;
    if(moving&&(!chapterById(targetId)||targetId===id)){toast("Выберите другую главу");return;}
    const remaining=ordered.filter(c=>c.id!==id),after=new Map(remaining.map((c,i)=>[c.id,i]));
    const firstY=removed.length?Math.min(...removed.map(n=>n.y)):140;
    const targetNodes=project.nodes.filter(n=>n.chapterId===targetId);
    const nextY=targetNodes.length?Math.max(...targetNodes.map(n=>n.y))+HEIGHT+50:140;
    const positions=new Map();
    for(const node of project.nodes){
      if(removedIds.has(node.id)&&!moving)continue;
      const targetChapter=removedIds.has(node.id)?targetId:node.chapterId;
      const x=node.x+(after.get(targetChapter)-before.get(node.chapterId))*LANE;
      const y=removedIds.has(node.id)?nextY+node.y-firstY:node.y;
      if(Math.abs(x)>100000||Math.abs(y)>100000){toast("Не хватает места для переноса. Выберите другую главу или измените расположение этапов.");return;}
      positions.set(node.id,{x,y,chapterId:targetChapter});
    }
    $("delete-chapter-dialog").close();
    mutate(()=>{
      project.chapters=remaining;project.chapters.forEach((c,i)=>c.order=i);
      if(!moving){project.nodes=project.nodes.filter(n=>!removedIds.has(n.id));project.edges=project.edges.filter(e=>!removedIds.has(e.from)&&!removedIds.has(e.to));}
      for(const node of project.nodes)Object.assign(node,positions.get(node.id));
      if(chapter===id)chapter=moving?targetId:null;
      selected=null;editingChapterId=null;
    });
    toast(moving?"Этапы перенесены, глава удалена. Можно отменить.":"Глава удалена. Можно отменить.");
  }
  function handleField(event){
    const input=event.target;const key=input.dataset.field;if(!key)return;const target=selected?.type==="node"?nodeById(selected.id):selected?.type==="edge"?edgeById(selected.id):selected?.type==="project"?project:null;if(!target)return;
    if(activeField!==input){remember();activeField=input;}
    if(selected.type==="edge"&&(key==="from"||key==="to")){const from=key==="from"?input.value:target.from,to=key==="to"?input.value:target.to;if(from===to||project.edges.some(e=>e.id!==target.id&&e.from===from&&e.to===to)){input.value=target[key];toast("Такой переход уже есть или ведёт в тот же этап");return;}}
    if(key==="chapterId"){const ordered=orderedChapters();const before=ordered.findIndex(c=>c.id===target.chapterId),after=ordered.findIndex(c=>c.id===input.value);target.x+=(after-before)*LANE;}
    target[key]=input.value;changed();renderCanvas();renderNavigation();renderOutline();
  }
  $("inspector").addEventListener("input",handleField);
  $("inspector").addEventListener("focusout",()=>{activeField=null;});
  $("chapter-popover").addEventListener("input",(event)=>{const id=event.target.dataset.chapterTitle||event.target.dataset.chapterSubtitle,c=chapterById(id);if(!c)return;if(activeField!==event.target){remember();activeField=event.target;}c[event.target.dataset.chapterTitle?"title":"subtitle"]=event.target.value;changed();renderNavigation();renderCanvas();renderOutline();positionChapterPopover();});
  $("chapter-popover").addEventListener("focusout",()=>{activeField=null;});
  document.addEventListener("click",(event)=>{
    const header=event.target.closest("[data-lane-chapter],[data-outline-chapter]");if(header){openChapterEditor(header.dataset.laneChapter||header.dataset.outlineChapter);return;}
    const select=event.target.closest("[data-select-node]");if(select){focusNode(select.dataset.selectNode);return;}
    const edge=event.target.closest("[data-select-edge]");if(edge){selected={type:"edge",id:edge.dataset.selectEdge};render();return;}
    const order=event.target.closest("[data-order]");if(order){reorderChapter(order.dataset.order,Number(order.dataset.delta));return;}
    const deletion=event.target.closest("[data-delete-chapter]");if(deletion){beginChapterDeletion(deletion.dataset.deleteChapter);return;}
    const action=event.target.closest("[data-action]")?.dataset.action;if(!action)return;
    const n=selected?.type==="node"?nodeById(selected.id):null;const e=selected?.type==="edge"?edgeById(selected.id):null;
    if(action==="close-inspector")document.body.classList.remove("inspector-open");
    if(action==="close-chapter")closeChapterPopover(true);
    if(action==="chapter-add-node"){closeChapterPopover();newNode();}
    if(action==="help")$("help-dialog").showModal();
    if(action==="connect-from"&&n){setLinking(true);linkSource=n.id;renderCanvas();$("map-hint").textContent="Выберите следующий этап на карте";document.body.classList.remove("inspector-open");}
    if(action==="quick-link"&&n)addEdge(n.id,$("quick-target").value);
    if(action==="delete-node"&&n){if(!confirm(`Удалить «${n.title}» и все его переходы? Можно отменить.`))return;mutate(()=>{project.nodes=project.nodes.filter(v=>v.id!==n.id);project.edges=project.edges.filter(v=>v.from!==n.id&&v.to!==n.id);selected=null;});toast("Этап удалён. Ctrl+Z — вернуть.");}
    if(action==="duplicate"&&n){if(project.nodes.length>=500){toast("Достигнут предел: 500 этапов");return;}mutate(()=>{const copy={...clone(n),id:uid("stage"),title:n.title.slice(0,289)+" · вариант",x:Math.min(99000,n.x+35),y:Math.min(99000,n.y+170)};project.nodes.push(copy);selected={type:"node",id:copy.id};});focusNode(selected.id);}
    if(action==="delete-edge"&&e)mutate(()=>{project.edges=project.edges.filter(v=>v.id!==e.id);selected=null;});
    if(action==="reverse"&&e){if(project.edges.some(v=>v.id!==e.id&&v.from===e.to&&v.to===e.from)){toast("Обратный переход уже существует");return;}mutate(()=>{[e.from,e.to]=[e.to,e.from];});}
    if(action==="add-chapter")addChapter();
  });
  $("chapters").onclick=(event)=>{const button=event.target.closest("[data-chapter]");if(button)navigateChapter(button.dataset.chapter);};
  $("overview").onclick=()=>{closeChapterPopover();chapter=null;render();fit(null);};
  $("viewport").addEventListener("pointerdown",(event)=>{
    if(event.target.closest("[data-lane-chapter]"))return;
    closeChapterPopover();
    if(!project||event.button!==0)return;const card=event.target.closest("[data-node]"),edge=event.target.closest("[data-edge]");if(edge){selected={type:"edge",id:edge.dataset.edge};document.body.classList.add("inspector-open");render();return;}if(card&&linking){selectNode(card.dataset.node);return;}
    const n=card&&nodeById(card.dataset.node);drag={pointer:event.pointerId,startX:event.clientX,startY:event.clientY,tx:transform.x,ty:transform.y,node:n,id:n?.id,nx:n?.x,ny:n?.y,moved:false};$("viewport").setPointerCapture(event.pointerId);
  });
  $("viewport").addEventListener("pointermove",(event)=>{
    if(!drag||event.pointerId!==drag.pointer)return;const dx=event.clientX-drag.startX,dy=event.clientY-drag.startY;if(!drag.moved&&Math.hypot(dx,dy)>4){drag.moved=true;if(drag.node)remember();}if(!drag.moved)return;
    if(drag.node){drag.node.x=Math.max(10,Math.min(project.chapters.length*LANE-WIDTH-10,drag.nx+dx/transform.k));drag.node.y=Math.max(115,Math.min(99000,drag.ny+dy/transform.k));const el=[...$("nodes").children].find(v=>v.dataset.node===drag.id);if(el){el.style.left=drag.node.x+"px";el.style.top=drag.node.y+"px";}renderEdges();}else{transform.x=drag.tx+dx;transform.y=drag.ty+dy;applyTransform();}
  });
  function endDrag(event){if(!drag||event.pointerId!==drag.pointer)return;const old=drag;drag=null;if($("viewport").hasPointerCapture(event.pointerId))$("viewport").releasePointerCapture(event.pointerId);if(old.node&&old.moved){const target=orderedChapters()[Math.max(0,Math.min(project.chapters.length-1,Math.floor((old.node.x+WIDTH/2)/LANE)))];old.node.chapterId=target.id;old.node.x=Math.round(old.node.x/5)*5;old.node.y=Math.round(old.node.y/5)*5;selected={type:"node",id:old.id};changed();render();}else if(old.node){selectNode(old.id);}else if(!old.moved){selected=null;chapter=null;document.body.classList.remove("inspector-open");render();}suppressClick=true;setTimeout(()=>suppressClick=false,0);}
  $("viewport").addEventListener("pointerup",endDrag);$("viewport").addEventListener("pointercancel",endDrag);
  $("nodes").addEventListener("click",(event)=>{if(event.detail===0&&!suppressClick){const card=event.target.closest("[data-node]");if(card)selectNode(card.dataset.node);}});
  function zoom(factor,x,y){const box=$("viewport").getBoundingClientRect();x??=box.width/2;y??=box.height/2;const next=Math.max(.15,Math.min(1.7,transform.k*factor));transform.x=x-(x-transform.x)*next/transform.k;transform.y=y-(y-transform.y)*next/transform.k;transform.k=next;applyTransform();}
  $("viewport").addEventListener("wheel",event=>{event.preventDefault();const box=$("viewport").getBoundingClientRect();zoom(Math.exp(-event.deltaY*.0015),event.clientX-box.left,event.clientY-box.top);},{passive:false});
  $("zoom-in").onclick=()=>zoom(1.2);$("zoom-out").onclick=()=>zoom(1/1.2);$("fit").onclick=()=>fit();
  $("map-view").onclick=()=>setView("map");$("list-view").onclick=()=>setView("list");
  function setView(value){closeChapterPopover();view=value;$("viewport").hidden=view!=="map";$("outline").hidden=view!=="list";$("map-view").setAttribute("aria-pressed",String(view==="map"));$("list-view").setAttribute("aria-pressed",String(view==="list"));renderOutline();}
  $("add-node").onclick=newNode;$("connect").onclick=()=>{if(view!=="map")setView("map");setLinking(!linking);};$("undo").onclick=undo;$("redo").onclick=redo;
  $("search").oninput=()=>{if(project){renderSearch();renderCanvas();}};$("export").onclick=exportProject;$("import").onclick=()=>$("import-file").click();$("import-file").onchange=(e)=>importProject(e.target.files[0]);$("help").onclick=()=>$("help-dialog").showModal();$("edit-project").onclick=()=>{closeChapterPopover();selected={type:"project"};document.body.classList.add("inspector-open");renderInspector();};
  $("delete-chapter-mode").onchange=updateChapterDeletion;$("cancel-delete-chapter").onclick=()=>$("delete-chapter-dialog").close();$("confirm-delete-chapter").onclick=confirmChapterDeletion;
  $("delete-chapter-dialog").addEventListener("close",()=>{pendingChapterId=null;});
  document.addEventListener("keydown",(event)=>{
    if($("delete-chapter-dialog").open)return;
    if(event.key==="Escape"){if(editingChapterId){closeChapterPopover(true);return;}if(linking)setLinking(false);document.body.classList.remove("inspector-open");return;}
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==="s"){event.preventDefault();save();return;}
    if(isTextInput(event.target)||$("help-dialog").open)return;
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==="z"){event.preventDefault();event.shiftKey?redo():undo();}
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==="y"){event.preventDefault();redo();}
    if(event.key.toLowerCase()==="f")fit();
  });
  document.addEventListener("click",(event)=>{const menu=document.querySelector(".file-menu");if(!menu)return;if(event.target.closest(".menu-content button")||!event.target.closest(".file-menu"))menu.open=false;});
  document.addEventListener("pointerdown",(event)=>{if(!event.target.closest("#chapter-popover,[data-lane-chapter],[data-outline-chapter],#delete-chapter-dialog,.zoom-controls"))closeChapterPopover();});
  window.addEventListener("resize",positionChapterPopover);$("outline").addEventListener("scroll",positionChapterPopover);
  window.addEventListener("beforeunload",(event)=>{if(dirty){writeDraft();event.preventDefault();event.returnValue="";}});
  async function start(){
    try{const remote=await fetchProject();project=validate(remote.project);revision=remote.revision;chapter=null;transform={x:30,y:15,k:.85};render();saveState("Сохранено в проект");
      let draft;try{draft=JSON.parse(localStorage.getItem(DRAFT_KEY));}catch{draft=null;}
      if(draft?.project&&JSON.stringify(draft.project)!==JSON.stringify(project)){paused=true;showNotice("В браузере остался несохранённый черновик предыдущего сеанса.",[["Восстановить черновик",()=>{try{validate(draft.project);remember();project=draft.project;paused=false;hideNotice();changed();render();}catch(error){toast(error.message);}}],["Оставить файл",()=>{localStorage.removeItem(DRAFT_KEY);paused=false;hideNotice();}]]);}
      setInterval(poll,4000);
    }catch(error){saveState("Нет подключения",true);showNotice(`Не удалось открыть карту: ${error.message}. Запустите run_hero_journey.cmd из папки проекта.`,[["Подключиться",start]]);$("inspector").innerHTML="<h2>Карта недоступна</h2><p class='intro-copy'>Редактору нужен локальный сервер, чтобы сохранять общий файл. Запустите run_hero_journey.cmd, затем обновите страницу.</p>";}
  }
  start();
})();

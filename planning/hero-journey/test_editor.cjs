"use strict";
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "C:/Users/Danil/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

const root = path.resolve(__dirname, "../..");
const source = path.join(root, "planning/hero-journey");
const output = path.join(root, "output/hero_journey");
const copy = path.join(output, "qa-copy", "planning", "hero-journey");
const base = "http://127.0.0.1:8768";
const python = process.env.PYTHON_EXE || "C:/Users/Danil/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
const mainPath = path.join(source, "journey.json");
const mainHash = crypto.createHash("sha256").update(fs.readFileSync(mainPath)).digest("hex");
const original = JSON.parse(fs.readFileSync(mainPath, "utf8"));
fs.mkdirSync(copy, { recursive: true });
for (const name of ["server.py", "app.js", "styles.css", "index.html", "journey.json"]) {
  fs.copyFileSync(path.join(source, name), path.join(copy, name));
}
const stdout = fs.openSync(path.join(output, "ui-server.stdout.log"), "w");
const stderr = fs.openSync(path.join(output, "ui-server.stderr.log"), "w");
const server = spawn(python, [path.join(copy, "server.py"), "--port", "8768"], { windowsHide: true, stdio: ["ignore", stdout, stderr], cwd: copy });
const results = [];
const errors = [];
const expectedHTTP = [];
let browser, page, context;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const clone = v => JSON.parse(JSON.stringify(v));
async function until(fn, message, timeout = 11000) {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try { last = await fn(); if (last) return last; } catch (error) { last = error.message; }
    await delay(80);
  }
  throw new Error(message + " (last: " + String(last) + ")");
}
async function get() {
  const response = await fetch(base + "/api/project");
  assert.equal(response.status, 200);
  return response.json();
}
async function put(project, revision) {
  const response = await fetch(base + "/api/project", { method: "PUT", headers: { Origin: base, "Content-Type": "application/json" }, body: JSON.stringify({ project, revision }) });
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return body;
}
async function disk(predicate, message) {
  return until(async () => { const data = await get(); return predicate(data.project) && data.project; }, message);
}
async function saved() {
  await until(async () => (await page.locator("#save-state").textContent()).includes("Сохранено"), "UI did not report saved");
}
async function openMenu() {
  const menu=page.locator("details.file-menu");
  if(await menu.count() && !(await menu.evaluate(el=>el.open))) await menu.locator("summary").click();
}
async function closeMenu() {
  const menu=page.locator("details.file-menu");
  if(await menu.count() && await menu.evaluate(el=>el.open)) await menu.locator("summary").click();
}
async function choose(id) {
  await openMenu();
  await page.locator("#search").fill(id);
  const target = page.locator('#search-results [data-select-node="' + id + '"]');
  if (await target.count()) await target.click();
  else {
    const data = await get();
    const node = data.project.nodes.find(n => n.id === id);
    await page.locator("#search").fill(node.title);
    await page.locator('#search-results [data-select-node="' + id + '"]').click();
  }
  await openMenu();
  await page.locator("#search").fill("");
  await closeMenu();
  const details=page.locator("#inspector details.extra-details");
  if(await details.count() && !(await details.evaluate(el=>el.open))) await details.locator("summary").click();
}
async function reset() {
  const current = await get();
  await put(clone(original), current.revision);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.locator('.node[data-node="r01"]').waitFor();
}
async function test(name, fn) {
  const started = Date.now();
  try { await fn(); results.push({name, status:"PASS", ms:Date.now()-started}); console.log("PASS " + name); }
  catch (error) {
    results.push({name, status:"FAIL", ms:Date.now()-started, error:error.stack});
    console.error("FAIL " + name + ": " + error.message);
    await page.screenshot({path:path.join(output, "failure-" + results.length + ".png"), fullPage:true}).catch(()=>{});
    await reset();
  }
}
(async () => {
 try {
  await until(async () => { const r = await fetch(base + "/api/health"); return r.ok; }, "Isolated server did not start", 12000);
  browser = await chromium.launch({headless:true});
  context = await browser.newContext({viewport:{width:1440,height:900},acceptDownloads:true});
  page = await context.newPage();
  page.on("pageerror", error=>errors.push(error.message));
  page.on("response", response=>{ if(response.status()>=400) expectedHTTP.push({status:response.status(),url:response.url()}); });
  page.on("dialog", dialog=>dialog.accept());
  await page.goto(base);
  await page.locator('.node[data-node="r01"]').waitFor();
  await page.screenshot({path:path.join(output,"desktop-initial.png"),fullPage:true});
  await choose("r04");
  if(await page.locator("#inspector details.extra-details[open]").count()) await page.locator("#inspector details.extra-details summary").click();
  await page.locator("#inspector").evaluate(el=>el.scrollTop=0);
  await page.screenshot({path:path.join(output,"desktop-editor.png"),fullPage:true});
  const mobilePreview=await context.newPage();
  await mobilePreview.setViewportSize({width:390,height:844});
  await mobilePreview.goto(base);
  await mobilePreview.locator('.node[data-node="r01"]').waitFor();
  await mobilePreview.screenshot({path:path.join(output,"mobile-390-initial.png"),fullPage:true});
  await mobilePreview.locator("#list-view").click();
  await mobilePreview.screenshot({path:path.join(output,"mobile-390-list.png"),fullPage:true});
  await mobilePreview.locator('#outline [data-select-node="r01"]').click();
  await mobilePreview.screenshot({path:path.join(output,"mobile-390-editor.png"),fullPage:true});
  await mobilePreview.close();
  console.log("SCREENSHOTS_READY light design: desktop-initial.png desktop-editor.png mobile-390-*.png");
  await reset();
  await test("load + chapter navigation + outline + search", async()=>{
    assert.equal(await page.locator(".node").count(), original.nodes.length);
    assert.equal(await page.locator(".chapter-button").count(), 6);
    await page.locator('[data-chapter="reception"]').click();
    await page.locator("#list-view").click();
    assert.equal(await page.locator(".outline-row").count(),original.nodes.filter(n=>n.chapterId==="reception").length);
    await page.locator('#outline [data-select-node="r04"]').click();
    assert.equal(await page.locator("#field-title").inputValue(), original.nodes.find(n=>n.id==="r04").title);
    await page.locator("#map-view").click();
    await choose("m03");
    assert.match(await page.locator("#field-reveal").inputValue(),/приказ/);
  });
  await test("edit all narrative fields + dropdowns + autosave + reload", async()=>{
    await choose("r01");
    const fields = ["title","location","goal","action","change","emotion","reveal","requires","notes"];
    for(const field of fields) await page.locator("#field-"+field).fill("QA "+field+" — проверка сохранения");
    await page.locator("#field-kind").selectOption("discovery");
    await page.locator("#field-status").selectOption("question");
    await disk(p=>fields.every(f=>p.nodes.find(n=>n.id==="r01")[f]==="QA "+f+" — проверка сохранения"),"Narrative fields not saved");
    await saved();
    await page.reload();
    await choose("r01");
    for(const field of fields) assert.equal(await page.locator("#field-"+field).inputValue(),"QA "+field+" — проверка сохранения");
    assert.equal(await page.locator("#field-kind").inputValue(),"discovery");
    assert.equal(await page.locator("#field-status").inputValue(),"question");
  });
  await test("add + duplicate + delete node with undo and redo", async()=>{
    await page.locator("#add-node").click();
    await page.locator("#field-title").fill("QA созданный этап");
    let p = await disk(p=>p.nodes.some(n=>n.title==="QA созданный этап"),"New node not saved");
    const id=p.nodes.find(n=>n.title==="QA созданный этап").id;
    const count=p.nodes.length;
    await page.locator('[data-action="duplicate"]').click();
    p=await disk(p=>p.nodes.length===count+1,"Duplicate not saved");
    const copyId=p.nodes.find(n=>n.title==="QA созданный этап · вариант").id;
    await page.locator("#undo").click();
    await disk(p=>!p.nodes.some(n=>n.id===copyId),"Undo duplicate failed");
    await page.locator("#redo").click();
    await disk(p=>p.nodes.some(n=>n.id===copyId),"Redo duplicate failed");
    await choose(copyId);
    await page.locator('[data-action="delete-node"]').click();
    await disk(p=>!p.nodes.some(n=>n.id===copyId),"Delete failed");
    await page.locator("#undo").click();
    await disk(p=>p.nodes.some(n=>n.id===copyId),"Undo deletion failed");
    await page.locator("#redo").click();
    await disk(p=>!p.nodes.some(n=>n.id===copyId),"Redo deletion failed");
    await choose(id);
  });
  await test("create + label + reverse + delete edge + undo/redo", async()=>{
    const before=(await get()).project;
    const id=before.nodes.find(n=>n.title==="QA созданный этап").id;
    await choose(id);
    await page.locator("#quick-target").selectOption("r01");
    await page.locator('[data-action="quick-link"]').click();
    await page.locator("#field-label").fill("QA альтернативный переход");
    await page.locator("#field-kind").selectOption("branch");
    let p=await disk(p=>p.edges.some(e=>e.from===id&&e.to==="r01"&&e.label==="QA альтернативный переход"&&e.kind==="branch"),"New edge not saved");
    const edgeId=p.edges.find(e=>e.from===id&&e.to==="r01").id;
    await page.locator('[data-action="reverse"]').click();
    await disk(p=>p.edges.some(e=>e.id===edgeId&&e.from==="r01"&&e.to===id),"Reverse edge failed");
    await page.locator('[data-action="delete-edge"]').click();
    await disk(p=>!p.edges.some(e=>e.id===edgeId),"Delete edge failed");
    await page.locator("#undo").click();
    await disk(p=>p.edges.some(e=>e.id===edgeId),"Undo edge deletion failed");
    await page.locator("#redo").click();
    await disk(p=>!p.edges.some(e=>e.id===edgeId),"Redo edge deletion failed");
  });
  await test("select SVG edge with actual pointer", async()=>{
    await choose("r01");
    const edgeId="edge-r01-r02";
    const point=await page.locator('[data-edge="'+edgeId+'"] .edge-hit').evaluate(path=>{
      const p=path.getPointAtLength(path.getTotalLength()/2);
      const transformed=new DOMPoint(p.x,p.y).matrixTransform(path.getScreenCTM());
      return {x:transformed.x,y:transformed.y};
    });
    await page.mouse.click(point.x,point.y);
    await page.locator("#field-from").waitFor({timeout:3000});
    assert.equal(await page.locator("#field-from").inputValue(),"r01");
    assert.equal(await page.locator("#field-to").inputValue(),"r02");
  });
  await test("connect mode chooses two cards with actual pointer", async()=>{
    await page.locator("#overview").click();
    await page.locator("#connect").click();
    await page.locator('.node[data-node="p01"]').click();
    await page.locator('.node[data-node="m03"]').click();
    const p=await disk(p=>p.edges.some(e=>e.from==="p01"&&e.to==="m03"),"Two-card connection failed");
    assert.equal(p.edges.find(e=>e.from==="p01"&&e.to==="m03").kind,"branch");
    await page.locator('[data-action="delete-edge"]').click();
    await disk(p=>!p.edges.some(e=>e.from==="p01"&&e.to==="m03"),"Temporary connection not removed");
  });
  await test("drag card into adjacent chapter + persistent coordinates", async()=>{
    await choose("r01");
    const card=page.locator('.node[data-node="r01"]');
    const box=await card.boundingBox();
    const scale=box.width/(await card.evaluate(el=>el.offsetWidth));
    const start={x:box.x+box.width/2,y:box.y+40*scale};
    const old=(await get()).project.nodes.find(n=>n.id==="r01");
    await page.mouse.move(start.x,start.y);
    await page.mouse.down();
    await page.mouse.move(start.x+400*scale,start.y+40*scale,{steps:18});
    await page.mouse.up();
    const p=await disk(p=>p.nodes.find(n=>n.id==="r01").chapterId==="utility","Drag did not change chapter");
    const n=p.nodes.find(n=>n.id==="r01");
    assert(n.x>=old.x+390&&n.y>=old.y+30);
    await page.reload(); await choose("r01");
    assert.equal(await page.locator("#field-chapterId").inputValue(),"utility");
    assert.equal((await get()).project.nodes.find(n=>n.id==="r01").x,n.x);
  });
  await test("chapter reorder moves its nodes + undo", async()=>{
    const before=clone((await get()).project);
    await page.locator('#chapters [data-chapter="prologue"]').click();
    await page.locator('[data-lane-chapter="prologue"]').click();
    await page.locator('[data-order="prologue"][data-delta="1"]').click();
    const changed=await disk(p=>p.chapters.find(c=>c.id==="prologue").order===1,"Chapter reorder not saved");
    assert.equal(changed.nodes.find(n=>n.id==="p01").x,before.nodes.find(n=>n.id==="p01").x+400);
    await page.locator("#undo").click();
    await disk(p=>p.chapters.find(c=>c.id==="prologue").order===0,"Chapter reorder undo failed");
  });
  await test("export/import full roundtrip + invalid import preserves map", async()=>{
    const current=(await get()).project;
    const downloadPromise=page.waitForEvent("download");
    await openMenu();
    await page.locator("#export").click();
    await closeMenu();
    const download=await downloadPromise;
    const exported=path.join(output,"ui-export.json");
    await download.saveAs(exported);
    assert.deepEqual(JSON.parse(fs.readFileSync(exported,"utf8")),current);
    await page.locator("#add-node").click();
    await page.locator("#field-title").fill("QA временный перед импортом");
    await disk(p=>p.nodes.length===current.nodes.length+1,"Pre-import edit failed");
    await page.locator("#import-file").setInputFiles(exported);
    await disk(p=>JSON.stringify(p)===JSON.stringify(current),"Import roundtrip not equal");
    await saved();
    for(const bad of [
      {label:"missing-id",mutate:p=>delete p.id},
      {label:"dangling-edge",mutate:p=>p.edges[0].to="does-not-exist"},
      {label:"unknown-field",mutate:p=>p.nodes[0].extra="invalid"}
    ]) {
      const invalid=clone(current); bad.mutate(invalid);
      const before=(await get()).revision;
      await page.locator("#import-file").setInputFiles({name:bad.label+".json",mimeType:"application/json",buffer:Buffer.from(JSON.stringify(invalid))});
      await until(async()=> (await page.locator("#toast").textContent()).includes("Импорт отменён"),"Invalid import did not report failure");
      await delay(800);
      assert.equal((await get()).revision,before,"Invalid import mutated server");
      assert.equal(await page.locator(".node").count(),current.nodes.length);
    }
  });
  await test("external file change automatically refreshes idle editor", async()=>{
    const current=(await get()).project;
    current.nodes.find(n=>n.id==="p01").title="QA внешняя файловая правка";
    fs.writeFileSync(path.join(copy,"journey.json"),JSON.stringify(current,null,2)+"\n");
    await until(async()=> (await page.locator('.node[data-node="p01"] h3').textContent())==="QA внешняя файловая правка","External file change did not refresh",10000);
    await choose("p01");
    assert.equal(await page.locator("#field-title").inputValue(),"QA внешняя файловая правка");
  });
  await test("concurrent edit conflict preserves local draft and accepts file", async()=>{
    await choose("p01");
    const external=await get();
    external.project.nodes.find(n=>n.id==="p01").title="QA версия из файла";
    await page.locator("#field-title").fill("QA моя конфликтная версия");
    await put(external.project,external.revision);
    await page.getByRole("button",{name:"Принять файл",exact:true}).waitFor({timeout:6000});
    assert.equal((await get()).project.nodes.find(n=>n.id==="p01").title,"QA версия из файла");
    const draft=await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith("slizi-hero-journey-draft:")).map(k=>localStorage.getItem(k)).join(""));
    assert.match(draft,/QA моя конфликтная версия/);
    await page.getByRole("button",{name:"Принять файл",exact:true}).click();
    assert.equal(await page.locator("#field-title").inputValue(),"QA версия из файла");
  });
  await test("concurrent edit conflict explicit keep-my-version", async()=>{
    await choose("p01");
    const external=await get();
    external.project.nodes.find(n=>n.id==="p01").title="QA другая внешняя версия";
    await page.locator("#field-title").fill("QA явно сохранить мою");
    await put(external.project,external.revision);
    await page.getByRole("button",{name:"Сохранить мою",exact:true}).waitFor({timeout:6000});
    await page.getByRole("button",{name:"Сохранить мою",exact:true}).click();
    await disk(p=>p.nodes.find(n=>n.id==="p01").title==="QA явно сохранить мою","Keep my version did not persist");
    await saved();
  });
  await reset();
  await page.screenshot({path:path.join(output,"desktop-initial.png"),fullPage:true});
  await page.locator("#overview").click();
  await page.screenshot({path:path.join(output,"desktop-overview.png"),fullPage:true});
  await choose("r04");
  const expanded=page.locator("#inspector details.extra-details[open]");
  if(await expanded.count()) await expanded.locator("summary").click();
  await page.locator("#inspector").evaluate(el=>el.scrollTop=0);
  await page.screenshot({path:path.join(output,"desktop-editor.png"),fullPage:true});
  const mobile=await context.newPage({viewport:{width:390,height:844}});
  await mobile.setViewportSize({width:390,height:844});
  mobile.on("pageerror",e=>errors.push("mobile: "+e.message));
  await mobile.goto(base);
  await mobile.locator('.node[data-node="r01"]').waitFor();
  await mobile.screenshot({path:path.join(output,"mobile-390-initial.png"),fullPage:true});
  await mobile.locator("#list-view").click();
  await mobile.screenshot({path:path.join(output,"mobile-390-list.png"),fullPage:true});
  await mobile.locator('#outline [data-select-node="r01"]').click();
  assert.equal(await mobile.locator("#field-title").inputValue(),original.nodes.find(n=>n.id==="r01").title);
  await mobile.screenshot({path:path.join(output,"mobile-390-editor.png"),fullPage:true});
  await mobile.locator('[data-action="close-inspector"]').click();
  assert.equal(await mobile.locator("body").evaluate(el=>el.classList.contains("inspector-open")),false);
  results.push({name:"390px mobile list/open editor/close + desktop and mobile screenshots",status:"PASS"});
  assert.deepEqual(errors,[],"Browser JavaScript errors");
 } catch(error) {
   results.push({name:"runner",status:"FAIL",error:error.stack});
   console.error(error.stack);
 } finally {
   if(browser) await browser.close();
   server.kill();
   fs.closeSync(stdout); fs.closeSync(stderr);
   const unchanged=crypto.createHash("sha256").update(fs.readFileSync(mainPath)).digest("hex")===mainHash;
   results.push({name:"main journey.json SHA256 unchanged",status:unchanged?"PASS":"FAIL",sha256:mainHash});
   const report={results,browserErrors:errors,httpErrors:expectedHTTP,sourceHashes:Object.fromEntries(["app.js","styles.css","server.py"].map(n=>[n,crypto.createHash("sha256").update(fs.readFileSync(path.join(copy,n))).digest("hex")]))};
   fs.writeFileSync(path.join(output,"UI_QA_RESULTS.json"),JSON.stringify(report,null,2)+"\n");
   console.log(JSON.stringify({passed:results.filter(r=>r.status==="PASS").length,failed:results.filter(r=>r.status==="FAIL").length,browserErrors:errors.length,mainUnchanged:unchanged,report:path.join(output,"UI_QA_RESULTS.json")}));
   process.exitCode=results.some(r=>r.status==="FAIL")||errors.length?1:0;
 }
})();

"use strict";
// Focused UI regression checks. All mutations target a disposable copy on port 8768.
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const net = require("node:net");
const { spawn } = require("node:child_process");
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "C:/Users/Danil/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
const root = path.resolve(__dirname, "../..");
const source = path.join(root, "planning/hero-journey");
const output = path.join(root, "output/hero_journey/inline_chapters");
const copy = path.join(output, "qa-copy/planning/hero-journey");
const base = "http://127.0.0.1:8768";
const python = process.env.PYTHON_EXE || "C:/Users/Danil/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
const mainPath = path.join(source, "journey.json");
const hash = filename => crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex");
const initialMainHash = hash(mainPath);
const original = JSON.parse(fs.readFileSync(mainPath, "utf8"));
const clone = value => JSON.parse(JSON.stringify(value));
const ordered = project => [...project.chapters].sort((a, b) => a.order - b.order);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const results = [], errors = [], httpErrors = [];
let server, browser, page, context, stdout, stderr;
let confirmAction = "accept";
async function until(fn, message, timeout = 10000) {
  let last;
  for (const end = Date.now() + timeout; Date.now() < end; await delay(80)) {
    try { last = await fn(); if (last) return last; } catch (error) { last = error.message; }
  }
  throw new Error(message + " (last: " + String(last) + ")");
}
async function get() {
  const response = await fetch(base + "/api/project");
  assert.equal(response.status, 200);
  return response.json();
}
async function disk(predicate, message) {
  return until(async () => { const { project } = await get(); return predicate(project) && project; }, message);
}
async function saved() {
  await until(async () => (await page.locator("#save-state").textContent()).includes("Сохранено"), "Save indicator did not settle");
}
async function reset(fixture = original) {
  const { revision } = await get();
  const response = await fetch(base + "/api/project", {method:"PUT",headers:{Origin:base,"Content-Type":"application/json"},body:JSON.stringify({project:clone(fixture),revision})});
  assert.equal(response.status, 200, await response.text());
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.locator("[data-lane-chapter]").first().waitFor();
  await until(async () => await page.locator(".chapter-button").count() === fixture.chapters.length, "Fixture did not load");
}
async function choose(id, target = page) {
  const node = (await get()).project.nodes.find(n => n.id === id);
  await target.locator('[data-chapter="' + node.chapterId + '"]').click();
  await target.locator("#list-view").click();
  await target.locator('#outline [data-select-node="' + id + '"]').click();
}
async function openChapterEditor(id, target = page) {
  const close = target.locator('[data-action="close-inspector"]');
  if(await close.isVisible()) await close.click();
  await target.locator("#map-view").click();
  await target.locator('[data-chapter="'+id+'"]').click();
  await target.locator('[data-lane-chapter="'+id+'"]').click();
  await target.locator("#chapter-popover").waitFor({state:"visible"});
  await target.locator('#chapter-popover [data-chapter-title="'+id+'"]').waitFor({state:"visible"});
}
async function openChapterDelete(id, target = page) {
  await openChapterEditor(id,target);
  await target.locator('[data-delete-chapter="' + id + '"]').click();
  await target.locator("#delete-chapter-dialog").waitFor({state:"visible"});
}
async function closeChapterDelete(target = page) {
  await target.locator("#delete-chapter-dialog").getByRole("button", {name:"Отмена",exact:true}).click();
  await target.locator("#delete-chapter-dialog").waitFor({state:"hidden"});
}
async function exactProject(expected, message) {
  return disk(project => JSON.stringify(project) === JSON.stringify(expected), message);
}
async function test(name, fn) {
  const started = Date.now();
  try {
    await reset();
    confirmAction = "accept";
    await fn();
    results.push({name,status:"PASS",ms:Date.now()-started});
    console.log("PASS " + name);
  } catch (error) {
    results.push({name,status:"FAIL",ms:Date.now()-started,error:error.stack});
    console.error("FAIL " + name + ": " + error.message);
    await page.screenshot({path:path.join(output,"failure-"+results.length+".png"),fullPage:true}).catch(() => {});
  }
}
async function visibleWithoutScroll(locator, target = page) {
  const box = await locator.boundingBox();
  assert(box, "Control has no visible box");
  const viewport = target.viewportSize();
  assert(box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width && box.y + box.height <= viewport.height, "Control is outside viewport");
}
async function emptyCanvasPoint(target = page) {
  return target.locator("#viewport").evaluate(el => {
    const box = el.getBoundingClientRect();
    for(const ry of [.6,.45,.7,.3]) for(const rx of [.03,.97,.15,.85,.5]) {
      const x = box.left+box.width*rx, y = box.top+box.height*ry;
      const element = document.elementFromPoint(x,y);
      if(element && el.contains(element) && !element.closest(".node,.lane-head,#chapter-popover,.canvas-controls,button,input,textarea,select")) return {x,y};
    }
    throw new Error("No unobstructed empty canvas point found");
  });
}
(async () => {
  try {
    await new Promise((resolve, reject) => { const probe = net.createServer(); probe.once("error", reject); probe.listen(8768,"127.0.0.1",() => probe.close(resolve)); });
    fs.mkdirSync(copy,{recursive:true});
    for(const filename of ["server.py","app.js","styles.css","index.html","journey.json"]) fs.copyFileSync(path.join(source,filename),path.join(copy,filename));
    stdout = fs.openSync(path.join(output,"server.stdout.log"),"w");
    stderr = fs.openSync(path.join(output,"server.stderr.log"),"w");
    server = spawn(python,[path.join(copy,"server.py"),"--port","8768"],{windowsHide:true,stdio:["ignore",stdout,stderr],cwd:copy});
    await until(async () => {
      const response = await fetch(base + "/api/health");
      if(!response.ok) return false;
      const health = await response.json();
      assert.equal(path.resolve(health.projectPath),path.join(copy,"journey.json"),"QA server is not isolated");
      return true;
    },"Isolated QA server failed to start");
    browser = await chromium.launch({headless:true});
    context = await browser.newContext({viewport:{width:1440,height:900}});
    page = await context.newPage();
    page.on("pageerror",error => errors.push(error.message));
    page.on("response",response => { if(response.status() >= 400) httpErrors.push({status:response.status(),url:response.url()}); });
    page.on("dialog",dialog => dialog[confirmAction]());
    await page.goto(base);
    await page.locator("[data-lane-chapter]").first().waitFor();

    await test("heading opens only its chapter popover and highlights members; Escape and background selection",async () => {
      const chapterId = ordered(original)[0].id;
      await openChapterEditor(chapterId);
      assert.equal(await page.locator("#inspector").isVisible(),false,"Chapter editing opened a sidebar");
      assert.equal(await page.locator(".lane.chapter-selected").count(),1);
      assert.equal(await page.locator(".lane.chapter-selected").getAttribute("data-lane"),chapterId);
      assert.deepEqual((await page.locator(".node.chapter-member").evaluateAll(nodes => nodes.map(el => el.dataset.node))).sort(),original.nodes.filter(n => n.chapterId === chapterId).map(n => n.id).sort());
      assert.equal(await page.locator(".node.dim").count(),0,"Unrelated nodes were dimmed");
      await page.keyboard.press("Escape");
      await page.locator("#chapter-popover").waitFor({state:"hidden"});
      assert.equal(await page.locator(".lane.chapter-selected").count(),1);
      assert.equal(await page.evaluate(() => document.activeElement?.dataset.laneChapter),chapterId);
      await page.locator('[data-lane-chapter="'+chapterId+'"]').click();
      await page.locator('#chapter-popover [data-action="close-chapter"]').click();
      await page.locator("#chapter-popover").waitFor({state:"hidden"});
      assert.equal(await page.locator(".lane.chapter-selected").count(),1);
      await page.locator('[data-lane-chapter="'+chapterId+'"]').click();
      const point = await emptyCanvasPoint();
      await page.mouse.click(point.x,point.y);
      await page.locator("#chapter-popover").waitFor({state:"hidden"});
      assert.equal(await page.locator(".lane.chapter-selected").count(),0);
      assert.equal(await page.locator(".node.chapter-member").count(),0);
      await exactProject(original,"Selecting and closing chapter editor changed data");
    });

    await test("zoom keeps inline editor anchored and pan closes popup while keeping chapter selection",async () => {
      const chapterId = ordered(original)[0].id;
      await openChapterEditor(chapterId);
      const before = await page.locator("#world").evaluate(el => el.style.transform);
      await page.locator("#zoom-in").click();
      assert.notEqual(await page.locator("#world").evaluate(el => el.style.transform),before,"Zoom control did not change transform");
      await visibleWithoutScroll(page.locator("#chapter-popover"));
      assert.equal(await page.locator(".lane.chapter-selected").getAttribute("data-lane"),chapterId);
      const point = await emptyCanvasPoint();
      const zoomed = await page.locator("#world").evaluate(el => el.style.transform);
      await page.mouse.move(point.x,point.y);
      await page.mouse.down();
      await page.mouse.move(point.x+32,point.y+22,{steps:8});
      await page.mouse.up();
      assert.notEqual(await page.locator("#world").evaluate(el => el.style.transform),zoomed,"Pan did not change transform");
      await page.locator("#chapter-popover").waitFor({state:"hidden"});
      assert.equal(await page.locator(".lane.chapter-selected").getAttribute("data-lane"),chapterId);
      await page.locator('[data-lane-chapter="'+chapterId+'"]').click();
      await visibleWithoutScroll(page.locator("#chapter-popover"));
      await exactProject(original,"Zoom/pan changed project data");
    });

    await test("node delete visible without extra-details; cancel, remove links, undo/redo and reload",async () => {
      const id = original.nodes.find(n => original.edges.some(e => e.from === n.id || e.to === n.id)).id;
      await choose(id);
      assert.equal(await page.locator("#inspector details.extra-details").evaluate(el => el.open),false);
      assert.equal(await page.locator("#inspector").evaluate(el => el.scrollTop),0);
      await visibleWithoutScroll(page.locator('[data-action="delete-node"]'));
      const before = (await get()).project;
      confirmAction = "dismiss";
      await page.locator('[data-action="delete-node"]').click();
      await delay(500);
      await exactProject(before,"Cancel node deletion changed data");
      confirmAction = "accept";
      await page.locator('[data-action="delete-node"]').click();
      const deleted = await disk(p => !p.nodes.some(n => n.id === id),"Node deletion not saved");
      assert(!deleted.edges.some(e => e.from === id || e.to === id));
      await page.locator("#undo").click();
      await exactProject(before,"Node delete undo did not restore nodes and links");
      await page.locator("#redo").click();
      await exactProject(deleted,"Node delete redo differs");
      await saved();
      await page.reload();
      await exactProject(deleted,"Node deletion not persistent");
      assert.equal(await page.locator('.node[data-node="'+id+'"]').count(),0);
    });

    await test("create chapter, rename and change subtitle, autosave and reload",async () => {
      assert.equal(await page.locator("#manage-chapters").count(),0,"Separate chapter manager remains");
      await openChapterEditor(ordered(original)[0].id);
      await page.locator('[data-action="add-chapter"]').click();
      let project = await disk(p => p.chapters.length === original.chapters.length+1,"New chapter not saved");
      const added = project.chapters.find(c => !original.chapters.some(old => old.id === c.id));
      assert.equal(added.order,1,"New chapter was not inserted after selected chapter");
      for(const node of original.nodes) {
        const offset = node.chapterId === ordered(original)[0].id ? 0 : 400;
        assert.equal(project.nodes.find(n => n.id === node.id).x,node.x+offset,"Inserting a chapter did not shift subsequent nodes");
      }
      await page.locator('[data-chapter-title="'+added.id+'"]').fill("QA Тайный обход");
      await page.locator('[data-chapter-subtitle="'+added.id+'"]').fill("Слизи находит другой путь к стаду");
      project = await disk(p => p.chapters.some(c => c.id === added.id && c.title === "QA Тайный обход" && c.subtitle === "Слизи находит другой путь к стаду"),"Chapter fields not saved");
      assert.equal(project.chapters.filter(c => c.id === added.id).length,1);
      await saved();
      await page.reload();
      await openChapterEditor(added.id);
      assert.equal(await page.locator('[data-chapter-title="'+added.id+'"]').inputValue(),"QA Тайный обход");
      assert.equal(await page.locator('[data-chapter-subtitle="'+added.id+'"]').inputValue(),"Слизи находит другой путь к стаду");
      assert.match(await page.locator('[data-chapter="'+added.id+'"]').textContent(),/QA Тайный обход/);
      await exactProject(project,"Reload changed chapter data");
    });

    await test("list heading opens the same chapter editor and adds stage to that chapter",async () => {
      const chapterId = ordered(original)[0].id;
      await page.locator('[data-chapter="'+chapterId+'"]').click();
      await page.locator("#list-view").click();
      await page.locator('[data-outline-chapter="'+chapterId+'"]').click();
      await page.locator("#chapter-popover").waitFor({state:"visible"});
      assert.equal(await page.locator("#inspector").isVisible(),false);
      assert.equal(await page.locator('#chapter-popover [data-chapter-title="'+chapterId+'"]').inputValue(),original.chapters.find(c => c.id === chapterId).title);
      await page.locator('#chapter-popover [data-action="chapter-add-node"]').click();
      await page.locator("#chapter-popover").waitFor({state:"hidden"});
      const changed = await disk(p => p.nodes.length === original.nodes.length+1,"Add stage from chapter popup did not save");
      const added = changed.nodes.find(n => !original.nodes.some(old => old.id === n.id));
      assert.equal(added.chapterId,chapterId);
      assert.equal(await page.locator("#inspector").isVisible(),true);
      await page.locator("#undo").click();
      await exactProject(original,"Undo stage addition from chapter popup failed");
    });

    await test("delete empty chapter, preserve map, undo/redo and reload",async () => {
      await openChapterEditor(ordered(original)[0].id);
      await page.locator('[data-action="add-chapter"]').click();
      const withEmpty = await disk(p => p.chapters.length === original.chapters.length+1,"Empty chapter not added");
      const id = withEmpty.chapters.find(c => !original.chapters.some(old => old.id === c.id)).id;
      await visibleWithoutScroll(page.locator('[data-lane-chapter="'+id+'"]'));
      assert.equal(await page.locator(".lane.chapter-selected").getAttribute("data-lane"),id);
      assert.equal(await page.locator(".node.chapter-member").count(),0);
      assert.equal(await page.locator("#inspector").isVisible(),false);
      await page.screenshot({path:path.join(output,"desktop-empty-chapter.png"),fullPage:true});
      await openChapterDelete(id);
      await page.locator("#confirm-delete-chapter").click();
      await exactProject(original,"Empty chapter deletion changed existing map");
      await page.locator("#undo").click();
      await exactProject(withEmpty,"Undo empty chapter deletion failed");
      await page.locator("#redo").click();
      await exactProject(original,"Redo empty chapter deletion failed");
      await saved();
      await page.reload();
      assert.equal(await page.locator(".chapter-button").count(),original.chapters.length);
    });

    await test("cancel populated chapter deletion and Escape preserve map",async () => {
      const id = original.nodes[0].chapterId;
      await openChapterDelete(id);
      await closeChapterDelete();
      await exactProject(original,"Cancel chapter deletion changed map");
      await openChapterDelete(id);
      await page.keyboard.press("Escape");
      await page.locator("#delete-chapter-dialog").waitFor({state:"hidden"});
      await delay(500);
      await exactProject(original,"Escape chapter deletion changed map");
    });

    await test("delete chapter by moving stages; links, relative positions, undo/redo and reload",async () => {
      const chapters = ordered(original);
      const from = chapters.find(c => original.nodes.some(n => n.chapterId === c.id));
      const target = chapters.find(c => c.id !== from.id && original.nodes.some(n => n.chapterId === c.id));
      const removedIndex = chapters.findIndex(c => c.id === from.id);
      const moved = original.nodes.filter(n => n.chapterId === from.id);
      const targetNodes = original.nodes.filter(n => n.chapterId === target.id);
      const targetMaxY = Math.max(...targetNodes.map(n => n.y));
      await openChapterDelete(from.id);
      assert.equal(await page.locator("#delete-chapter-mode").inputValue(),"move");
      await page.locator("#delete-chapter-target").selectOption(target.id);
      await page.locator("#confirm-delete-chapter").click();
      const changed = await disk(p => !p.chapters.some(c => c.id === from.id),"Chapter transfer not saved");
      assert.equal(changed.nodes.length,original.nodes.length);
      assert.deepEqual(changed.edges,original.edges,"Transfer changed graph links");
      assert.deepEqual(ordered(changed).map(c => c.order),Array.from({length:changed.chapters.length},(_,i) => i));
      for(const n of moved) {
        const actual = changed.nodes.find(item => item.id === n.id);
        assert.equal(actual.chapterId,target.id);
        assert(actual.y >= targetMaxY+96,"Transferred stages overlap existing stages vertically");
        const anchor = moved[0], movedAnchor = changed.nodes.find(item => item.id === anchor.id);
        assert.equal(actual.x-movedAnchor.x,n.x-anchor.x,"Transfer changed relative horizontal placement");
        assert.equal(actual.y-movedAnchor.y,n.y-anchor.y,"Transfer changed relative vertical placement");
      }
      const movedIds = new Set(moved.map(n => n.id));
      for(const n of original.nodes.filter(n => !movedIds.has(n.id))) {
        const oldIndex = chapters.findIndex(c => c.id === n.chapterId);
        const actual = changed.nodes.find(item => item.id === n.id);
        assert.equal(actual.x,n.x-(oldIndex>removedIndex?400:0),"Remaining chapter lane did not shift consistently");
        assert.equal(actual.y,n.y);
      }
      await page.locator("#undo").click();
      await exactProject(original,"Undo chapter transfer failed");
      await page.locator("#redo").click();
      await exactProject(changed,"Redo chapter transfer failed");
      await saved();
      await page.reload();
      await choose(moved[0].id);
      assert.equal(await page.locator("#field-title").inputValue(),moved[0].title);
      await exactProject(changed,"Transfer lost after reload");
    });

    await test("delete chapter with stages and incident edges; preserve other edges, undo/redo and reload",async () => {
      const chapterId = ordered(original).find(c => original.nodes.some(n => n.chapterId === c.id)).id;
      const removed = new Set(original.nodes.filter(n => n.chapterId === chapterId).map(n => n.id));
      await openChapterDelete(chapterId);
      await page.locator("#delete-chapter-mode").selectOption("delete");
      await page.locator("#confirm-delete-chapter").click();
      const changed = await disk(p => !p.chapters.some(c => c.id === chapterId),"Cascade deletion not saved");
      assert.equal(changed.nodes.length,original.nodes.length-removed.size);
      assert(!changed.nodes.some(n => removed.has(n.id)));
      assert.deepEqual(changed.edges,original.edges.filter(e => !removed.has(e.from) && !removed.has(e.to)));
      assert(changed.edges.every(e => changed.nodes.some(n => n.id === e.from) && changed.nodes.some(n => n.id === e.to)));
      await page.locator("#undo").click();
      await exactProject(original,"Undo cascade deletion did not restore graph");
      await page.locator("#redo").click();
      await exactProject(changed,"Redo cascade deletion failed");
      await saved();
      await page.reload();
      assert.equal(await page.locator(".node").count(),changed.nodes.length);
      await exactProject(changed,"Cascade deletion lost after reload");
    });

    await test("external deletion of selected chapter refreshes selection before adding a stage",async () => {
      const chapterId = ordered(original)[0].id;
      await page.locator('[data-chapter="'+chapterId+'"]').click();
      const remote = await get();
      const removed = new Set(remote.project.nodes.filter(n => n.chapterId === chapterId).map(n => n.id));
      remote.project.chapters = ordered(remote.project).filter(c => c.id !== chapterId).map((c,order) => ({...c,order}));
      remote.project.nodes = remote.project.nodes.filter(n => !removed.has(n.id));
      remote.project.edges = remote.project.edges.filter(e => !removed.has(e.from) && !removed.has(e.to));
      const response = await fetch(base+"/api/project",{method:"PUT",headers:{Origin:base,"Content-Type":"application/json"},body:JSON.stringify(remote)});
      assert.equal(response.status,200,await response.text());
      await until(async () => await page.locator('[data-chapter="'+chapterId+'"]').count() === 0,"Deleted chapter did not refresh in browser");
      assert.equal(await page.locator("#overview").evaluate(el => el.classList.contains("active")),true);
      await page.locator("#add-node").click();
      await page.locator("#field-title").fill("QA этап после внешнего удаления главы");
      const changed = await disk(p => p.nodes.some(n => n.title === "QA этап после внешнего удаления главы"),"New stage after external deletion did not save");
      const added = changed.nodes.find(n => n.title === "QA этап после внешнего удаления главы");
      assert(changed.chapters.some(c => c.id === added.chapterId),"New stage points at removed chapter");
      await saved();
    });

    await test("reorder from inline chapter editor moves both chapter lanes and preserves graph",async () => {
      const chapters = ordered(original), chapter = chapters[0], neighbor = chapters[1];
      await openChapterEditor(chapter.id);
      await page.locator('#chapter-popover [data-order="'+chapter.id+'"][data-delta="1"]').click();
      const changed = await disk(p => p.chapters.find(c => c.id === chapter.id).order === 1,"Inline chapter reorder not saved");
      assert.deepEqual(changed.edges,original.edges);
      for(const node of original.nodes) {
        const offset = node.chapterId === chapter.id ? 400 : node.chapterId === neighbor.id ? -400 : 0;
        const actual = changed.nodes.find(n => n.id === node.id);
        assert.equal(actual.x,node.x+offset);
        assert.equal(actual.y,node.y);
      }
      await page.locator("#undo").click();
      await exactProject(original,"Undo inline chapter reorder failed");
      await page.locator("#redo").click();
      await exactProject(changed,"Redo inline chapter reorder failed");
    });

    await test("last chapter cannot be deleted",async () => {
      const fixture = clone(original);
      fixture.chapters = [ordered(fixture)[0]];
      fixture.chapters[0].order = 0;
      fixture.nodes = fixture.nodes.filter(n => n.chapterId === fixture.chapters[0].id);
      const ids = new Set(fixture.nodes.map(n => n.id));
      fixture.edges = fixture.edges.filter(e => ids.has(e.from) && ids.has(e.to));
      await reset(fixture);
      await openChapterEditor(fixture.chapters[0].id);
      const deletion = page.locator('[data-delete-chapter="'+fixture.chapters[0].id+'"]');
      assert.equal(await deletion.isDisabled(),true);
      await exactProject(fixture,"Last chapter guard changed fixture");
    });

    await test("desktop and 390px inline controls rendered; mobile chapter create/edit/delete",async () => {
      const node = original.nodes[0];
      await choose(node.id);
      await page.screenshot({path:path.join(output,"desktop-node-delete.png"),fullPage:true});
      await openChapterEditor(node.chapterId);
      await visibleWithoutScroll(page.locator("#chapter-popover"));
      await page.screenshot({path:path.join(output,"desktop-inline-chapter.png"),fullPage:true});
      await page.keyboard.press("Escape");
      await page.screenshot({path:path.join(output,"desktop-chapter-selection.png"),fullPage:true});
      await openChapterDelete(node.chapterId);
      await page.screenshot({path:path.join(output,"desktop-delete-chapter-dialog.png"),fullPage:true});
      await closeChapterDelete();
      const mobile = await context.newPage();
      mobile.on("pageerror",error => errors.push("mobile: "+error.message));
      mobile.on("dialog",dialog => dialog.accept());
      await mobile.setViewportSize({width:390,height:844});
      await mobile.goto(base);
      assert.equal(await mobile.locator("#manage-chapters").count(),0);
      await choose(node.id,mobile);
      await visibleWithoutScroll(mobile.locator('[data-action="delete-node"]'),mobile);
      await mobile.screenshot({path:path.join(output,"mobile-node-delete.png"),fullPage:true});
      await openChapterEditor(node.chapterId,mobile);
      await visibleWithoutScroll(mobile.locator("#chapter-popover"),mobile);
      await mobile.screenshot({path:path.join(output,"mobile-inline-chapter.png"),fullPage:true});
      await mobile.keyboard.press("Escape");
      await mobile.screenshot({path:path.join(output,"mobile-chapter-selection.png"),fullPage:true});
      await openChapterDelete(node.chapterId,mobile);
      await visibleWithoutScroll(mobile.locator("#confirm-delete-chapter"),mobile);
      await mobile.screenshot({path:path.join(output,"mobile-delete-chapter-dialog.png"),fullPage:true});
      await closeChapterDelete(mobile);
      await mobile.locator('[data-action="add-chapter"]').click();
      const added = await disk(p => p.chapters.length === original.chapters.length+1,"Mobile add chapter failed");
      const newId = added.chapters.find(c => !original.chapters.some(old => old.id === c.id)).id;
      await mobile.locator('[data-chapter-title="'+newId+'"]').fill("QA mobile глава");
      await disk(p => p.chapters.some(c => c.id === newId && c.title === "QA mobile глава"),"Mobile chapter rename failed");
      await openChapterDelete(newId,mobile);
      await mobile.locator("#confirm-delete-chapter").click();
      await exactProject(original,"Mobile delete chapter failed");
      await mobile.close();
    });
    assert.deepEqual(errors,[],"Browser JavaScript errors");
    assert.deepEqual(httpErrors,[],"Unexpected HTTP errors");
  } catch(error) {
    results.push({name:"runner",status:"FAIL",error:error.stack});
    console.error(error.stack);
  } finally {
    if(browser) await browser.close();
    if(server) server.kill();
    if(stdout !== undefined) fs.closeSync(stdout);
    if(stderr !== undefined) fs.closeSync(stderr);
    const finalMainHash = hash(mainPath);
    const mainUnchanged = finalMainHash === initialMainHash;
    results.push({name:"main journey.json unchanged during isolated run",status:mainUnchanged?"PASS":"CHANGED_EXTERNALLY",initialMainHash,finalMainHash});
    const sourceHashes = Object.fromEntries(["app.js","styles.css","index.html","server.py"].filter(n => fs.existsSync(path.join(copy,n))).map(n => [n,hash(path.join(copy,n))]));
    fs.mkdirSync(output,{recursive:true});
    const report = {results,browserErrors:errors,httpErrors,base,isolatedProject:path.join(copy,"journey.json"),sourceHashes};
    fs.writeFileSync(path.join(output,"CHAPTER_QA_RESULTS.json"),JSON.stringify(report,null,2)+"\n");
    console.log(JSON.stringify({passed:results.filter(r => r.status === "PASS").length,failed:results.filter(r => r.status === "FAIL").length,browserErrors:errors.length,mainUnchanged,report:path.join(output,"CHAPTER_QA_RESULTS.json")}));
    process.exitCode = results.some(r => r.status === "FAIL") || errors.length ? 1 : 0;
  }
})();

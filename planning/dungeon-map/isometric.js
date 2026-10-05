"use strict";

// Schematic room geometry. These units describe relationships and height,
// not final Godot dimensions.
globalThis.IsoMap = (() => {
  const STEP_X = 60;
  const STEP_Y = 30;
  const STEP_H = 45;
  const THICKNESS = 0.85;

  const firstFloor = {
    r01: { u: 0, v: 9, h: 0, w: 2, d: 1.5 },
    r02: { u: 3, v: 9, h: 0.9, w: 2, d: 1.5 },
    r03: { u: 6, v: 8, h: 1.8, w: 2, d: 1.5 },
    r04: { u: 8, v: 6, h: 2.6, w: 2, d: 1.5 },
    r05: { u: 7, v: 3, h: 3.6, w: 2, d: 1.5 },
    r06: { u: 4, v: 2, h: 4.5, w: 2, d: 1.5 },
    r07: { u: 1, v: 4, h: 5.4, w: 2, d: 1.5 },
    r08: { u: 1, v: 7, h: 6.1, w: 2, d: 1.5 },
    r09: { u: 4, v: 6, h: 7.2, w: 2, d: 1.5 }
  };

  function clamp(value, low, high) { return Math.min(high, Math.max(low, value)); }
  function fallback(id, index) {
    if (firstFloor[id]) return { ...firstFloor[id] };
    const bend = index % 4;
    return { u: 1 + bend * 2.2, v: 5 - Math.floor(index / 4) * 2 - bend * 0.65, h: index * 0.45, w: 1.8, d: 1.35 };
  }
  function normalize(source, id, index) {
    const base = fallback(id, index);
    const input = source && typeof source === "object" ? source : {};
    return {
      u: clamp(Number.isFinite(Number(input.u)) ? Number(input.u) : base.u, -4, 20),
      v: clamp(Number.isFinite(Number(input.v)) ? Number(input.v) : base.v, -4, 20),
      h: clamp(Number.isFinite(Number(input.h)) ? Number(input.h) : base.h, 0, 8),
      w: clamp(Number.isFinite(Number(input.w)) ? Number(input.w) : base.w, 0.8, 4),
      d: clamp(Number.isFinite(Number(input.d)) ? Number(input.d) : base.d, 0.8, 4)
    };
  }
  function point(u, v, h) { return { x: (u - v) * STEP_X, y: (u + v) * STEP_Y - h * STEP_H }; }
  function center(item) {
    const g = item.iso;
    return point(g.u + g.w / 2, g.v + g.d / 2, g.h);
  }
  function corners(g, lower = false) {
    const h = g.h - (lower ? THICKNESS : 0);
    return [point(g.u, g.v, h), point(g.u + g.w, g.v, h), point(g.u + g.w, g.v + g.d, h), point(g.u, g.v + g.d, h)];
  }
  function xy(p) { return `${p.x.toFixed(1)},${p.y.toFixed(1)}`; }
  function polygon(points) { return points.map(xy).join(" "); }
  function boundsFor(rooms) {
    if (!rooms.length) return { x: -400, y: -240, w: 800, h: 560 };
    const points = rooms.flatMap((item) => [...corners(item.iso), ...corners(item.iso, true)]);
    const minX = Math.min(...points.map((p) => p.x));
    const maxX = Math.max(...points.map((p) => p.x));
    const minY = Math.min(...points.map((p) => p.y));
    const maxY = Math.max(...points.map((p) => p.y));
    return { x: minX - 105, y: minY - 100, w: maxX - minX + 210, h: maxY - minY + 205 };
  }
  function glyph(type) { return ({ entrance: "↘", combat: "⚔", puzzle: "◇", story: "✦", boss: "♛", rest: "☼" })[type] || "•"; }

  function landmarkSvg(item, mid) {
    const x = mid.x, y = mid.y;
    const at = (dx, dy) => `${(x + dx).toFixed(1)} ${(y + dy).toFixed(1)}`;
    switch (item.id) {
      case "r01": return `<path class="iso-prop-slime" d="M ${at(-15, -14)} Q ${at(-21, -34)} ${at(0, -51)} Q ${at(21, -34)} ${at(15, -14)} Q ${at(0, -5)} ${at(-15, -14)} Z"/><circle class="iso-prop-eye" cx="${x - 5}" cy="${y - 26}" r="2"/><circle class="iso-prop-eye" cx="${x + 5}" cy="${y - 26}" r="2"/>`;
      case "r02": return `<path class="iso-prop-stone" d="M ${at(-28, -17)} L ${at(-28, -40)} L ${at(6, -40)} L ${at(6, -17)} Z M ${at(9, -17)} L ${at(9, -33)} L ${at(28, -33)} L ${at(28, -17)} Z"/><path class="iso-prop-seam" d="M ${at(-28, -30)} L ${at(6, -30)} M ${at(-8, -40)} L ${at(-8, -17)}"/>`;
      case "r03": return `<path class="iso-prop-stone" d="M ${at(-29, -20)} L ${at(-29, -28)} L ${at(29, -28)} L ${at(29, -20)} Z"/><path class="iso-prop-seam" d="M ${at(-24, -28)} L ${at(-24, -45)} M ${at(0, -28)} L ${at(0, -45)} M ${at(24, -28)} L ${at(24, -45)} M ${at(-29, -45)} L ${at(29, -45)}"/>`;
      case "r04": return `<path class="iso-prop-stone" d="M ${at(-30, -17)} Q ${at(0, -31)} ${at(30, -17)} Z"/><path class="iso-prop-ring" d="M ${at(-24, -27)} Q ${at(-24, -51)} ${at(-7, -48)} L ${at(0, -31)} M ${at(2, -29)} Q ${at(7, -58)} ${at(25, -48)} L ${at(26, -25)}"/>`;
      case "r05": return `<path class="iso-prop-seam" d="M ${at(-22, -19)} Q ${at(22, -27)} ${at(-22, -34)} Q ${at(22, -41)} ${at(-22, -48)} Q ${at(22, -55)} ${at(-22, -62)}"/><path class="iso-prop-arch" d="M ${at(-30, -18)} L ${at(30, -18)}"/>`;
      case "r06": return `<path class="iso-prop-stone" d="M ${at(-27, -42)} L ${at(27, -42)} L ${at(27, -32)} L ${at(-27, -32)} Z"/><text class="iso-glyph" x="${x.toFixed(1)}" y="${(y - 47).toFixed(1)}">⚔</text>`;
      case "r07": return `<path class="iso-prop-arch" d="M ${at(-30, -19)} L ${at(-30, -50)} L ${at(30, -50)} L ${at(30, -19)}"/><path class="iso-prop-seam" d="M ${at(-20, -31)} L ${at(20, -31)} M ${at(0, -50)} L ${at(0, -66)}"/>`;
      case "r08": return `<path class="iso-prop-seam" d="M ${at(0, -17)} L ${at(0, -36)} M ${at(0, -36)} L ${at(-25, -57)} M ${at(0, -36)} L ${at(25, -57)}"/><circle class="iso-prop-orb" cx="${x - 25}" cy="${y - 57}" r="4"/><circle class="iso-prop-orb" cx="${x + 25}" cy="${y - 57}" r="4"/>`;
      case "r09": return `<path class="iso-prop-arch" d="M ${at(-24, -15)} L ${at(-24, -48)} Q ${at(0, -74)} ${at(24, -48)} L ${at(24, -15)}"/><circle class="iso-prop-orb" cx="${x}" cy="${y - 48}" r="5"/>`;
      default: return `<text class="iso-glyph" x="${x.toFixed(1)}" y="${(y - 24).toFixed(1)}">${glyph(item.type)}</text>`;
    }
  }

  function roomSvg(item, selected, escapeHtml) {
    const top = corners(item.iso);
    const low = corners(item.iso, true);
    const mid = center(item);
    const name = item.title.length > 19 ? `${item.title.slice(0, 18)}…` : item.title;
    const label = `${item.code} ${item.title}, ${item.minutes} минут`;
    return `<g class="iso-room ${selected ? "selected" : ""}" data-iso-room="${escapeHtml(item.id)}" data-type="${escapeHtml(item.type)}" role="button" tabindex="0" aria-label="${escapeHtml(label)}">
      <title>${escapeHtml(label)} — ${escapeHtml(item.summary)}</title>
      <polygon class="iso-face iso-face-left" points="${polygon([top[3], top[2], low[2], low[3]])}"/>
      <polygon class="iso-face iso-face-right" points="${polygon([top[1], top[2], low[2], low[1]])}"/>
      <polygon class="iso-top" points="${polygon(top)}"/>
      <path class="iso-floor-mark" d="M ${xy(top[0])} L ${xy(top[2])}"/>
      ${landmarkSvg(item, mid)}
      <rect class="iso-label-bg" x="${(mid.x - 73).toFixed(1)}" y="${(mid.y - 5).toFixed(1)}" width="146" height="38" rx="9"/>
      <text class="iso-label-code" x="${mid.x.toFixed(1)}" y="${(mid.y + 8).toFixed(1)}">${escapeHtml(item.code)} · ${item.minutes} мин</text>
      <text class="iso-label-title" x="${mid.x.toFixed(1)}" y="${(mid.y + 25).toFixed(1)}">${escapeHtml(name)}</text>
    </g>`;
  }

  function scene(floor, links, selectedId, floorIndex, escapeHtml) {
    const rooms = floor.rooms;
    const roomById = new Map(rooms.map((item) => [item.id, item]));
    const bounds = boundsFor(rooms);
    const visibleLinks = links.filter((link) => roomById.has(link.from) && roomById.has(link.to));
    const bridges = visibleLinks.map((link) => {
      const a = center(roomById.get(link.from));
      const b = center(roomById.get(link.to));
      const mx = (a.x + b.x) / 2;
      const my = (a.y + b.y) / 2 - 12;
      const d = `M ${xy(a)} Q ${mx.toFixed(1)},${my.toFixed(1)} ${xy(b)}`;
      const optional = link.type === "optional" ? " optional" : "";
      return `<path class="iso-bridge-shadow${optional}" d="${d}"/><path class="iso-bridge${optional}" d="${d}"/><path class="iso-trail${optional}" d="${d}"/>`;
    }).join("");
    const sorted = [...rooms].sort((a, b) => center(a).y - center(b).y);
    const entrance = roomById.get("r01") || rooms[0];
    const exit = rooms.at(-1);
    const markers = floorIndex === 0 && rooms.length ? `<text class="iso-landmark" x="${(center(entrance).x - 120).toFixed(1)}" y="${(center(entrance).y + 80).toFixed(1)}">↓ МЕСТО ПАДЕНИЯ</text><text class="iso-landmark exit" x="${(center(exit).x + 15).toFixed(1)}" y="${(center(exit).y - 94).toFixed(1)}">↑ ВЕРХНИЙ ШЛЮЗ</text>` : "";
    const sceneWidth = bounds.w;
    const sceneHeight = bounds.h;
    const texture = Array.from({ length: 9 }, (_, index) => {
      const y = bounds.y + 72 + index * sceneHeight / 10;
      return `<path class="iso-stratum" d="M ${bounds.x.toFixed(1)},${y.toFixed(1)} q ${(sceneWidth / 3).toFixed(1)},${index % 2 ? 12 : -10} ${(sceneWidth * 0.66).toFixed(1)},0 t ${(sceneWidth * 0.34).toFixed(1)},0"/>`;
    }).join("");
    const glow = exit ? center(exit) : { x: 0, y: 0 };
    const markup = `<defs>
      <radialGradient id="iso-cave-light"><stop stop-color="#47665a" stop-opacity=".6"/><stop offset="1" stop-color="#112028" stop-opacity="0"/></radialGradient>
      <linearGradient id="iso-light-beam" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#f4d996" stop-opacity=".55"/><stop offset="1" stop-color="#e6cd8e" stop-opacity="0"/></linearGradient>
      <filter id="iso-glow"><feGaussianBlur stdDeviation="6"/></filter>
    </defs>
    <rect class="iso-cave" x="${bounds.x.toFixed(1)}" y="${bounds.y.toFixed(1)}" width="${sceneWidth.toFixed(1)}" height="${sceneHeight.toFixed(1)}"/>
    <ellipse cx="${glow.x.toFixed(1)}" cy="${(glow.y + 60).toFixed(1)}" rx="270" ry="230" fill="url(#iso-cave-light)"/>
    <polygon points="${(glow.x - 35).toFixed(1)},${bounds.y.toFixed(1)} ${(glow.x + 35).toFixed(1)},${bounds.y.toFixed(1)} ${(glow.x + 205).toFixed(1)},${(glow.y + 190).toFixed(1)} ${(glow.x - 205).toFixed(1)},${(glow.y + 190).toFixed(1)}" fill="url(#iso-light-beam)"/>
    ${texture}
    <g class="iso-bridges">${bridges}</g>
    <g class="iso-rooms">${sorted.map((item) => roomSvg(item, item.id === selectedId, escapeHtml)).join("")}</g>
    ${markers}`;
    return { markup, bounds };
  }

  return Object.freeze({ normalize, point, center, corners, boundsFor, scene, STEP_X, STEP_Y });
})();

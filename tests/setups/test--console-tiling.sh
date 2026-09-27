#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the Console UI's tiling tree (variants/base/web-ttyd-split/tiling.js)
# — the i3-style layout behind its Ctrl+Alt shortcuts. Pure logic, run under
# Node; the shortcuts themselves are wired up in index.html.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"
source ../common--source.sh
if ! command -v node >/dev/null; then
  echo "SKIP: Console tiling tests require Node."
  exit 0
fi
node <<'JS'
const assert = require('node:assert/strict');
const T = require('../../variants/base/web-ttyd-split/tiling.js');
const S = (tree) => T.serialize(tree);
const P = (text) => { const t = T.parse(text); assert.ok(t, 'parses: ' + text); return t; };

// ---- text form ----
for (const text of ['1', 'h(1,2)', 'v(1,h(2,3))', 'h(1@60,v(2,3)@40)', 'v(h(1,2),h(3,4))', 'h(1,2,3,4)']) {
  assert.equal(S(P(text)), text, 'round trip: ' + text);
}
assert.equal(S(P(' H( 1 , V(2,3) ) ')), 'h(1,v(2,3))', 'spaces and case are ignored');
assert.equal(S(P('h(1,h(2,3))')), 'h(1@50,2@25,3@25)', 'a split inside one of the same direction folds in, sizes kept');
assert.equal(S(P('h(1@70,2)')), 'h(1@70,2@30)', 'a missing size takes the rest');
assert.equal(S(P('h(1@60,2@60)')), 'h(1,2)', 'sizes that do not add up are rescaled');
for (const bad of ['', 'single', '5', '0', 'h(1)', 'h(1,1)', 'h(1,2', 'x(1,2)', 'h(1@100,2)', 'h(1@60,2@60,3)',
                   'h(1,2,3,4,1)', 'h(1,2)x', 'h(1@,2)', null, 42]) {
  assert.equal(T.parse(bad), null, 'rejected: ' + JSON.stringify(bad));
}

// ---- presets ----
const presets = ['single', 'hsplit', 'vsplit', 'left-main', 'top-main', 'quad'];
for (const name of presets) {
  const m = T.matchPreset(T.presetTree(name, 0.3, 0.7));
  assert.equal(m.name, name, 'preset round trip: ' + name);
  if (m.x !== undefined) assert.ok(Math.abs(m.x - 0.3) < 1e-9, name + ' keeps x');
  if (m.y !== undefined) assert.ok(Math.abs(m.y - 0.7) < 1e-9, name + ' keeps y');
}
assert.equal(T.matchPreset(P('h(2,1)')), null, 'panes out of order are not a preset');
assert.equal(T.matchPreset(P('v(h(1@30,2),h(3@60,4))')), null, 'quad with rows split apart is not the quad preset');
assert.equal(T.matchPreset(P('h(1@10,2)')), null, 'a divider outside the preset range stays a tree');
assert.equal(T.matchPreset(P('h(v(1,3),v(2,4))')), null, 'columns-first quad is its own tree');

// ---- geometry: panes tile the area exactly ----
function assertTiles(tree, label) {
  const r = T.rects(tree);
  const list = T.panes(tree).map((p) => r[p]);
  const area = list.reduce((a, b) => a + b.w * b.h, 0);
  assert.ok(Math.abs(area - 1) < 1e-9, label + ': areas sum to 1');
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      const a = list[i], b = list[j];
      const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
      const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
      assert.ok(ox <= 1e-9 || oy <= 1e-9, label + ': no overlap');
    }
  }
}

// ---- every shape of up to 4 panes is reachable by shortcuts alone ----
// Labels do not matter for the count: the shape with panes renumbered in order.
const canon = (tree) => { let n = 0; return T.shape(tree).replace(/[1-4]/g, () => String(++n)); };
const dirs = ['left', 'right', 'up', 'down'];
function nextTrees(tree) {
  const out = [];
  const inTree = T.panes(tree);
  const hidden = [1, 2, 3, 4].filter((p) => !inTree.includes(p));
  for (const p of inTree) {
    for (const d of dirs) out.push(T.move(tree, p, d));
    out.push(T.toggleSplit(tree, p));
    if (inTree.length > 1) out.push(T.remove(tree, p));
    if (hidden.length) for (const sd of [undefined, 'h', 'v']) out.push(T.insert(tree, p, hidden[0], sd, 'h'));
  }
  return out;
}
// Keyed on shape: sizes shift with every insert and remove, so keying on the
// full text would never run out of new states.
const seen = new Map([[T.shape(P('1')), P('1')]]);
const queue = [P('1')];
while (queue.length) {
  for (const t of nextTrees(queue.shift())) {
    const key = T.shape(t);
    if (!seen.has(key)) { seen.set(key, t); queue.push(t); }
  }
}
const shapes = new Set([...seen.values()].map(canon));
const bySize = [1, 2, 3, 4].map((n) => [...shapes].filter((s) => (s.match(/[1-4]/g) || []).length === n).length);
assert.deepEqual(bySize, [1, 2, 6, 22], 'shapes of 1..4 panes reachable: ' + bySize);
for (const t of seen.values()) assertTiles(t, S(t));

// ---- focus ----
const lm = P('h(1,v(2,3))');
assert.equal(T.neighbor(lm, 1, 'right'), 2, 'right of the main pane is the top of the stack');
assert.equal(T.neighbor(lm, 3, 'left'), 1);
assert.equal(T.neighbor(lm, 2, 'down'), 3);
assert.equal(T.neighbor(lm, 3, 'down'), null, 'no pane below the bottom one');
assert.equal(T.neighbor(lm, 1, 'left'), null);

// ---- move (i3 semantics) ----
assert.equal(S(T.move(P('h(1,2)'), 1, 'right')), 'h(2,1)', 'swap within a split');
assert.equal(S(T.move(P('h(1,2)'), 1, 'left')), 'h(1,2)', 'already at the edge: unchanged');
assert.equal(S(T.move(P('h(1,v(2,3))'), 2, 'left')), 'h(1,2,3)', 'step out past the edge of its split');
assert.equal(S(T.move(P('h(1,v(2,3))'), 1, 'right')), 'v(2,3,1)', 'step into the split beside it');
assert.equal(S(T.move(P('v(1,2)'), 1, 'left')), 'h(1,2)', 'no split runs that way: take the whole side');
assert.equal(S(T.move(P('h(1,v(2,3))'), 3, 'down')), 'v(h(1,2),3)', 'a bottom pane moving down takes the whole bottom');
assert.equal(S(T.move(P('v(h(1,2),3)'), 3, 'down')), 'v(h(1,2),3)', 'already the whole bottom: unchanged');
assert.equal(S(T.move(P('h(1@70,2)'), 1, 'right')), 'h(2@70,1@30)', 'a swap keeps the sizes where they are');

// ---- insert / remove / toggle / resize ----
assert.equal(S(T.insert(P('1'), 1, 2, undefined, 'h')), 'h(1,2)', 'a lone pane splits the fallback way');
assert.equal(S(T.insert(P('1'), 1, 2, undefined, 'v')), 'v(1,2)');
assert.equal(S(T.insert(P('h(1,2)'), 1, 3)), 'h(1,3,2)', 'joins its own split, right after it');
assert.equal(S(T.insert(P('h(1,2)'), 2, 3, 'v')), 'h(1,v(2,3))', 'split v on a pane stacks the new one under it');
assert.equal(S(T.insert(P('h(1,2,3,4)'), 1, 4)), 'h(1,2,3,4)', 'four panes is the limit');
assert.equal(S(T.remove(P('h(1,v(2,3))'), 2)), 'h(1,3)', 'removing collapses the split left with one');
assert.equal(S(T.remove(P('1'), 1)), '1', 'the last pane stays');
assert.equal(S(T.toggleSplit(P('h(1,v(2,3))'), 2)), 'h(1@50,2@25,3@25)', 'toggling folds into a parent of the same way');
assert.equal(S(T.toggleSplit(P('h(1,2)'), 1)), 'v(1,2)');
assert.equal(S(T.resize(P('h(1,2)'), 1, 'h', 0.1)), 'h(1@60,2@40)', 'grow width');
assert.equal(S(T.resize(P('h(1,2)'), 2, 'h', 0.1)), 'h(1@40,2@60)', 'the last pane grows into the one before');
assert.equal(S(T.resize(P('h(1,2)'), 1, 'h', 0.9)), 'h(1@90,2@10)', 'clamped at the minimum share');
assert.equal(S(T.resize(P('h(1,2)'), 1, 'v', 0.1)), 'h(1,2)', 'no split that way: unchanged');
assert.equal(S(T.resize(P('h(1,v(2,3))'), 2, 'h', 0.1)), 'h(1@40,v(2,3)@60)', 'grows the split holding it');

// ---- dragging a divider ----
assert.equal(S(T.dragDivider(P('h(1,v(2,3))'), [1], 0, 0.25)), 'h(1,v(2@25,3@75))', 'the stack divider, by its split path');
assert.equal(S(T.dragDivider(P('h(1,2)'), [], 0, 0.01)), 'h(1@10,2@90)', 'a drag stops at the minimum share');
assert.equal(S(T.dragDivider(P('h(1,2)'), [], 1, 0.3)), 'h(1,2)', 'no such divider: unchanged');

console.log('PASS: text form, presets, 31 reachable shapes, focus, move, insert, remove, toggle, resize, drag');
JS
print_test_result true "$0" 1 "Console tiling tree: all 31 layouts of up to 4 panes, driven the way i3 drives them"

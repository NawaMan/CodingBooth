// Booth console tiling — the i3-style layout tree behind the Console UI's
// Ctrl+Alt shortcuts. Pure logic, no DOM: index.html asks it where panes go
// and how a shortcut changes that, and tests/setups/test--console-tiling.sh
// runs the same file under Node.
//
// A layout is a tree of splits over the four fixed panes (1-4), like an i3
// workspace capped at four windows:
//
//   leaf  = { pane: 1 }
//   split = { dir: "h" | "v", children: [...], sizes: [fractions summing to 1] }
//
// "h" puts children side by side, "v" stacks them — i3's splith / splitv.
// Every arrangement of up to four rectangles is reachable this way (the first
// one that is not needs five), so there are 31 shapes and no preset list to
// keep complete.
//
// Written as text, a tree is `h(1,v(2,3))`, with an optional `@percent` per
// child when the sizes are not equal: `h(1@60,v(2,3))`. That string is what
// the console stores as its layout — in the URL hash, localStorage and
// .booth/console.json — beside the six preset names it already had.
(function (root) {
  "use strict";

  var MAX_PANES = 4;
  // Smallest share a child may be given of its split, by keyboard or drag.
  var MIN_SIZE = 0.1;
  // The six toolbar presets clamp their dividers to this range; a tree with a
  // divider outside it keeps showing as a tree rather than a preset.
  var PRESET_MIN = 0.2;
  var PRESET_MAX = 0.8;
  var EPS = 1e-6;

  function leaf(pane) {
    return { pane: pane };
  }

  function isLeaf(node) {
    return typeof node.pane === "number";
  }

  function clone(node) {
    return isLeaf(node)
      ? leaf(node.pane)
      : { dir: node.dir, children: node.children.map(clone), sizes: node.sizes.slice() };
  }

  function sum(list) {
    return list.reduce(function (a, b) { return a + b; }, 0);
  }

  // Collapses one-child splits and folds a split into a parent of the same
  // direction (i3 keeps those nested; here they would only be shapes that look
  // identical but move differently). Sizes are rescaled to sum to 1.
  function normalize(node) {
    if (isLeaf(node)) return node;
    var children = [];
    var sizes = [];
    node.children.forEach(function (child, i) {
      var size = node.sizes[i];
      var inner = normalize(child);
      if (!isLeaf(inner) && inner.dir === node.dir) {
        inner.children.forEach(function (grandchild, j) {
          children.push(grandchild);
          sizes.push(size * inner.sizes[j]);
        });
      } else {
        children.push(inner);
        sizes.push(size);
      }
    });
    if (children.length === 1) return children[0];
    var total = sum(sizes);
    return { dir: node.dir, children: children, sizes: sizes.map(function (s) { return s / total; }) };
  }

  function panes(node) {
    if (!node) return [];
    if (isLeaf(node)) return [node.pane];
    return node.children.reduce(function (all, child) { return all.concat(panes(child)); }, []);
  }

  // ---- text form ------------------------------------------------------------

  function parse(text) {
    if (typeof text !== "string") return null;
    var s = text.replace(/\s+/g, "").toLowerCase();
    var i = 0;
    var seen = {};

    function node() {
      var c = s.charAt(i);
      if (c >= "1" && c <= String(MAX_PANES)) {
        i++;
        var pane = Number(c);
        if (seen[pane]) throw new Error("pane twice");
        seen[pane] = true;
        return leaf(pane);
      }
      if ((c === "h" || c === "v") && s.charAt(i + 1) === "(") {
        i += 2;
        var children = [];
        var sizes = [];
        for (;;) {
          children.push(node());
          var size = null;
          if (s.charAt(i) === "@") {
            i++;
            var m = /^\d+(\.\d+)?/.exec(s.slice(i));
            if (!m) throw new Error("bad size");
            i += m[0].length;
            size = Number(m[0]) / 100;
            if (!(size > 0 && size < 1)) throw new Error("bad size");
          }
          sizes.push(size);
          if (s.charAt(i) === ",") { i++; continue; }
          if (s.charAt(i) === ")") { i++; break; }
          throw new Error("expected , or )");
        }
        if (children.length < 2) throw new Error("split of one");
        var given = sizes.filter(function (x) { return x !== null; });
        var missing = sizes.length - given.length;
        var rest = missing ? (1 - sum(given)) / missing : 0;
        if (missing && rest <= 0) throw new Error("sizes over 100");
        return { dir: c, children: children, sizes: sizes.map(function (x) { return x === null ? rest : x; }) };
      }
      throw new Error("unexpected " + c);
    }

    try {
      var tree = node();
      return i === s.length ? normalize(tree) : null;
    } catch (_e) {
      return null;
    }
  }

  function serialize(node) {
    if (isLeaf(node)) return String(node.pane);
    var even = 1 / node.sizes.length;
    var equal = node.sizes.every(function (s) { return Math.abs(s - even) < 0.005; });
    return node.dir + "(" + node.children.map(function (child, i) {
      return serialize(child) + (equal ? "" : "@" + Math.round(node.sizes[i] * 100));
    }).join(",") + ")";
  }

  // The same text without sizes: what a tree looks like, not how big.
  function shape(node) {
    return isLeaf(node) ? String(node.pane) : node.dir + "(" + node.children.map(shape).join(",") + ")";
  }

  // ---- the six toolbar presets ------------------------------------------------

  function split(dir, children, first) {
    return { dir: dir, children: children, sizes: [first, 1 - first] };
  }

  // A preset as a tree, using the console's two shared divider positions.
  function presetTree(name, x, y) {
    x = typeof x === "number" ? x : 0.5;
    y = typeof y === "number" ? y : 0.5;
    switch (name) {
      case "hsplit":    return split("h", [leaf(1), leaf(2)], x);
      case "vsplit":    return split("v", [leaf(1), leaf(2)], y);
      case "left-main": return split("h", [leaf(1), split("v", [leaf(2), leaf(3)], y)], x);
      case "top-main":  return split("v", [leaf(1), split("h", [leaf(2), leaf(3)], x)], y);
      case "quad":      return split("v", [split("h", [leaf(1), leaf(2)], x), split("h", [leaf(3), leaf(4)], x)], y);
      default:          return leaf(1);
    }
  }

  function inPresetRange(value) {
    return value >= PRESET_MIN - EPS && value <= PRESET_MAX + EPS;
  }

  // The preset a tree is exactly, with its divider positions, or null. The
  // console shows a matching tree as that preset, so a shortcut that lands on
  // one lights up its toolbar button and keeps the preset's name in the URL.
  function matchPreset(tree) {
    var found = null;
    switch (shape(tree)) {
      case "1":                found = { name: "single" }; break;
      case "h(1,2)":           found = { name: "hsplit", x: tree.sizes[0] }; break;
      case "v(1,2)":           found = { name: "vsplit", y: tree.sizes[0] }; break;
      case "h(1,v(2,3))":      found = { name: "left-main", x: tree.sizes[0], y: tree.children[1].sizes[0] }; break;
      case "v(1,h(2,3))":      found = { name: "top-main", y: tree.sizes[0], x: tree.children[1].sizes[0] }; break;
      case "v(h(1,2),h(3,4))":
        // The quad preset has one shared vertical divider; a tree whose two
        // rows are split in different places is not it.
        if (Math.abs(tree.children[0].sizes[0] - tree.children[1].sizes[0]) > 0.005) return null;
        found = { name: "quad", y: tree.sizes[0], x: tree.children[0].sizes[0] };
        break;
      default:
        return null;
    }
    if (found.x !== undefined && !inPresetRange(found.x)) return null;
    if (found.y !== undefined && !inPresetRange(found.y)) return null;
    return found;
  }

  // ---- geometry ---------------------------------------------------------------

  // Each pane's rectangle as fractions of the whole area: { x, y, w, h }.
  function rects(tree) {
    var out = {};
    (function walk(node, box) {
      if (isLeaf(node)) {
        out[node.pane] = box;
        return;
      }
      var offset = 0;
      node.children.forEach(function (child, i) {
        var size = node.sizes[i];
        walk(child, node.dir === "h"
          ? { x: box.x + box.w * offset, y: box.y, w: box.w * size, h: box.h }
          : { x: box.x, y: box.y + box.h * offset, w: box.w, h: box.h * size });
        offset += size;
      });
    })(tree, { x: 0, y: 0, w: 1, h: 1 });
    return out;
  }

  function nodeAt(tree, path) {
    return path.reduce(function (node, i) { return node.children[i]; }, tree);
  }

  function boxAt(tree, path) {
    var box = { x: 0, y: 0, w: 1, h: 1 };
    var node = tree;
    path.forEach(function (i) {
      var offset = sum(node.sizes.slice(0, i));
      var size = node.sizes[i];
      box = node.dir === "h"
        ? { x: box.x + box.w * offset, y: box.y, w: box.w * size, h: box.h }
        : { x: box.x, y: box.y + box.h * offset, w: box.w, h: box.h * size };
      node = node.children[i];
    });
    return box;
  }

  // Moves the divider between children index and index+1 of the split at
  // `path` (child indexes from the root) to `pos`, a fraction of the whole area.
  function dragDivider(tree, path, index, pos) {
    var t = clone(tree);
    var node = nodeAt(t, path);
    if (!node || isLeaf(node) || index < 0 || index >= node.children.length - 1) return tree;
    var box = boxAt(t, path);
    var local = node.dir === "h" ? (pos - box.x) / box.w : (pos - box.y) / box.h;
    var start = sum(node.sizes.slice(0, index));
    var end = start + node.sizes[index] + node.sizes[index + 1];
    var at = Math.min(end - MIN_SIZE, Math.max(start + MIN_SIZE, local));
    node.sizes[index] = at - start;
    node.sizes[index + 1] = end - at;
    return t;
  }

  function overlap(a0, a1, b0, b1) {
    return Math.min(a1, b1) - Math.max(a0, b0);
  }

  // The pane next to `pane` in a direction: it has to touch that edge; among
  // several, the one sharing the most of it (ties go to the top/left one).
  function neighbor(tree, pane, dir) {
    var r = rects(tree);
    var me = r[pane];
    if (!me) return null;
    var best = null;
    var bestOverlap = EPS;
    panes(tree).forEach(function (other) {
      if (other === pane) return;
      var o = r[other];
      var touches;
      var shared;
      if (dir === "left" || dir === "right") {
        touches = dir === "left" ? Math.abs(o.x + o.w - me.x) < EPS : Math.abs(me.x + me.w - o.x) < EPS;
        shared = overlap(o.y, o.y + o.h, me.y, me.y + me.h);
      } else {
        touches = dir === "up" ? Math.abs(o.y + o.h - me.y) < EPS : Math.abs(me.y + me.h - o.y) < EPS;
        shared = overlap(o.x, o.x + o.w, me.x, me.x + me.w);
      }
      if (touches && shared > bestOverlap + EPS) {
        best = other;
        bestOverlap = shared;
      }
    });
    return best;
  }

  // ---- edits ------------------------------------------------------------------

  // The splits holding `pane`, innermost first: [{ node, index }], where
  // node.children[index] is the leaf itself (first entry) or the split that
  // contains it. Empty for a lone leaf; null when the pane is not in the tree.
  function ancestors(tree, pane) {
    var found = null;
    (function walk(node, chain) {
      if (found) return;
      if (isLeaf(node)) {
        if (node.pane === pane) found = chain;
        return;
      }
      node.children.forEach(function (child, i) {
        walk(child, [{ node: node, index: i }].concat(chain));
      });
    })(tree, []);
    return found;
  }

  // Removes child i, handing its share to the rest in proportion.
  function removeChild(node, i) {
    var freed = node.sizes[i];
    node.children.splice(i, 1);
    node.sizes.splice(i, 1);
    var rest = 1 - freed;
    node.sizes = node.sizes.map(function (s) { return rest > EPS ? s / rest : 1 / node.sizes.length; });
  }

  // Inserts a child at i with an equal share, shrinking the rest to make room.
  function insertChild(node, i, child) {
    var n = node.children.length + 1;
    node.sizes = node.sizes.map(function (s) { return s * (n - 1) / n; });
    node.children.splice(i, 0, child);
    node.sizes.splice(i, 0, 1 / n);
  }

  // i3's `move <dir>`: swap with a pane beside it in the same split, step into
  // a split beside it, step out past the edge of its own split, or — when no
  // split runs that way — take a whole side of the screen.
  function move(tree, pane, dir) {
    var axis = dir === "left" || dir === "right" ? "h" : "v";
    var delta = dir === "left" || dir === "up" ? -1 : 1;
    var t = clone(tree);
    var chain = ancestors(t, pane);
    if (!chain || chain.length === 0) return tree;
    var parent = chain[0].node;
    var me = parent.children[chain[0].index];

    for (var k = 0; k < chain.length; k++) {
      var node = chain[k].node;
      var index = chain[k].index;
      if (node.dir !== axis) continue;
      var target = index + delta;
      if (k === 0) {
        if (target < 0 || target >= node.children.length) continue;
        var sibling = node.children[target];
        if (isLeaf(sibling)) {
          node.children[target] = me;
          node.children[index] = sibling;
          return normalize(t);
        }
        removeChild(node, index);
        // Entering from the side lands at the near end of a split that runs
        // the same way; a perpendicular one gets it at the end.
        insertChild(sibling, sibling.dir === axis && delta > 0 ? 0 : sibling.children.length, me);
        return normalize(t);
      }
      removeChild(parent, chain[0].index);
      insertChild(node, delta < 0 ? index : index + 1, me);
      return normalize(t);
    }

    // Already filling that whole side: nothing to do.
    var r = rects(tree)[pane];
    var atEdge = axis === "h"
      ? (delta < 0 ? r.x < EPS : r.x + r.w > 1 - EPS) && r.h > 1 - EPS
      : (delta < 0 ? r.y < EPS : r.y + r.h > 1 - EPS) && r.w > 1 - EPS;
    if (atEdge) return tree;
    removeChild(parent, chain[0].index);
    var rest = normalize(t);
    return normalize({ dir: axis, children: delta < 0 ? [me, rest] : [rest, me], sizes: [0.5, 0.5] });
  }

  // Opens `newPane` beside `pane`. With `dir` (i3's split h / split v) the
  // pane is split that way; without it the new pane joins the pane's own
  // split, and a lone pane splits `fallbackDir`.
  function insert(tree, pane, newPane, dir, fallbackDir) {
    if (!tree) return leaf(newPane);
    if (panes(tree).indexOf(newPane) >= 0 || panes(tree).length >= MAX_PANES) return tree;
    var t = clone(tree);
    var chain = ancestors(t, pane);
    if (!chain) return tree;
    var wanted = dir || (chain.length ? chain[0].node.dir : fallbackDir || "h");
    if (chain.length && chain[0].node.dir === wanted) {
      insertChild(chain[0].node, chain[0].index + 1, leaf(newPane));
      return normalize(t);
    }
    var pair = { dir: wanted, children: [leaf(pane), leaf(newPane)], sizes: [0.5, 0.5] };
    if (!chain.length) return pair;
    chain[0].node.children[chain[0].index] = pair;
    return normalize(t);
  }

  function remove(tree, pane) {
    var chain = ancestors(tree, pane);
    if (!chain || chain.length === 0) return tree;
    var t = clone(tree);
    chain = ancestors(t, pane);
    removeChild(chain[0].node, chain[0].index);
    return normalize(t);
  }

  // i3's `layout toggle split`: the split holding the pane turns the other way.
  function toggleSplit(tree, pane) {
    var t = clone(tree);
    var chain = ancestors(t, pane);
    if (!chain || chain.length === 0) return tree;
    chain[0].node.dir = chain[0].node.dir === "h" ? "v" : "h";
    return normalize(t);
  }

  // i3's resize mode: grow (delta > 0) or shrink the pane along an axis ("h"
  // for width, "v" for height), taking from or giving to the neighbour after
  // it — or before it, for the last one.
  function resize(tree, pane, axis, delta) {
    var t = clone(tree);
    var chain = ancestors(t, pane);
    if (!chain) return tree;
    for (var k = 0; k < chain.length; k++) {
      var node = chain[k].node;
      if (node.dir !== axis) continue;
      var i = chain[k].index;
      var other = i + 1 < node.children.length ? i + 1 : i - 1;
      var total = node.sizes[i] + node.sizes[other];
      var mine = Math.min(total - MIN_SIZE, Math.max(MIN_SIZE, node.sizes[i] + delta));
      node.sizes[i] = mine;
      node.sizes[other] = total - mine;
      return t;
    }
    return tree;
  }

  var api = {
    MAX_PANES: MAX_PANES,
    parse: parse,
    serialize: serialize,
    shape: shape,
    panes: panes,
    presetTree: presetTree,
    matchPreset: matchPreset,
    rects: rects,
    dragDivider: dragDivider,
    neighbor: neighbor,
    move: move,
    insert: insert,
    remove: remove,
    toggleSplit: toggleSplit,
    resize: resize
  };

  root.BoothTiling = api;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
})(typeof window !== "undefined" ? window : globalThis);

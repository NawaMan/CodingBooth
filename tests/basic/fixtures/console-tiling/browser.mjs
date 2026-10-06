// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
//
// Drives a real booth's Console UI in headless Chrome and prints one line per
// case — `CASE|<n>|true|false|<description>` — for test030 to report.
//
// No Playwright: Chrome's own DevTools protocol over Node's built-in
// WebSocket (Node 22+), so it runs wherever Chrome and Node do. Keys are sent
// as real input events, so they arrive in whichever pane frame has focus —
// the xterm inside ttyd — exactly as a person's would.
//
// Usage: node browser.mjs <console-url> <container-name> [main|fallback]
//   CB_CHROME = browser binary; CB_CASE_START = number of cases already reported.
// "main" (the default) drives the console; "fallback" checks a booth started
// with a deliberately broken .booth/console.json.
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, container, phase = "main"] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let caseNo = Number(process.env.CB_CASE_START || 0);
let failed = false;
function report(ok, description, detail) {
  caseNo++;
  console.log(`CASE|${caseNo}|${ok ? "true" : "false"}|${description}`);
  if (!ok) {
    failed = true;
    console.log(`  got: ${JSON.stringify(detail)}`);
  }
}
function tmux(...args) {
  try {
    return execFileSync("docker", ["exec", "-u", "coder", container, "tmux", ...args], { encoding: "utf8" });
  } catch {
    return null;
  }
}

const profile = mkdtempSync(join(tmpdir(), "cb-console-tiling-"));
const chrome = spawn(process.env.CB_CHROME, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1400,900", "about:blank",
], { stdio: "ignore" });

let ws;
const warnings = [];
const dialogs = [];
let acceptDialogs = true;
try {
  // Chrome writes the port it picked here once DevTools is listening.
  let port;
  for (let i = 0; i < 100 && !port; i++) {
    try { port = readFileSync(join(profile, "DevToolsActivePort"), "utf8").split("\n")[0]; } catch { await sleep(100); }
  }
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.method === "Runtime.consoleAPICalled" && msg.params.type === "warning") {
      warnings.push(msg.params.args.map((a) => a.value).join(" "));
      return;
    }
    // ttyd asks "Close terminal?" (beforeunload) once a terminal has been
    // typed in; leaving the page to load it fresh has to get past that.
    if (msg.method === "Page.javascriptDialogOpening") {
      dialogs.push(msg.params.message);
      ws.send(JSON.stringify({ id: ++id, method: "Page.handleJavaScriptDialog", params: { accept: msg.params.type === "beforeunload" || acceptDialogs } }));
      return;
    }
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const n = ++id;
    pending.set(n, (msg) => (msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result)));
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  const evaluate = async (expression) => {
    const r = await send("Runtime.evaluate", { expression, returnByValue: true });
    if (r.exceptionDetails) throw new Error("page script failed: " + expression);
    return r.result.value;
  };
  async function until(expression, timeout = 30000) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      if (await evaluate(expression).catch(() => false)) return true;
      await sleep(200);
    }
    return false;
  }
  // mods: "ca" = Ctrl+Alt, "cas" = Ctrl+Alt+Shift
  async function key(mods, keyName, code, keyCode) {
    const modifiers = (mods.includes("a") ? 1 : 0) | (mods.includes("c") ? 2 : 0) | (mods.includes("s") ? 8 : 0);
    const base = { modifiers, key: keyName, code, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...base });
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
    await sleep(300);
  }
  async function typeLine(text) {
    for (const ch of text) await send("Input.dispatchKeyEvent", { type: "char", text: ch });
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    await send("Input.dispatchKeyEvent", { type: "char", text: "\r" });
    await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  }
  const STATE = `(() => ({
    hash: decodeURIComponent(location.hash),
    active: [...document.querySelectorAll('.pane.active')].map(p => p.dataset.pane).join(''),
    focused: (document.querySelector('.pane.focused') || {dataset:{}}).dataset.pane,
    keyboard: document.activeElement && document.activeElement.closest && document.activeElement.closest('.pane')
      ? document.activeElement.closest('.pane').dataset.pane : null,
    preset: (document.querySelector('[data-layout].active') || {dataset:{}}).dataset.layout || null,
    tilingButton: document.getElementById('tree-layout').classList.contains('active'),
    frames: [1,2].map(n => document.querySelector('.pane-' + n + ' .term-frame').contentWindow.performance.timeOrigin),
  }))()`;
  const termReady = (n) => `!!document.querySelector('.pane-${n} .term-frame').contentWindow.term`;

  await send("Runtime.enable");
  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
  if (phase === "fallback") {
    // .booth/console.json here is broken on purpose (see test030). The page
    // must still load, run its scripts, and keep what can be kept.
    await send("Page.navigate", { url });
    const loaded = await until(`document.readyState === 'complete' && document.querySelectorAll('.pane').length === 6`)
      && await until(termReady(1));
    await until(`document.querySelectorAll('.pane-5 .web-tab-frame').length >= 2`, 10000);
    await sleep(500);
    const f = await evaluate(`(() => ({
      preset: (document.querySelector('[data-layout].active') || {dataset:{}}).dataset.layout || null,
      active: [...document.querySelectorAll('.pane.active')].map(p => p.dataset.pane).join(''),
      web5: document.querySelector('.pane-5').classList.contains('mode-web'),
      tabs5: [...document.querySelectorAll('.pane-5 .web-tab-frame')].map(f => f.getAttribute('src')),
      web2: document.querySelector('.pane-2').classList.contains('mode-web'),
      // An unescaped </script> ends the JSON early; an unescaped <!--<script>
      // swallows the script after it, the one that sets BOOTH_CONSOLE_SPEC.
      intact: (() => { try { JSON.parse(document.getElementById('cb-console-config').textContent); return true; } catch { return false; } })(),
      specRan: window.BOOTH_CONSOLE_SPEC === "shared",
      hint: (document.getElementById('shortcut-hint') || {}).textContent || '',
    }))()`);
    report(loaded && f.intact && f.specRan && f.hint.includes("Ctrl+Alt"),
      "A console.json with </script> and <!-- inside a tab still loads the whole page and its scripts", f);
    report(f.preset === "grid6" && f.active === "123456",
      "An unknown layout falls back to one that shows every pane given tabs (pane 5: grid6)", f);
    report(f.web5 && f.tabs5.length === 2 && !f.tabs5.some((src) => /google|object/i.test(src || "")) && !f.web2,
      "Pane 5 keeps its two real tabs; a non-address tab and a non-object pane are skipped, not opened", f);
    const mine = warnings.filter((w) => w.startsWith(".booth/console.json"));
    report(mine.some((w) => /layout/.test(w)) && mine.some((w) => /pane 2/.test(w)) && mine.some((w) => /pane "9"/.test(w)) && mine.some((w) => /is not an address/.test(w)),
      "Each thing console.json had wrong is named in a console warning", mine);

    // console-spec=shared, yet the file it could not fully read is left alone,
    // even after a layout change.
    const readFile = () => { try { return execFileSync("docker", ["exec", container, "cat", "/home/coder/code/.booth/console.json"], { encoding: "utf8" }); } catch { return ""; } };
    const original = readFile();
    await evaluate(`document.querySelector('[data-layout="quad"]').click()`);
    await sleep(2000);
    report(original.includes("Not-A-Layout") && readFile() === original
        && warnings.some((w) => /not saving layout changes over a file with problems/.test(w)),
      "A console.json with problems is never saved over, even with console-spec=shared", { kept: readFile() === original });
  } else {
    await send("Page.navigate", { url: url + "#mode=single" });
    const loaded = await until(`!!window.BoothTiling && document.readyState === 'complete'`) && await until(termReady(1));
    let s = await evaluate(STATE);
    report(loaded && s.preset === "single", "The Console UI loads with the tiling engine and a live terminal", s);

    // Into session 1's terminal, then Ctrl+Alt+Enter from inside xterm.
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 700, y: 450, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 700, y: 450, button: "left", clickCount: 1 });
    await sleep(300);
    await key("ca", "Enter", "Enter", 13);
    await until(termReady(2));
    await sleep(500);
    s = await evaluate(STATE);
    report(s.preset === "hsplit" && s.focused === "2" && s.keyboard === "2",
      "Ctrl+Alt+Enter inside a terminal opens session 2 beside it and moves the keyboard there", s);

    await typeLine("echo cb-tiling-two");
    let pane2 = "";
    for (let i = 0; i < 25 && !pane2.includes("\ncb-tiling-two"); i++) { await sleep(200); pane2 = tmux("capture-pane", "-p", "-t", "s2") || ""; }
    report(pane2.includes("\ncb-tiling-two"), "Typing after the shortcut lands in session 2's shell", pane2.trim().split("\n").slice(-3));

    await key("ca", "h", "KeyH", 72);
    s = await evaluate(STATE);
    const frames = s.frames;
    await key("cas", "L", "KeyL", 76);
    s = await evaluate(STATE);
    const pane1 = tmux("capture-pane", "-p", "-t", "s1") || "";
    report(s.hash === "#mode=h(2,1)" && s.preset === null && s.tilingButton && JSON.stringify(s.frames) === JSON.stringify(frames)
        && !/\^\[|\$ [hHlL]\s*$/m.test(pane1),
      "Ctrl+Alt+h then Ctrl+Alt+Shift+l swap the sessions into tiling layout h(2,1) without reloading a terminal or typing into it", { s, frames });

    await key("cas", "Q", "KeyQ", 81);
    s = await evaluate(STATE);
    const hiddenAlive = tmux("has-session", "-t", "s1") !== null;
    await key("ca", "1", "Digit1", 49);
    const back = await evaluate(STATE);
    report(s.active === "2" && hiddenAlive && back.active === "12" && back.focused === "1" && JSON.stringify(back.frames) === JSON.stringify(frames),
      "Ctrl+Alt+Shift+q hides session 1 with its tmux session still running; Ctrl+Alt+1 brings the same terminal back", { closed: s, hiddenAlive, back });

    const HELP = `(() => { const b = document.getElementById('bl-help-btn'); const o = document.getElementById('bl-help-dialog-overlay');
      const p = document.getElementById('bl-help-panel-console');
      return { button: !!b && b.style.display !== 'none', tabs: [...o.querySelectorAll('.msg-tab')].map(t => t.dataset.tab).join(','),
        open: o.classList.contains('visible'), active: (o.querySelector('.msg-tab.active') || {dataset:{}}).dataset.tab || null,
        tableHeight: p ? Math.round(p.getBoundingClientRect().height) : 0,
      picture: !!(p && p.querySelector('img') && p.querySelector('img').complete && p.querySelector('img').naturalWidth > 0) }; })()`;
    let h = await evaluate(HELP);
    const listed = h.button && h.tabs === "general,console";
    await evaluate(`document.getElementById('bl-help-btn').click()`);
    await sleep(300);
    h = await evaluate(HELP);
    report(listed && h.open && h.active === "console" && h.tableHeight > 100 && h.picture,
      "The Booth panel's CodingBooth Help opens on a visible Console Shortcuts tab with its home-row picture (General kept, Clipboard left out)", h);

    // ---- layouts: the toolbar, console.json, Reload, + / −, columns first ----
    const boothPort = new URL(url).port;
    const LAYOUT = `(() => ({
      buttons: [...document.querySelectorAll('[data-layout]')].map(b => b.dataset.layout).join(','),
      preset: (document.querySelector('[data-layout].active') || {dataset:{}}).dataset.layout || null,
      active: [...document.querySelectorAll('.pane.active')].map(p => p.dataset.pane).join(''),
      other: getComputedStyle(document.getElementById('tree-layout')).display !== 'none',
      otherLit: document.getElementById('tree-layout').classList.contains('active'),
      addOff: document.getElementById('pane-add').disabled,
      removeOff: document.getElementById('pane-remove').disabled,
      handles: [...document.querySelectorAll('.tree-handle')].map(h => h.classList.contains('split-handle-x') ? 'x' : 'y').sort().join(''),
      web5: document.querySelector('.pane-5').classList.contains('mode-web'),
      tab5: [...document.querySelectorAll('.pane-5 .web-tab-frame')].map(f => f.getAttribute('src')),
    }))()`;
    const origin = (n) => `document.querySelector('.pane-${n} .term-frame').contentWindow.performance.timeOrigin`;

    let l = await evaluate(LAYOUT);
    report(l.buttons === "single,hsplit,left-main,right-main,vsplit,top-main,bottom-main,quad,grid6",
      "The toolbar has a button for every 2x2 layout and the 3x2 grid", l.buttons);

    // A browser that has never opened this console starts from .booth/console.json.
    await evaluate(`localStorage.clear()`);
    await send("Page.navigate", { url: url + "?fresh=1" });
    const fresh = await until(`document.readyState === 'complete' && !!document.querySelector('.pane-6')`) && await until(termReady(6));
    await until(`document.querySelectorAll('.pane-5 .web-tab-frame').length > 0`, 10000);
    l = await evaluate(LAYOUT);
    report(fresh && l.preset === "grid6" && l.active === "123456" && l.web5 && l.tab5.some(src => src.includes("127.0.0.1:" + boothPort))
        && !l.other && l.addOff && !l.removeOff && l.handles === "xxyyy",
      "console.json's grid6 opens six live sessions in three columns, pane 5 in Web view, + greyed at six", l);

    // Pane 5 shows an outside (cross-origin) site; pane 6, after it, a terminal.
    const before = await evaluate(origin(6));
    await evaluate(`document.getElementById('reload').click()`);
    const reloaded = await until(`${origin(6)} !== ${before}`, 10000) && await until(termReady(6));
    report(reloaded, "Reload goes past a web tab showing an outside site and still reloads the terminal after it", { before });

    await evaluate(`document.getElementById('pane-remove').click()`);
    await sleep(300);
    const five = await evaluate(LAYOUT);
    await evaluate(`document.getElementById('pane-add').click()`);
    await sleep(300);
    const sixAgain = await evaluate(LAYOUT);
    report(five.active.length === 5 && five.preset === null && five.other && five.otherLit && !five.addOff
        && sixAgain.active === "123456" && sixAgain.addOff,
      "The − button closes a pane, five panes show as Other, and + brings the sixth back", { five, sixAgain });

    await evaluate(`document.querySelector('[data-layout="quad"]').click()`);
    await sleep(300);
    l = await evaluate(LAYOUT);
    // Drag the left column's top/bottom divider up; the right column's stays.
    const handle = await evaluate(`(() => { const h = [...document.querySelectorAll('.tree-handle.split-handle-y')]
      .map(e => e.getBoundingClientRect()).sort((a, b) => a.left - b.left)[0]; return { x: h.left + h.width / 2, y: h.top + h.height / 2 }; })()`);
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: handle.x, y: handle.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: handle.x, y: handle.y - 120, button: "left" });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: handle.x, y: handle.y - 120, button: "left", clickCount: 1 });
    await sleep(300);
    const heights = await evaluate(`[1, 2].map(n => Math.round(document.querySelector('.pane-' + n).getBoundingClientRect().height))`);
    const after = await evaluate(LAYOUT);
    report(l.active === "1234" && l.handles === "xyy" && heights[0] < heights[1] - 80 && after.preset === "quad" && !after.other,
      "quad is columns first: one column's divider moves on its own and the layout is still quad", { l, heights, after });

    // console-spec=shared: the dragged quad is saved as its whole tree, which
    // reads back as quad; an untouched preset is saved by name.
    let saved = "";
    for (let i = 0; i < 20 && !/^h\(v\(1@\d+,3@\d+\),v\(2,4\)\)$/.test(saved); i++) {
      await sleep(250);
      try { saved = JSON.parse(execFileSync("docker", ["exec", container, "cat", "/home/coder/code/.booth/console.json"], { encoding: "utf8" })).layout || ""; } catch { saved = ""; }
    }
    await evaluate(`document.querySelector('[data-layout="hsplit"]').click()`);
    let named = "";
    for (let i = 0; i < 20 && named !== "hsplit"; i++) {
      await sleep(250);
      try { named = JSON.parse(execFileSync("docker", ["exec", container, "cat", "/home/coder/code/.booth/console.json"], { encoding: "utf8" })).layout || ""; } catch { named = ""; }
    }
    report(/^h\(v\(1@\d+,3@\d+\),v\(2,4\)\)$/.test(saved) && named === "hsplit",
      "console.json saves a resized preset as its whole tree, and an untouched one by name", { saved, named });

    // Back to the dragged quad, then Ctrl+Alt+= evens it out.
    await evaluate(`document.querySelector('[data-layout="quad"]').click()`);
    await sleep(300);
    const unequal = await evaluate(`[1, 3].map(n => Math.round(document.querySelector('.pane-' + n).getBoundingClientRect().height))`);
    await key("ca", "=", "Equal", 187);
    const even = await evaluate(`[1, 3].map(n => Math.round(document.querySelector('.pane-' + n).getBoundingClientRect().height))`);
    const eq = await evaluate(LAYOUT);
    let evenSaved = "";
    for (let i = 0; i < 20 && evenSaved !== "quad"; i++) {
      await sleep(250);
      try { evenSaved = JSON.parse(execFileSync("docker", ["exec", container, "cat", "/home/coder/code/.booth/console.json"], { encoding: "utf8" })).layout || ""; } catch { evenSaved = ""; }
    }
    report(Math.abs(unequal[0] - unequal[1]) > 80 && Math.abs(even[0] - even[1]) <= 2 && eq.preset === "quad" && evenSaved === "quad",
      "Ctrl+Alt+= equalizes a dragged quad: still quad, saved by name again", { unequal, even, preset: eq.preset, evenSaved });

    // Reset session 2: Cancel on the confirmation leaves it running; OK ends
    // its tmux session and the pane reconnects to a fresh one.
    const sessionId = () => ((tmux("list-sessions", "-F", "#{session_name} #{session_id}") || "")
      .split("\n").find((l) => l.startsWith("s2 ")) || "").slice(3);
    await until(termReady(2));
    const firstId = sessionId();
    acceptDialogs = false;
    dialogs.length = 0;
    await evaluate(`document.querySelector('.session-reset[data-session="2"]').click()`);
    await sleep(1000);
    const keptId = sessionId();
    const asked = dialogs.slice();
    acceptDialogs = true;
    const p2 = await evaluate(`(() => { const r = document.querySelector('.pane-2').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: p2.x, y: p2.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: p2.x, y: p2.y, button: "left", clickCount: 1 });
    await sleep(300);
    await key("cas", "X", "KeyX", 88);
    let newId = "";
    for (let i = 0; i < 40 && (!newId || newId === firstId); i++) { await sleep(250); newId = sessionId(); }
    report(firstId && keptId === firstId && asked.some((m) => /Reset session 2\?/.test(m))
        && dialogs.length >= 2 && newId && newId !== firstId,
      "Reset session asks first: Cancel keeps session 2 running, Ctrl+Alt+Shift+x then OK gives the pane a fresh one", { firstId, keptId, newId, asked });
  }
} catch (e) {
  report(false, "The browser run completed", String(e && e.stack || e));
} finally {
  try { ws && ws.close(); } catch {}
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);

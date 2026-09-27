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
// Usage: node browser.mjs <console-url> <container-name>   (CB_CHROME = browser binary)
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, container] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let caseNo = 0;
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
      tableHeight: p ? Math.round(p.getBoundingClientRect().height) : 0 }; })()`;
  let h = await evaluate(HELP);
  const listed = h.button && h.tabs === "general,console";
  await evaluate(`document.getElementById('bl-help-btn').click()`);
  await sleep(300);
  h = await evaluate(HELP);
  report(listed && h.open && h.active === "console" && h.tableHeight > 100,
    "The Booth panel's CodingBooth Help opens on a visible Console Shortcuts tab (General kept, Clipboard left out)", h);
} catch (e) {
  report(false, "The browser run completed", String(e && e.stack || e));
} finally {
  try { ws && ws.close(); } catch {}
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);

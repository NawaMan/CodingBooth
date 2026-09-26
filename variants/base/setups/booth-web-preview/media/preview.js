// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
(() => {
  "use strict";
  const { parseTarget } = BoothPreview;
  const frame = document.getElementById("app");
  const input = document.getElementById("address");
  const error = document.getElementById("error");
  const externalHint = document.getElementById("external-hint");
  const back = document.getElementById("back");
  const forward = document.getElementById("forward");
  const prefix = location.pathname.slice(0, -"/booth-preview/index.html".length);
  // Opened by code-server's extension, the hash carries the first address and
  // the token its bridge checks. Opened on its own (the notebook variant's
  // Launcher tile) there is no bridge: these controls open pages in the browser
  // themselves and keep the current address in their own hash across reloads.
  let initial = {};
  if (location.hash.length > 1) {
    try { initial = JSON.parse(decodeURIComponent(location.hash.slice(1))) || {}; }
    catch { error.textContent = "This preview's address could not be read. Open Web Preview again."; error.hidden = false; return; }
  }
  const standalone = !initial.token;
  // Standalone inside JupyterLab, the tabs are JupyterLab's own: the notebook
  // variant has it expose itself (LabApp.expose_app_in_browser), and this page
  // is same-origin with it. Anywhere else there is no editor to add a tab to.
  const lab = standalone ? jupyterApp() : null;
  // Everything below that touches JupyterLab goes through this: its objects are
  // not a stable API, and a change there may only cost ＋, the tab title, the
  // saved address or theme matching — never navigation in these controls.
  function labSafely(fn, fallback = null) {
    try {
      const result = fn();
      if (result && typeof result.catch === "function") result.catch(failure => console.warn("Web Preview (JupyterLab):", failure));
      return result;
    } catch (failure) {
      console.warn("Web Preview (JupyterLab):", failure);
      return fallback;
    }
  }
  document.getElementById("new").hidden = standalone && !lab;
  // The Markdown shortcut is the notebook variant's, matching the Console UI's.
  document.getElementById("markdown").hidden = !lab;
  // Match JupyterLab's light/dark theme, including a switch made while open;
  // it marks the choice on its <body>. Elsewhere the OS preference applies.
  if (lab) labSafely(() => {
    const labBody = window.parent.document.body;
    const followTheme = () => labSafely(() => {
      const light = labBody.dataset.jpThemeLight;
      if (light === "true" || light === "false") document.documentElement.dataset.theme = light === "true" ? "light" : "dark";
      else delete document.documentElement.dataset.theme;
    });
    followTheme();
    new MutationObserver(followTheme).observe(labBody, { attributes: true, attributeFilter: ["data-jp-theme-light"] });
  });
  let current;
  let entries = [];
  let position = -1;
  let loading = false;
  let navigation = 0;
  const VIEWMD_PORT = 8765;

  function jupyterApp() {
    try {
      const app = window.parent !== window && window.parent.jupyterapp;
      return app && app.commands && app.shell ? app : null;
    } catch { return null; }
  }
  // The JupyterLab tab (a MainAreaWidget around an IFrame) holding this page.
  function labTab() {
    return labSafely(() => {
      for (const widget of lab.shell.widgets("main")) {
        if (widget.node.contains(window.frameElement)) return widget;
      }
      return null;
    });
  }
  // JupyterLab saves a tab's url only when the tab is created, so a restored
  // tab would reopen where it started. Each tab keeps its latest address here
  // instead, under the id jupyter-server-proxy gives the tab's IFrame (the one
  // it restores; the outer tab's own id is regenerated on every load). Keys of
  // tabs that are gone are pruned.
  const savedKey = id => "cb.webPreview.tab." + id;
  const tabId = tab => labSafely(() => (tab.content && tab.content.id) || tab.id, "");
  function savedAddress() {
    const tab = lab && labTab();
    try { return tab ? localStorage.getItem(savedKey(tabId(tab))) : null; } catch { return null; }
  }
  function saveAddress(tab, address) {
    try {
      localStorage.setItem(savedKey(tabId(tab)), address);
      labSafely(() => lab.restored.then(() => {
        const open = new Set(Array.from(lab.shell.widgets("main"), widget => savedKey(tabId(widget))));
        for (let i = localStorage.length - 1; i >= 0; i--) {
          const key = localStorage.key(i);
          if (key && key.startsWith(savedKey("")) && !open.has(key)) localStorage.removeItem(key);
        }
      }));
    } catch { /* Storage unavailable: the tab restores at its opening address. */ }
  }
  function shellUrl(address) {
    return location.origin + location.pathname + "#" + encodeURIComponent(JSON.stringify({ address }));
  }
  function targetUrl(target) {
    return target.port ? new URL(prefix + "/proxy/" + target.port + target.path, location.href).href : target.url;
  }
  function notify(type) {
    if (!current) return;
    if (!standalone) {
      parent.postMessage({ type, address: current.address, token: initial.token }, "*");
    } else if (type === "state") {
      const url = shellUrl(current.address);
      history.replaceState(null, "", url);
      const tab = lab && labTab();
      if (tab) {
        labSafely(() => { tab.title.label = current.title; });
        saveAddress(tab, current.address);
      }
    } else if (type === "external") {
      window.open(targetUrl(current), "_blank", "noopener");
    } else if (type === "new" && lab) {
      // jupyter-server-proxy's own open command: a fresh id is a fresh tab,
      // tracked and restored like the one its Launcher tile opens.
      const id = "server-proxy:booth-web-preview-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
      labSafely(() => lab.commands.execute("server-proxy:open", { id, title: current.title, url: shellUrl(current.address), newBrowserTab: false }));
    }
  }
  function update(target, record = true) {
    if (record && entries[position] !== target.address) {
      entries = entries.slice(0, position + 1);
      entries.push(target.address);
      position = entries.length - 1;
    }
    current = target;
    externalHint.hidden = !!target.port;
    externalHint.textContent = !target.port && location.protocol === "https:" && target.url.startsWith("http:")
      ? "HTTP pages cannot be embedded in this HTTPS booth. Use an HTTPS address or Open in browser (↗)."
      : "Some sites block embedded previews. Use Open in browser (↗) if the page does not load. The address tracks pages opened with these controls.";
    if (document.activeElement !== input) input.value = target.address;
    back.disabled = position <= 0;
    forward.disabled = position >= entries.length - 1;
    notify("state");
  }
  function load(url) {
    // Replace navigations initiated by these controls; our bounded history
    // never backs out of the preview into the surrounding editor.
    try {
      // Replacing the same URL (especially one with a fragment after
      // pushState) can be a same-document no-op. Reload must hit the server.
      if (frame.contentWindow.location.href === url) frame.contentWindow.location.reload();
      else frame.contentWindow.location.replace(url);
    }
    catch { frame.src = url; }
  }
  function navigate(value, record = true) {
    try {
      const target = parseTarget(value, current && current.address);
      error.hidden = true;
      update(target, record);
      input.value = target.address;
      input.blur();
      loading = true;
      const url = targetUrl(target);
      const seq = ++navigation;
      if (target.port !== VIEWMD_PORT) { load(url); return; }
      // The Markdown viewer is started on demand, as the Console UI's is. The
      // endpoint is a no-op when something already serves the port. A slower
      // start must not override a navigation made while it was pending.
      fetch(prefix + "/booth-messages/api/viewmd", { method: "POST" })
        .then(response => { if (!response.ok) throw new Error("The Markdown viewer did not start."); })
        .then(() => { if (seq === navigation) load(url); },
              failure => { if (seq === navigation) { loading = false; error.textContent = failure.message; error.hidden = false; } });
    } catch (failure) {
      error.textContent = failure.message;
      error.hidden = false;
    }
  }
  function observe(replaceEntry = false) {
    if (loading || !current || !current.port) return;
    try {
      const url = new URL(frame.contentWindow.location.href);
      if (url.origin !== location.origin) return;
      const match = url.pathname.slice(prefix.length).match(/^\/proxy\/([0-9]+)(\/.*)?$/);
      if (!match) {
        error.textContent = "This page left the preview path. Reload the booth address or use Open in browser.";
        error.hidden = false;
        return;
      }
      const next = parseTarget(match[1] + (match[2] || "/") + url.search + url.hash);
      if (!current || next.address !== current.address) {
        // A redirect completes the requested navigation; it is not an extra
        // history entry, or Back would repeatedly revisit the redirect.
        if (replaceEntry) entries[position] = next.address;
        update(next, !replaceEntry);
      }
    } catch { /* Cross-origin navigation cannot be observed; retain the entered address. */ }
  }
  frame.addEventListener("load", () => { const requested = loading; loading = false; observe(requested); });
  // Includes SPA pushState/replaceState and fragment navigation without injecting
  // code into the application or replacing its networking APIs.
  setInterval(observe, 250);
  document.getElementById("navigation").addEventListener("submit", (event) => { event.preventDefault(); navigate(input.value); });
  back.addEventListener("click", () => { if (position > 0) navigate(entries[--position], false); });
  forward.addEventListener("click", () => { if (position + 1 < entries.length) navigate(entries[++position], false); });
  document.getElementById("reload").addEventListener("click", () => { if (current) navigate(current.address, false); });
  document.getElementById("new").addEventListener("click", () => notify("new"));
  document.getElementById("external").addEventListener("click", () => notify("external"));
  document.getElementById("markdown").addEventListener("click", () => navigate("http://booth:" + VIEWMD_PORT + "/"));
  const start = savedAddress() || initial.address;
  if (start) navigate(start);
  else {
    // Most previews are a booth server: only the port is left to type.
    input.value = "http://booth:";
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  }
})();

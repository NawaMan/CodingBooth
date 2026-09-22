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
  let initial;
  try { initial = JSON.parse(decodeURIComponent(location.hash.slice(1))); }
  catch { error.textContent = "Open this preview with CodingBooth: Open Web Preview."; error.hidden = false; return; }
  let current;
  let entries = [];
  let position = -1;
  let loading = false;

  function notify(type) {
    if (current) parent.postMessage({ type, address: current.address, token: initial.token }, "*");
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
  function navigate(value, record = true) {
    try {
      const target = parseTarget(value, current && current.address);
      error.hidden = true;
      update(target, record);
      input.value = target.address;
      input.blur();
      loading = true;
      const url = target.port ? new URL(prefix + "/proxy/" + target.port + target.path, location.href).href : target.url;
      // Replace navigations initiated by these controls; our bounded history
      // never backs out of the preview into the surrounding editor.
      try {
        // Replacing the same URL (especially one with a fragment after
        // pushState) can be a same-document no-op. Reload must hit the server.
        if (frame.contentWindow.location.href === url) frame.contentWindow.location.reload();
        else frame.contentWindow.location.replace(url);
      }
      catch { frame.src = url; }
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
  navigate(initial.address);
})();

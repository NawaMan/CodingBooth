// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
// Shared address rules for the extension host and browser controls.
(function (root) {
  "use strict";
  function boothTarget(port, rest) {
    port = Number(port);
    if (port < 1 || port > 65535) throw new Error("Port must be between 1 and 65535.");
    // 10000-10007: the booth port and its helpers; 19999: code-server;
    // 18888: JupyterLab. Each variant's editor sits behind the wrapper already.
    if ((port >= 10000 && port <= 10007) || port === 19999 || port === 18888) {
      throw new Error("That port is reserved for Booth services.");
    }
    const url = new URL(`http://booth:${port}${rest || "/"}`);
    // URL removes :80; keep the port explicit in the user-facing address.
    const path = url.pathname + url.search + url.hash;
    return { kind: "booth", port, path, address: `http://booth:${port}${path}`, title: `Web · ${port}${path === "/" ? "" : path}` };
  }
  function externalTarget(value) {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol)) throw new Error("Only HTTP and HTTPS addresses can be previewed.");
    if (url.username || url.password) throw new Error("Enter an address without embedded credentials.");
    if (url.hostname === "booth") throw new Error("Use http://booth:<port>/ for booth servers.");
    return { kind: "external", port: null, url: url.href, address: url.href, title: `Web · ${url.host}` };
  }
  function parseTarget(input, current) {
    const value = String(input || "").trim();
    if (!value) throw new Error("Enter a port, web address, or search terms.");
    if (value.startsWith("//")) throw new Error("Include http:// or https:// before the host.");
    if (/^[/?#]/.test(value)) {
      if (!current) throw new Error("Open a page before entering a relative address.");
      const base = parseTarget(current);
      const url = new URL(value, base.url || base.address);
      return base.port ? boothTarget(base.port, url.pathname + url.search + url.hash) : externalTarget(url.href);
    }
    const match = value.match(/^(?:http:\/\/booth:|booth:|:)?([0-9]+)([/?#].*)?$/i);
    if (match) return boothTarget(match[1], match[2]);
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return externalTarget(value);
    if (/^(?:https?|booth|javascript|data|file|vbscript|about|blob):/i.test(value)) {
      throw new Error("Enter a valid HTTP or HTTPS address.");
    }
    // Match the console web panel: browser-local hosts default to HTTP,
    // other bare domains or host:port addresses default to HTTPS.
    if (/^(localhost|127\.0\.0\.1)(?::[0-9]+)?([/?#].*)?$/i.test(value)) return externalTarget("http://" + value);
    if (/^[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:[:][0-9]+)?([/?#].*)?$/i.test(value) ||
        /^[a-z0-9-]+:[0-9]+([/?#].*)?$/i.test(value)) return externalTarget("https://" + value);
    // Keep the query as the saved address so duplication and restoration do
    // not replace the user's words with Google's generated URL.
    return { kind: "search", port: null, address: value, title: `Search: ${value}`,
      url: "https://www.google.com/search?q=" + encodeURIComponent(value) + "&igu=1" };
  }
  if (typeof module !== "undefined") module.exports = { parseTarget };
  else root.BoothPreview = { parseTarget };
})(typeof globalThis !== "undefined" ? globalThis : this);

// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
const vscode = require("vscode");
const crypto = require("crypto");
const { parseTarget } = require("./media/target");
const viewType = "codingbooth.webPreview";
const panels = new Set();

async function resolveAddress(address) {
  const target = parseTarget(address);
  if (!target.port) return new URL(target.url);
  const uri = await vscode.env.asExternalUri(vscode.Uri.parse(`http://127.0.0.1:${target.port}/`));
  const external = new URL(uri.toString(true));
  // URI.parse decodes query delimiters. Resolve only the proxy base through
  // VS Code, then append the encoded application path/query unchanged.
  return new URL(external.origin + external.pathname.replace(/\/?$/, "/") + target.path.slice(1));
}

async function initializePanel(context, panel, address) {
  const target = parseTarget(address);
  // Resolve the Booth shell even for an external first destination.
  // asExternalUri maps the port without contacting a server.
  const external = await resolveAddress(target.port ? target.address : "3000");
  const suffix = external.pathname.match(/^(.*)\/proxy\/[0-9]+(?:\/|$)/);
  if (!suffix) throw new Error("Web Preview requires CodingBooth's code-server path proxy.");
  const shell = new URL(`${suffix[1]}/booth-preview/index.html`, external);
  const token = crypto.randomBytes(24).toString("hex");
  shell.hash = encodeURIComponent(JSON.stringify({ address: target.address, token }));
  panel.title = target.title;
  panel.webview.options = { enableScripts: true, localResourceRoots: [context.extensionUri] };
  const bridge = panel.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, "bridge.js"));
  const nonce = crypto.randomBytes(16).toString("hex");
  const attr = (value) => String(value).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  // Booth applications share the controls' origin, so their navigation can
  // be observed. External pages keep their own origin and framing policies.
  // The bridge carries only UI state.
  panel.webview.html = `<!doctype html><html><head>
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src ${attr(shell.origin)}; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}';">
    <style nonce="${nonce}">html,body,iframe{width:100%;height:100%;margin:0;padding:0;border:0;overflow:hidden}body{background:var(--vscode-editor-background)}</style>
    </head><body><iframe id="preview" title="Booth Web Preview" data-src="${attr(shell.href)}" data-token="${token}" data-address="${attr(target.address)}" sandbox="allow-scripts allow-same-origin allow-forms allow-downloads"></iframe>
    <script nonce="${nonce}" src="${attr(bridge)}"></script></body></html>`;
  const listener = panel.webview.onDidReceiveMessage(async (message) => {
    if (!message || !["state", "new", "external"].includes(message.type)) return;
    try {
      const next = parseTarget(message.address);
      if (message.type === "state") panel.title = next.title;
      if (message.type === "new") await vscode.commands.executeCommand(viewType, next.address);
      // vscode.open accepts a URL string and preserves encoded query values;
      // parsing it into a URI first loses literal &, + and # in searches.
      if (message.type === "external") await vscode.commands.executeCommand("vscode.open", (await resolveAddress(next.address)).href);
    } catch (error) {
      vscode.window.showErrorMessage(error.message);
    }
  });
  panels.add(panel);
  panel.onDidDispose(() => { listener.dispose(); panels.delete(panel); });
}

function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand(viewType, async (address) => {
    if (typeof address !== "string") {
      address = await vscode.window.showInputBox({
        title: "Open Booth Web Preview",
        prompt: "Port, web address, or Google search — each preview opens in its own editor tab",
        placeHolder: "3000, example.com, or search terms",
        validateInput: (input) => { try { parseTarget(input); } catch (error) { return error.message; } }
      });
    }
    if (!address) return;
    let panel;
    try {
      parseTarget(address);
      const column = [...panels].some(preview => preview.active) ? vscode.ViewColumn.Active : vscode.ViewColumn.Beside;
      panel = vscode.window.createWebviewPanel(viewType, "Web Preview", column, {
        enableScripts: true, retainContextWhenHidden: true
      });
      await initializePanel(context, panel, address);
    } catch (error) {
      if (panel) panel.dispose();
      vscode.window.showErrorMessage(error.message);
    }
  }));
  context.subscriptions.push(vscode.window.registerWebviewPanelSerializer(viewType, {
    async deserializeWebviewPanel(panel, state) {
      try { await initializePanel(context, panel, state.address); }
      catch (error) { panel.dispose(); vscode.window.showErrorMessage(`Could not restore Web Preview: ${error.message}`); }
    }
  }));
  const button = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 10);
  button.text = "$(globe) Web Preview";
  button.tooltip = "Open a booth server, web page, or Google search in a new preview tab";
  button.command = viewType;
  button.show();
  context.subscriptions.push(button);
}
module.exports = { activate };

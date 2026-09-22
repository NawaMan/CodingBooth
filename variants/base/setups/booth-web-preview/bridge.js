// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
(() => {
  const vscode = acquireVsCodeApi();
  const frame = document.getElementById("preview");
  const origin = new URL(frame.dataset.src).origin;
  vscode.setState({ address: frame.dataset.address });
  window.addEventListener("message", (event) => {
    if (event.source !== frame.contentWindow || event.origin !== origin) return;
    const message = event.data;
    if (!message || message.token !== frame.dataset.token) return;
    if (message.type === "state") vscode.setState({ address: message.address });
    if (["state", "new", "external"].includes(message.type)) {
      vscode.postMessage({ type: message.type, address: message.address });
    }
  });
  // Initialize persistent state and the listener before the embedded controls
  // can send their first navigation message or the tab can be hidden.
  frame.src = frame.dataset.src;
})();

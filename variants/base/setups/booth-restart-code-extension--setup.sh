#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-restart-code-extension--setup.sh
#
# Installs a bundled code-server extension that provides:
#   - Command palette entry: "CodingBooth: Restart"
#   - Status bar button (sync icon) for easy access
#   - Confirmation dialog before restart
#
# The extension calls booth--restart --yes to restart the container.
# Packages a .vsix and installs via CLI for proper registration.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/libs/code-extension-source.sh"

EXT_NAME="booth-restart"
EXT_PUBLISHER="codingbooth"
EXT_VERSION="1.0.0"

build_vsix() {
  local tmp
  tmp=$(mktemp -d)

  # Extension source files
  mkdir -p "$tmp/extension"

  cat > "$tmp/extension/package.json" <<'JSON'
{
  "name": "booth-restart",
  "displayName": "CodingBooth: Restart",
  "description": "Restart the CodingBooth container from within VS Code",
  "publisher": "codingbooth",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.60.0"
  },
  "categories": ["Other"],
  "activationEvents": ["onStartupFinished"],
  "main": "./extension.js",
  "contributes": {
    "commands": [
      {
        "command": "codingbooth.restart",
        "title": "CodingBooth: Restart"
      }
    ]
  }
}
JSON

  cat > "$tmp/extension/extension.js" <<'JS'
const vscode = require("vscode");
const { spawn } = require("child_process");
const fs = require("fs");

const RESTART_MARKER = "/tmp/.booth-restarting";

function activate(context) {
  const statusBar = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    -100
  );
  statusBar.text = "$(sync) Restart";
  statusBar.tooltip = "Restart CodingBooth (re-reads config)";
  statusBar.command = "codingbooth.restart";
  statusBar.show();
  context.subscriptions.push(statusBar);

  context.subscriptions.push(
    vscode.commands.registerCommand("codingbooth.restart", async () => {
      const answer = await vscode.window.showWarningMessage(
        "Restart this CodingBooth container?",
        { modal: true, detail: "The server will restart with updated configuration. This may take some time \u2014 please retry after a moment." },
        "Restart"
      );
      if (answer !== "Restart") return;

      // Hide the restart button once confirmed
      statusBar.hide();

      // Launch restart detached so it survives even if code-server starts dying
      const child = spawn("booth--restart", ["--yes"], {
        detached: true,
        stdio: "ignore"
      });
      child.unref();

      // Show progress and poll for the restart marker
      vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: "CodingBooth",
          cancellable: false
        },
        (progress) => new Promise((resolve) => {
          progress.report({ message: "Restarting..." });

          function reloadWindow() {
            resolve();
            vscode.commands.executeCommand("workbench.action.reloadWindow");
          }

          let elapsed = 0;
          const interval = setInterval(() => {
            elapsed += 500;
            if (fs.existsSync(RESTART_MARKER)) {
              clearInterval(interval);
              reloadWindow();
              return;
            }
            if (elapsed >= 15000) {
              clearInterval(interval);
              reloadWindow();
            }
          }, 500);
        })
      );
    })
  );

}

function deactivate() {}

module.exports = { activate, deactivate };
JS

  # VSIX manifest (required by VS Code / code-server)
  cat > "$tmp/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="${EXT_NAME}" Version="${EXT_VERSION}" Publisher="${EXT_PUBLISHER}" />
    <DisplayName>CodingBooth: Restart</DisplayName>
    <Description xml:space="preserve">Restart the CodingBooth container from within VS Code</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.60.0" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui,workspace" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
XML

  cat > "$tmp/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json" />
  <Default Extension=".js" ContentType="application/javascript" />
  <Default Extension=".vsixmanifest" ContentType="text/xml" />
</Types>
XML

  # Package as .vsix (zip)
  local vsix="/tmp/${EXT_PUBLISHER}.${EXT_NAME}-${EXT_VERSION}.vsix"
  (cd "$tmp" && zip -qr "$vsix" .)
  rm -rf "$tmp"
  echo "$vsix"
}

# Build the .vsix once
VSIX_PATH=$(build_vsix)
echo "📦 Built extension: $VSIX_PATH"

installed=0

if command -v code-server >/dev/null 2>&1; then
  if is_qemu; then
    echo "⚠️  QEMU detected — deferring booth-restart extension install to first launch."
    installed=1   # not an error
  else
    echo "Installing booth-restart extension for code-server..."
    cli_bin="$(cli_bin_for_install code-server)"
    "$cli_bin" --install-extension "$VSIX_PATH" --extensions-dir "$CODESERVER_EXTENSION_DIR" --force
    find "$CODESERVER_EXTENSION_DIR" -type d -exec chmod a+w {} +
    echo "  ✔ Installed for code-server"
    installed=1
  fi
fi

rm -f "$VSIX_PATH"

if (( installed == 0 )); then
  echo "⚠ code-server not found; skipping booth-restart extension." >&2
fi

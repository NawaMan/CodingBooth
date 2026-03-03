#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-shutdown-code-extension--setup.sh
#
# Installs a bundled VS Code / code-server extension that provides:
#   - Command palette entry: "CodingBooth: Shut Down"
#   - Status bar button (power icon) for easy access
#   - Confirmation dialog before shutdown
#
# The extension calls booth--shutdown to gracefully stop the container.
# Packages a .vsix and installs via CLI for proper registration.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/libs/code-extension-source.sh"

EXT_NAME="booth-shutdown"
EXT_PUBLISHER="codingbooth"
EXT_VERSION="1.0.0"

build_vsix() {
  local tmp
  tmp=$(mktemp -d)

  # Extension source files
  mkdir -p "$tmp/extension"

  cat > "$tmp/extension/package.json" <<'JSON'
{
  "name": "booth-shutdown",
  "displayName": "CodingBooth: Shutdown",
  "description": "Shut down the CodingBooth container from within VS Code",
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
        "command": "codingbooth.shutdown",
        "title": "CodingBooth: Shut Down"
      }
    ]
  }
}
JSON

  cat > "$tmp/extension/extension.js" <<'JS'
const vscode = require("vscode");
const { exec } = require("child_process");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("codingbooth.shutdown", async () => {
      const answer = await vscode.window.showWarningMessage(
        "Shut down this CodingBooth container?",
        { modal: true, detail: "All terminal sessions will be closed and the container will stop." },
        "Shut Down"
      );
      if (answer !== "Shut Down") return;

      vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: "Shutting down CodingBooth\u2026",
          cancellable: false
        },
        () => new Promise((resolve) => {
          exec("booth--shutdown", () => resolve());
          // Resolve after a timeout in case the process is killed before callback fires
          setTimeout(resolve, 10000);
        })
      );
    })
  );

  const statusBar = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    0
  );
  statusBar.text = "$(close) Shut Down";
  statusBar.tooltip = "Shut down CodingBooth";
  statusBar.command = "codingbooth.shutdown";
  statusBar.show();
  context.subscriptions.push(statusBar);
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
    <DisplayName>CodingBooth: Shutdown</DisplayName>
    <Description xml:space="preserve">Shut down the CodingBooth container from within VS Code</Description>
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
  echo "Installing booth-shutdown extension for code-server..."
  cli_bin="$(cli_bin_for_install code-server)"
  "$cli_bin" --install-extension "$VSIX_PATH" --extensions-dir "$CODESERVER_EXTENSION_DIR" --force
  find "$CODESERVER_EXTENSION_DIR" -type d -exec chmod a+w {} +
  echo "  ✔ Installed for code-server"
  installed=1
fi

if command -v code >/dev/null 2>&1; then
  echo "Installing booth-shutdown extension for VS Code..."
  cli_bin="$(cli_bin_for_install code)"
  cli_opts=()
  if [[ "${EUID}" -eq 0 ]]; then
    vscode_root_data="/tmp/vscode-root-user-data"
    mkdir -p "$vscode_root_data"
    cli_opts=(--no-sandbox --user-data-dir "$vscode_root_data")
  fi
  "$cli_bin" "${cli_opts[@]}" --install-extension "$VSIX_PATH" --extensions-dir "$VSCODE_EXTENSION_DIR" --force
  find "$VSCODE_EXTENSION_DIR" -type d -exec chmod a+w {} +
  echo "  ✔ Installed for VS Code"
  installed=1
fi

rm -f "$VSIX_PATH"

if (( installed == 0 )); then
  echo "⚠ Neither VS Code nor code-server found; skipping booth-shutdown extension." >&2
fi

#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# booth-message-code-extension--setup.sh
#
# Installs a bundled code-server extension that:
#   - Watches .booth/.tmp/messages/ for incoming message files
#   - Shows VS Code notification dialogs (yes/no or text input)
#   - Writes response files back for the host CLI to read
#
# Follows the same pattern as booth-shutdown-code-extension--setup.sh.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/libs/code-extension-source.sh"

EXT_NAME="booth-message"
EXT_PUBLISHER="codingbooth"
EXT_VERSION="1.0.0"

build_vsix() {
  local tmp
  tmp=$(mktemp -d)

  # Extension source files
  mkdir -p "$tmp/extension"

  cat > "$tmp/extension/package.json" <<'JSON'
{
  "name": "booth-message",
  "displayName": "CodingBooth: Messages",
  "description": "Receive and respond to messages from the host in CodingBooth",
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
        "command": "codingbooth.showMessages",
        "title": "CodingBooth: Show Pending Messages"
      }
    ]
  }
}
JSON

  cat > "$tmp/extension/extension.js" <<'EXTJS'
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");

const MSG_DIR = "/home/coder/code/.booth/.tmp/messages";
const POLL_INTERVAL = 2000; // 2 seconds

// Track messages we've already shown to avoid duplicates
const shownMessages = new Set();

function activate(context) {
  // Start polling for new messages
  const timer = setInterval(() => pollMessages(), POLL_INTERVAL);
  context.subscriptions.push({ dispose: () => clearInterval(timer) });

  // Register manual command
  context.subscriptions.push(
    vscode.commands.registerCommand("codingbooth.showMessages", () => {
      pollMessages();
    })
  );

  // Initial poll
  setTimeout(() => pollMessages(), 1000);
}

function pollMessages() {
  let entries;
  try {
    entries = fs.readdirSync(MSG_DIR);
  } catch (_e) {
    return; // Directory doesn't exist yet
  }

  for (const file of entries) {
    if (!file.endsWith(".msg.json")) continue;

    const msgId = file.replace(".msg.json", "");

    // Skip if already shown or already responded
    if (shownMessages.has(msgId)) continue;
    const respFile = path.join(MSG_DIR, msgId + ".response.json");
    if (fs.existsSync(respFile)) continue;

    // Check expiry
    const msgPath = path.join(MSG_DIR, file);
    let msg;
    try {
      msg = JSON.parse(fs.readFileSync(msgPath, "utf8"));
    } catch (_e) {
      continue;
    }

    if (msg.expires) {
      const expiresAt = new Date(msg.expires);
      if (Date.now() > expiresAt.getTime()) {
        writeResponse(msgId, "timeout");
        continue;
      }
    }

    // Mark as shown and display
    shownMessages.add(msgId);
    showMessage(msg);
  }
}

async function showMessage(msg) {
  let answer;

  if (msg.type === "text") {
    const input = await vscode.window.showInputBox({
      title: msg.title,
      prompt: msg.body,
      placeHolder: "Type your response...",
      ignoreFocusOut: true
    });
    answer = input !== undefined ? input : "cancelled";
  } else {
    // yes-no
    const choice = await vscode.window.showInformationMessage(
      msg.body,
      { modal: true, detail: msg.title },
      "Yes",
      "No"
    );
    if (choice === "Yes") {
      answer = "yes";
    } else if (choice === "No") {
      answer = "no";
    } else {
      answer = "cancelled";
    }
  }

  writeResponse(msg.id, answer);
}

function writeResponse(msgId, answer) {
  const response = {
    id: msgId,
    answer: answer,
    answered: new Date().toISOString()
  };
  const respPath = path.join(MSG_DIR, msgId + ".response.json");
  try {
    fs.writeFileSync(respPath, JSON.stringify(response, null, 2));
  } catch (e) {
    vscode.window.showErrorMessage("Failed to write message response: " + e.message);
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
EXTJS

  # VSIX manifest (required by VS Code / code-server)
  cat > "$tmp/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="${EXT_NAME}" Version="${EXT_VERSION}" Publisher="${EXT_PUBLISHER}" />
    <DisplayName>CodingBooth: Messages</DisplayName>
    <Description xml:space="preserve">Receive and respond to messages from the host in CodingBooth</Description>
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
    echo "⚠️  QEMU detected — deferring booth-message extension install to first launch."
    installed=1   # not an error
  else
    echo "Installing booth-message extension for code-server..."
    cli_bin="$(cli_bin_for_install code-server)"
    "$cli_bin" --install-extension "$VSIX_PATH" --extensions-dir "$CODESERVER_EXTENSION_DIR" --force
    find "$CODESERVER_EXTENSION_DIR" -type d -exec chmod a+w {} +
    echo "  ✔ Installed for code-server"
    installed=1
  fi
fi

rm -f "$VSIX_PATH"

if (( installed == 0 )); then
  echo "⚠ code-server not found; skipping booth-message extension." >&2
fi

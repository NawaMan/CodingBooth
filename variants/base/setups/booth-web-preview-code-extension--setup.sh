#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Bundled preview extension and same-origin browser controls for the code-server
# variant. No marketplace access or npm build is needed.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/libs/code-extension-source.sh"
if ! command -v code-server >/dev/null 2>&1; then
  source "$SCRIPT_DIR/libs/skip-setup.sh"
  skip_setup "$(basename "$0")" "code-server not installed"
fi

DEST="${CB_WEB_PREVIEW_DIR:-/usr/local/share/booth-web-preview}"
mkdir -p "$DEST" "$CODESERVER_EXTENSION_DIR"
cp -R "$SCRIPT_DIR/booth-web-preview/." "$DEST/"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/extension"
cp "$DEST/package.json" "$DEST/extension.js" "$DEST/bridge.js" "$tmp/extension/"
cp -R "$DEST/media" "$tmp/extension/"
cat >"$tmp/extension.vsixmanifest" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="booth-web-preview" Version="1.0.0" Publisher="codingbooth" />
    <DisplayName>CodingBooth: Web Preview</DisplayName>
    <Description xml:space="preserve">Preview booth web servers in editor tabs.</Description>
    <Tags>preview,web,codingbooth</Tags><Categories>Other</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.70.0" /></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code" /></Installation>
  <Dependencies />
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" /></Assets>
</PackageManifest>
XML
cat >"$tmp/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json" />
  <Default Extension="js" ContentType="application/javascript" />
  <Default Extension="html" ContentType="text/html" />
  <Default Extension="css" ContentType="text/css" />
  <Default Extension="vsixmanifest" ContentType="text/xml" />
</Types>
XML
(cd "$tmp" && zip -qr "$DEST/extension.vsix" .)

if is_qemu; then
  # Keep the VSIX for the native runtime rather than silently omitting the
  # extension from cross-built images. The shared extension directory is writable.
  cat >/usr/share/startup.d/65-cb-web-preview--startup.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
EXT_DIR=/usr/local/share/code-server/extensions
if [[ ! -f "$EXT_DIR/codingbooth.booth-web-preview-1.0.0/package.json" ]]; then
  code-server --install-extension /usr/local/share/booth-web-preview/extension.vsix \
    --extensions-dir "$EXT_DIR" --force
fi
SH
  chmod +x /usr/share/startup.d/65-cb-web-preview--startup.sh
else
  "$(cli_bin_for_install code-server)" --install-extension "$DEST/extension.vsix" \
    --extensions-dir "$CODESERVER_EXTENSION_DIR" --force
fi
find "$CODESERVER_EXTENSION_DIR" -type d -exec chmod a+w {} +
echo "✅ CodingBooth: Web Preview 1.0.0 installed."
echo "ℹ️ In the code-server variant, click Web Preview and enter http://booth:3000/."

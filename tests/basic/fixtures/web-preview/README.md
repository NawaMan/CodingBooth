# Code-server web preview fixture

From this directory run `../../../../codingbooth --variant codeserver` using a
local build and matching code-server image. Two servers start inside the booth,
on ports 8080 and 8081; neither needs a host port mapping.

Click **Web Preview** in code-server's status bar and enter `8080`. Open another
preview with `8081`. Drag the editor tabs into groups to view both beside code.
Each server demonstrates root-relative CSS/JavaScript/API URLs, redirects,
WebSockets, links, and SPA navigation. Use **Developer: Reload Window** in the
Command Palette to save the editor workspace and restore the previews.

Enter `example.com` to open an external HTTPS page, or `python async examples`
to search Google. Search tabs keep the original query when duplicated or
restored. External sites may block embedding; use **Open in browser** if needed.
An HTTPS booth cannot embed an HTTP page directly.

The non-interactive proxy checks are in `tests/basic/test027--codeserver-web-preview.sh`.
The browser check additionally needs the `playwright` Node package and Chromium;
set `CB_PLAYWRIGHT_MODULE` to the package path and `CB_CHROMIUM_PATH` to the browser
executable when these are not installed in their usual locations.
External-site and Google responses are intercepted by the browser test so it
checks cross-origin embedding and query handling without depending on public
sites' availability or changing framing policies.

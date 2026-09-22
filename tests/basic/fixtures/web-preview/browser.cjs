// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
const assert = require("node:assert/strict");
const { chromium } = require(process.env.CB_PLAYWRIGHT_MODULE || "playwright");
const base = process.argv[2];
const password = process.env.CB_PREVIEW_TEST_PASSWORD;

async function until(fn, description, timeout = 30000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const value = await fn();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out: ${description}`);
}

(async () => {
  // This fixture uses Booth's self-signed localhost certificate. Playwright's
  // context option alone does not cover Chromium service-worker registration.
  const browser = await chromium.launch({ executablePath: process.env.CB_CHROMIUM_PATH || undefined,
    args: ["--ignore-certificate-errors"] });
  let page;
  const errors = [];
  try {
    const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1600, height: 1000 } });
    context.setDefaultTimeout(15000);
    // Deterministic external origins exercise real cross-origin frames and
    // CSP without making the regression suite depend on Google's availability.
    let externalLoads = 0;
    await context.route("https://example.com/**", route => {
      externalLoads++;
      return route.fulfill({ contentType: "text/html", body: '<h1>External page</h1><a href="/next">External link</a>' });
    });
    await context.route("https://www.google.com/search?**", route => route.fulfill({
      contentType: "text/html", body: '<h1>Search results fixture</h1>'
    }));
    page = await context.newPage();
    page.on("console", message => { if (message.type() === "error") errors.push(message.text().slice(0, 400)); });
    page.on("requestfailed", request => errors.push(`${request.url()}: ${request.failure()?.errorText}`));
    page.on("pageerror", error => console.error("Page:", error.message));
    if (password) {
      const response = await context.request.get(base + "/proxy/8080/api/id", { maxRedirects: 0 });
      assert.ok([401, 403].includes(response.status()) || (response.status() === 302 && response.headers().location.includes("login")), "Anonymous API must not reach the application");
      await page.goto(base + "/login");
      const anonymousSocket = await page.evaluate(url => new Promise((resolve, reject) => {
        const socket = new WebSocket(url.replace(/^http/, "ws") + "/proxy/8080/ws");
        const timer = setTimeout(() => { socket.close(); reject(new Error("Anonymous socket did not finish its handshake")); }, 5000);
        socket.onopen = () => { clearTimeout(timer); socket.close(); resolve(true); };
        socket.onerror = () => { clearTimeout(timer); resolve(false); };
      }), base);
      assert.equal(anonymousSocket, false, "Anonymous WebSocket must be denied");
      await page.locator('input[name="password"]').fill(password);
      await page.locator('button[type="submit"], input[type="submit"]').click();
    }
    await page.goto(base + "/?_booth_inner=1&folder=/home/coder/code");
    async function open(address, matches = f => f.url().includes(`/proxy/${address}/`)) {
      await page.getByText("Web Preview", { exact: true }).click({ timeout: 60000 });
      await page.locator(".quick-input-widget input").fill(String(address));
      await page.keyboard.press("Enter");
      try { return await until(() => page.frames().find(matches), `preview ${address}`); }
      catch (error) {
        console.error("Frames:", page.frames().map(f => f.url()));
        console.error("Editor:", (await page.locator("body").innerText()).slice(-2500));
        console.error("Browser:", errors);
        throw error;
      }
    }
    function controls(app) { return app.parentFrame(); }
    async function verifyApp(app, port) {
      await app.getByRole("heading", { name: `Server ${port}`, exact: true }).waitFor();
      await until(async () => (await app.locator("#api").textContent()) === `api-${port}`, "rewritten API request");
      await until(async () => (await app.locator("#socket").textContent()) === `socket-${port}`, "WebSocket upgrade");
      assert.equal(await app.locator("body").evaluate(el => getComputedStyle(el).backgroundColor), "rgb(232, 245, 233)", "Rewritten CSS must load");
    }
    const first = await open(8080);
    await verifyApp(first, 8080);
    const ui = controls(first);
    await ui.locator("#address").fill("http://booth:8080/redirect");
    await ui.locator("#address").press("Enter");
    await until(async () => (await ui.locator("#address").inputValue()).endsWith("/next"), "redirect address");
    await ui.getByRole("button", { name: "Back", exact: true }).click();
    await until(async () => (await first.locator("#path").textContent()) === "/", "back skips redirect");
    await first.getByText("Next page", { exact: true }).click();
    await until(async () => (await ui.locator("#address").inputValue()).endsWith("/next"), "address after link");
    await ui.getByRole("button", { name: "Back", exact: true }).click();
    await until(async () => (await first.locator("#path").textContent()) === "/", "back navigation");
    await ui.getByRole("button", { name: "Forward", exact: true }).click();
    await until(async () => (await first.locator("#path").textContent()) === "/next", "forward navigation");
    await first.getByText("SPA navigation", { exact: true }).click();
    await until(async () => (await ui.locator("#address").inputValue()).endsWith("/spa?ok=1#section"), "SPA address tracking");
    await ui.getByRole("button", { name: "Reload", exact: true }).click();
    await until(async () => (await first.locator("#path").textContent()) === "/spa", "reload current SPA address");
    console.log("PASS: navigation, redirect history and SPA reload");
    const second = await open(8081);
    await verifyApp(second, 8081);
    await controls(second).locator("#address").fill("8081/?next=one%26two%2Bthree%23four#part");
    await controls(second).locator("#address").press("Enter");
    await until(() => second.url().includes("next=one%26two"), "encoded booth query");
    const popupPromise = context.waitForEvent("page", { timeout: 15000 });
    await controls(second).getByRole("button", { name: "Open in browser", exact: true }).click();
    const popup = await popupPromise;
    await popup.waitForURL(/\/proxy\/8081\//);
    await popup.getByRole("heading", { name: "Server 8081", exact: true }).waitFor();
    assert.equal(new URL(popup.url()).searchParams.get("next"), "one&two+three#four");
    await popup.close();
    await controls(second).locator("#address").fill("8081");
    await controls(second).locator("#address").press("Enter");
    await until(() => second.url().endsWith("/proxy/8081/"), "reset second address");
    // Each editor gets a separate frame and URI; changing one cannot reroute the other.
    assert.notEqual(first, second);
    assert.equal(await first.locator("#api").textContent(), "api-8080");
    await page.getByRole("tab", { name: /Web · 8080/ }).click();
    await ui.getByRole("button", { name: "New preview tab", exact: true }).click();
    await until(() => page.getByRole("tab", { name: /Web · 8080/ }).count().then(n => n === 2), "duplicate preview tab");
    // Close only the duplicate. VS Code should serialize the other two tabs.
    await page.getByRole("tab", { name: /Web · 8080/ }).last().getByRole("button", { name: /Close/ }).click();
    await page.getByRole("tab", { name: /Web · 8081/ }).waitFor();
    console.log("PASS: independent tabs, duplication and Open in browser");
    const external = await open("example.com", f => f.url() === "https://example.com/");
    await external.getByRole("heading", { name: "External page" }).waitFor();
    const externalUI = controls(external);
    assert.equal(await externalUI.locator("#address").inputValue(), "https://example.com/");
    const loads = externalLoads;
    await externalUI.getByRole("button", { name: "Reload", exact: true }).click();
    await until(() => externalLoads > loads, "external reload");
    // Cross-origin links cannot update our address bar; retain the entered URL.
    await external.getByText("External link", { exact: true }).click();
    await external.waitForURL("https://example.com/next");
    assert.equal(await externalUI.locator("#address").inputValue(), "https://example.com/");
    await externalUI.locator("#address").fill("http://example.com/");
    await externalUI.locator("#address").press("Enter");
    await until(async () => (await externalUI.locator("#external-hint").textContent()).includes("HTTP pages cannot be embedded"), "HTTP guidance in HTTPS booth");
    await externalUI.locator("#address").fill("8080");
    await externalUI.locator("#address").press("Enter");
    await verifyApp(external, 8080);
    assert.equal(await externalUI.locator("#external-hint").isVisible(), false);
    await externalUI.getByRole("button", { name: "Back", exact: true }).click();
    await externalUI.getByRole("button", { name: "Back", exact: true }).click();
    await external.getByRole("heading", { name: "External page" }).waitFor();
    const query = "cats & dogs + café #1";
    const search = await open(query, f => f.url().startsWith("https://www.google.com/search?"));
    await search.getByRole("heading", { name: "Search results fixture" }).waitFor();
    const searchUI = controls(search);
    assert.equal(new URL(search.url()).searchParams.get("q"), query);
    assert.equal(new URL(search.url()).searchParams.get("igu"), "1");
    assert.equal(await searchUI.locator("#address").inputValue(), query);
    const searchPopupPromise = context.waitForEvent("page");
    await searchUI.getByRole("button", { name: "Open in browser", exact: true }).click();
    // VS Code asks before opening an external domain outside the editor.
    await page.getByRole("button", { name: "Open", exact: true }).click();
    const searchPopup = await searchPopupPromise;
    await searchPopup.waitForURL("https://www.google.com/search?**");
    assert.equal(new URL(searchPopup.url()).searchParams.get("q"), query);
    await searchPopup.close();
    await searchUI.getByRole("button", { name: "New preview tab", exact: true }).click();
    await until(() => page.getByRole("tab", { name: /Search: cats/ }).count().then(n => n === 2), "duplicate search");
    await page.getByRole("tab", { name: /Search: cats/ }).last().getByRole("button", { name: /Close/ }).click();
    console.log("PASS: external addresses, reload, switching to booth servers, Google query encoding and search duplication");
    // Use the editor's reload command so VS Code flushes its workspace storage
    // before the navigation. An immediate browser-level reload can interrupt
    // VS Code's delayed persistence of newly opened tabs (including file tabs).
    await page.keyboard.press("F1");
    await page.locator(".quick-input-widget input").fill(">Developer: Reload Window");
    await page.getByRole("option", { name: /Developer: Reload Window/ }).click();
    await page.waitForLoadState("domcontentloaded");
    // VS Code restores hidden webviews lazily, when their tab is activated.
    await page.getByRole("tab", { name: /Web · 8080/ }).click({ timeout: 60000 });
    await until(() => page.frames().find(f => f.url().includes("/proxy/8080/spa?ok=1#section")), "restored first address", 60000);
    await page.getByRole("tab", { name: /Web · 8081/ }).click();
    const restored = await until(() => {
      const apps = page.frames().filter(f => /\/proxy\/(8080|8081)\//.test(f.url()));
      return apps.some(f => f.url().includes("/proxy/8080/spa?ok=1#section")) && apps.some(f => f.url().includes("/proxy/8081/")) && apps;
    }, "restored previews", 60000);
    assert.equal(restored.length, 2);
    for (const app of restored) await verifyApp(app, app.url().includes("/8080/") ? 8080 : 8081);
    await page.getByRole("tab", { name: /Web · example.com/ }).click();
    const restoredExternal = await until(() => page.frames().find(f => f.url() === "https://example.com/"), "restored external address");
    await restoredExternal.getByRole("heading", { name: "External page" }).waitFor();
    await page.getByRole("tab", { name: /Search: cats/ }).click();
    const restoredSearch = await until(() => page.frames().find(f => f.url().startsWith("https://www.google.com/search?")), "restored search");
    assert.equal(await controls(restoredSearch).locator("#address").inputValue(), query);
    assert.equal(new URL(restoredSearch.url()).searchParams.get("q"), query);
    await restoredSearch.getByRole("heading", { name: "Search results fixture" }).waitFor();
    console.log("PASS: external tabs and search text restore after editor reload");
    console.log("PASS: rewritten assets/API, WebSockets, independent tabs, navigation, duplication and restored addresses");
    if (process.env.CB_PREVIEW_SCREENSHOT) await page.screenshot({ path: process.env.CB_PREVIEW_SCREENSHOT });
  } catch (error) {
    if (page) {
      console.error("Browser errors:", errors);
      console.error("Remaining frames:", page.frames().map(frame => frame.url()));
      console.error("Editor state:", (await page.locator("body").innerText()).slice(-1800));
      await page.screenshot({ path: "/tmp/cb-web-preview-failure.png" });
    }
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });

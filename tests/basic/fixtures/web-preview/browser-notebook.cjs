// Copyright 2025-2026 Nawa Manusitthipol. Licensed under Apache-2.0.
// Notebook counterpart of browser.cjs: opens Web Preview from the JupyterLab
// Launcher and drives the controls in their JupyterLab tab.
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
  const browser = await chromium.launch({ executablePath: process.env.CB_CHROMIUM_PATH || undefined,
    args: ["--ignore-certificate-errors"] });
  let page;
  try {
    // A light OS preference, so dark controls below can only come from JupyterLab.
    const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1600, height: 1000 }, colorScheme: "light" });
    context.setDefaultTimeout(15000);
    page = await context.newPage();
    page.on("pageerror", error => console.error("Page:", error.message));

    await page.goto(base + "/login");
    const anonymousSocket = await page.evaluate(url => new Promise(resolve => {
      const socket = new WebSocket(url.replace(/^http/, "ws") + "/proxy/8080/ws");
      const timer = setTimeout(() => { socket.close(); resolve(true); }, 5000);
      socket.onopen = () => { clearTimeout(timer); socket.close(); resolve(true); };
      socket.onerror = () => { clearTimeout(timer); resolve(false); };
    }), base);
    assert.equal(anonymousSocket, false, "Anonymous WebSocket must be denied");
    // Jupyter's login page also carries a "set a new password" form; use the first.
    const login = page.locator("form").filter({ has: page.locator('input[name="password"]') }).first();
    await login.locator('input[name="password"]').fill(password);
    await login.locator('button[type="submit"], input[type="submit"]').click();
    await page.waitForURL(url => !url.pathname.startsWith("/login"));

    await page.goto(base + "/lab");
    // A fresh Launcher, whatever layout JupyterLab restored.
    await until(() => page.evaluate(() => !!(window.jupyterapp && window.jupyterapp.commands.hasCommand("launcher:create"))), "JupyterLab app", 60000);
    await page.evaluate(() => window.jupyterapp.restored.then(() => window.jupyterapp.commands.execute("launcher:create")));
    // Both tiles carry their icon, and it actually loads.
    for (const title of ["Web Preview", "Markdown Viewer"]) {
      const icon = page.locator(`.jp-LauncherCard[title="${title}"] .jp-LauncherCard-icon`).first();
      await icon.waitFor({ timeout: 60000 });
      const drawn = await icon.evaluate(el => new Promise(resolve => {
        const match = getComputedStyle(el).backgroundImage.match(/url\("?([^")]+)"?\)/);
        if (!match) return resolve(0);
        const image = new Image();
        image.onload = () => resolve(image.naturalWidth);
        image.onerror = () => resolve(0);
        image.src = match[1];
      }));
      assert.ok(drawn > 0, `${title} tile shows its icon`);
    }
    // Optional: a picture of the Launcher, for checking the icons by eye.
    if (process.env.CB_PREVIEW_SCREENSHOT) {
      await page.locator(".jp-LauncherCard[title=\"Web Preview\"]").first().scrollIntoViewIfNeeded();
      await page.screenshot({ path: process.env.CB_PREVIEW_SCREENSHOT });
    }
    await page.locator(".jp-LauncherCard", { hasText: "Web Preview" }).first().click({ timeout: 60000 });
    const ui = await until(() => page.frames().find(f => f.url().includes("/booth-preview/index.html")), "controls tab");
    await ui.locator("#address").waitFor();
    assert.equal(await ui.locator("#address").inputValue(), "http://booth:", "An empty preview leaves only the port to type");
    assert.equal(await ui.locator("#new").isVisible(), true, "JupyterLab can open more preview tabs");

    // JupyterLab defaults to dark, and the controls follow it — live, too.
    const controlsBackground = () => ui.locator("body").evaluate(el => getComputedStyle(el).backgroundColor);
    assert.equal(await page.locator("body").getAttribute("data-jp-theme-light"), "false", "JupyterLab starts dark");
    await until(async () => (await controlsBackground()) === "rgb(32, 33, 36)", "dark controls under JupyterLab Dark");
    await page.evaluate(() => window.jupyterapp.commands.execute("apputils:change-theme", { theme: "JupyterLab Light" }));
    await until(async () => (await controlsBackground()) === "rgb(243, 243, 243)", "controls follow a switch to JupyterLab Light");
    await page.evaluate(() => window.jupyterapp.commands.execute("apputils:change-theme", { theme: "JupyterLab Dark" }));
    await until(async () => (await controlsBackground()) === "rgb(32, 33, 36)", "controls follow a switch back to JupyterLab Dark");

    await ui.locator("#address").fill("8080");
    await ui.locator("#address").press("Enter");
    const app = await until(() => page.frames().find(f => f.url().includes("/proxy/8080/")), "preview 8080");
    await app.getByRole("heading", { name: "Server 8080", exact: true }).waitFor();
    await until(async () => (await app.locator("#api").textContent()) === "api-8080", "rewritten API request");
    await until(async () => (await app.locator("#socket").textContent()) === "socket-8080", "WebSocket upgrade");
    assert.equal(await app.locator("body").evaluate(el => getComputedStyle(el).backgroundColor), "rgb(232, 245, 233)", "Rewritten CSS must load");

    await ui.locator("#address").fill("http://booth:8080/redirect");
    await ui.locator("#address").press("Enter");
    await until(async () => (await ui.locator("#address").inputValue()) === "http://booth:8080/next", "redirect address");
    await app.locator("#spa").click();
    await until(async () => (await ui.locator("#address").inputValue()) === "http://booth:8080/spa?ok=1#section", "SPA address");

    // Open in browser: a booth server opens at its proxied address.
    const [popup] = await Promise.all([context.waitForEvent("page"), ui.locator("#external").click()]);
    await until(() => popup.url().includes("/proxy/8080/spa?ok=1"), "external page address");
    await popup.close();

    // Reloading the controls keeps the address.
    await ui.evaluate(() => location.reload());
    const reloaded = await until(() => page.frames().find(f => f.url().includes("/booth-preview/index.html")), "reloaded controls");
    await until(async () => (await reloaded.locator("#address").inputValue().catch(() => "")) === "http://booth:8080/spa?ok=1#section", "restored address");

    // Tabs are named after what they show.
    const tabs = () => page.locator("#jp-main-dock-panel .lm-TabBar-tab .lm-TabBar-tabLabel").allTextContents();
    await until(async () => (await tabs()).includes("Web · 8080/spa?ok=1#section"), "tab titled after its page");

    // ＋ opens a second, independent preview tab at the same address.
    const controlsFrames = () => page.frames().filter(f => f.url().includes("/booth-preview/index.html"));
    await reloaded.locator("#new").click();
    const second = await until(() => controlsFrames().find(f => f !== reloaded), "second preview tab");
    await until(async () => (await second.locator("#address").inputValue().catch(() => "")) === "http://booth:8080/spa?ok=1#section", "second tab starts at the same address");
    await second.locator("#address").fill("8081");
    await second.locator("#address").press("Enter");
    const app8081 = await until(() => page.frames().find(f => f.url().includes("/proxy/8081/")), "preview 8081");
    await app8081.getByRole("heading", { name: "Server 8081", exact: true }).waitFor();
    await until(async () => (await tabs()).includes("Web · 8081"), "second tab title");
    assert.equal(await reloaded.locator("#address").inputValue(), "http://booth:8080/spa?ok=1#section", "the first tab keeps its own address");

    // A JupyterLab reload restores both tabs where they were.
    await page.waitForTimeout(1500);  // let JupyterLab persist its layout
    await page.reload();
    const addresses = async () => Promise.all(controlsFrames().map(f => f.locator("#address").inputValue().catch(() => "")));
    try {
      await until(async () => {
        const values = await addresses();
        return values.includes("http://booth:8080/spa?ok=1#section") && values.includes("http://booth:8081/");
      }, "both tabs restored", 60000);
    } catch (error) {
      console.error("Restored addresses:", await addresses(), "Tabs:", await tabs());
      throw error;
    }
    // The editor's own ports are refused.
    const last = await until(async () => {
      for (const frame of controlsFrames()) if (await frame.locator("#address").isVisible().catch(() => false)) return frame;
    }, "visible preview tab");
    await last.locator("#address").fill("18888");
    await last.locator("#address").press("Enter");
    await until(async () => (await last.locator("#error").textContent()).includes("reserved"), "reserved port");

    // 📄 switches the tab to the Markdown viewer, starting it on demand.
    await last.locator("#markdown").click();
    await until(async () => (await last.locator("#address").inputValue()).startsWith("http://booth:8765/"), "Markdown address");
    const rendered = async () => {
      for (const frame of page.frames().filter(f => f.url().includes("/proxy/8765/"))) {
        if ((await frame.locator("body").innerText().catch(() => "")).includes("Rendered by viewmd for the notebook preview.")) return frame;
      }
    };
    await until(rendered, "README rendered by viewmd", 45000);

    // The Markdown Viewer tile opens its own tab on viewmd.
    const before = controlsFrames().length;
    await page.evaluate(() => window.jupyterapp.commands.execute("launcher:create"));
    await page.locator(".jp-LauncherCard", { hasText: "Markdown Viewer" }).first().click();
    await until(() => controlsFrames().length > before, "Markdown Viewer tab");
    await until(async () => (await tabs()).filter(label => label.startsWith("Web · 8765")).length >= 2, "Markdown Viewer tab titled after viewmd");


    // A JupyterLab whose API has changed underneath the controls: ＋, titles and
    // saved addresses may stop, but previews must still load and track.
    await page.evaluate(() => {
      const broken = () => { throw new Error("JupyterLab API changed"); };
      window.jupyterapp.shell.widgets = broken;
      window.jupyterapp.commands.execute = broken;
    });
    const survivor = await until(async () => {
      for (const frame of controlsFrames()) if (await frame.locator("#address").isVisible().catch(() => false)) return frame;
    }, "visible preview tab after the API change");
    await survivor.locator("#address").fill("8081/after-api-change");
    await survivor.locator("#address").press("Enter");
    await until(async () => (await survivor.locator("#address").inputValue()) === "http://booth:8081/after-api-change", "address still tracks");
    const loaded = await until(() => page.frames().find(f => f.url().includes("/proxy/8081/after-api-change")), "preview still loads");
    await loaded.getByRole("heading", { name: "Server 8081", exact: true }).waitFor();
    await survivor.locator("#new").click();
    assert.equal(await survivor.locator("#error").isVisible(), false, "A failing JupyterLab call must not surface as a navigation error");

    console.log("PASS: Launcher tiles and icons, booth preview, redirects, SPA navigation, open in browser, reload, theme, multiple tabs, titles, restoration and the Markdown viewer in JupyterLab");
  } catch (error) {
    if (page) console.error("Frames:", page.frames().map(f => f.url()));
    console.error(error);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();

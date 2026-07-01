// Visit a real web page with headless Chromium and save a screenshot.
//
//   node screenshot.js [url] [outfile]
//
// Defaults to Hacker News (a content-rich, bot-friendly programming feed).
// Note: some sites — including reddit.com — block headless browsers outright,
// so they return a "blocked by network security" page instead of content.
// The browser is the one pre-baked into the booth image, so this runs without
// downloading anything.
const { chromium } = require('playwright');

const url = process.argv[2] || 'https://news.ycombinator.com/';
const outFile = process.argv[3] || 'screenshot.png';

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 1400 } });

  console.log(`Visiting ${url} ...`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // Give late-loading content a moment to settle.
  await page.waitForTimeout(3000);

  const title = await page.title();
  console.log(`Page title: ${title}`);

  await page.screenshot({ path: outFile });
  console.log(`Screenshot saved to ${outFile}`);

  await browser.close();
})().catch((err) => {
  console.error('Screenshot failed:', err.message);
  process.exit(1);
});

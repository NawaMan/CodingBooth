// Playwright, the JavaScript way. Open a real page, save a screenshot, and print
// "TITLE|SUM" — TITLE is the live page's title, SUM is 1+..+10 run inside the browser.
const { chromium } = require('playwright');

const url = process.env.PAGE_URL || 'https://developer.mozilla.org/en-US/docs/Web/JavaScript';
const shot = process.env.SHOT_PATH || 'javascript.png';

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(3000);
  const sum = await page.evaluate(() => {
    let s = 0;
    for (let i = 1; i <= 10; i++) s += i;
    return s;
  });
  const title = await page.title();
  await page.screenshot({ path: shot });
  console.log(`${title}|${sum}`);
  await browser.close();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

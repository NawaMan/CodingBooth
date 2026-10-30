import { test, expect } from '@playwright/test';

// The app is served over HTTP by served/serve.mjs (started by playwright.served.config.ts),
// the way a CI job tests a real web app: start it, then drive it in a headless browser.
test('counter page served over HTTP', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle('Playwright counter');
  await expect(page.locator('#count')).toHaveText('0');

  await page.click('#add');
  await page.click('#add');
  await expect(page.locator('#count')).toHaveText('2');

  const shot = await page.screenshot();
  expect(shot.length).toBeGreaterThan(1000);
});

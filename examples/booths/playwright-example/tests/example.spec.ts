import { test, expect } from '@playwright/test';

test('basic browser test', async ({ page }) => {
  // Navigate to a data URL to avoid network dependency
  await page.goto('data:text/html,<h1>Hello from Playwright!</h1><p>Sum of 1..10 = 55</p>');

  // Verify the page title element
  const heading = page.locator('h1');
  await expect(heading).toHaveText('Hello from Playwright!');

  // Verify computed content
  const paragraph = page.locator('p');
  await expect(paragraph).toContainText('55');
});

test('javascript evaluation', async ({ page }) => {
  await page.goto('about:blank');

  // Evaluate JavaScript in the browser
  const sum = await page.evaluate(() => {
    let s = 0;
    for (let i = 1; i <= 10; i++) s += i;
    return s;
  });

  expect(sum).toBe(55);
});

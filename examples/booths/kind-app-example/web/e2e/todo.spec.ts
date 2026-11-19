import { test, expect } from '@playwright/test';

test.describe('TODO App', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('h1');
  });

  test('displays the app title', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('TODO App');
  });

  test('can add a new task', async ({ page }) => {
    const taskTitle = `Test Task ${Date.now()}`;

    await page.fill('#title', taskTitle);
    await page.fill('#description', 'Test Description');
    await page.click('button[type="submit"]');

    await expect(page.locator(`text=${taskTitle}`)).toBeVisible();
  });

  test('can mark task as complete', async ({ page }) => {
    // First create a task
    const taskTitle = `Complete Task ${Date.now()}`;
    await page.fill('#title', taskTitle);
    await page.click('button[type="submit"]');
    await expect(page.locator(`text=${taskTitle}`)).toBeVisible();

    // Find and click the checkbox
    const taskItem = page.locator(`text=${taskTitle}`).locator('..').locator('..');
    const checkbox = taskItem.locator('input[type="checkbox"]');
    await checkbox.click();

    // Verify the task is marked as complete (has line-through)
    await expect(taskItem.locator('h3')).toHaveClass(/line-through/);
  });

  test('can edit a task', async ({ page }) => {
    // First create a task
    const taskTitle = `Edit Task ${Date.now()}`;
    await page.fill('#title', taskTitle);
    await page.click('button[type="submit"]');
    await expect(page.locator(`text=${taskTitle}`)).toBeVisible();

    // Click edit button
    const taskItem = page.locator(`text=${taskTitle}`).locator('..').locator('..');
    await taskItem.locator('button:has-text("Edit")').click();

    // Edit the title
    const updatedTitle = `Updated ${taskTitle}`;
    await page.locator('input[type="text"]').first().fill(updatedTitle);
    await page.click('button:has-text("Save")');

    // Verify the update
    await expect(page.locator(`text=${updatedTitle}`)).toBeVisible();
  });

  test('can delete a task', async ({ page }) => {
    // First create a task
    const taskTitle = `Delete Task ${Date.now()}`;
    await page.fill('#title', taskTitle);
    await page.click('button[type="submit"]');
    await expect(page.locator(`text=${taskTitle}`)).toBeVisible();

    // Click delete button and confirm
    page.on('dialog', dialog => dialog.accept());
    const taskItem = page.locator(`text=${taskTitle}`).locator('..').locator('..');
    await taskItem.locator('button:has-text("Delete")').click();

    // Verify the task is gone
    await expect(page.locator(`text=${taskTitle}`)).not.toBeVisible();
  });

  test('can export tasks as CSV', async ({ page }) => {
    const downloadPromise = page.waitForEvent('download');
    await page.click('button:has-text("Export CSV")');
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toBe('tasks.csv');
  });

  test('can export tasks as JSON', async ({ page }) => {
    const downloadPromise = page.waitForEvent('download');
    await page.click('button:has-text("Export JSON")');
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toBe('tasks.json');
  });

  test('changes sync across tabs', async ({ browser }) => {
    // Open two tabs
    const context = await browser.newContext();
    const page1 = await context.newPage();
    const page2 = await context.newPage();

    await page1.goto('/');
    await page2.goto('/');

    await page1.waitForSelector('h1');
    await page2.waitForSelector('h1');

    // Create a task in tab 1
    const taskTitle = `Sync Task ${Date.now()}`;
    await page1.fill('#title', taskTitle);
    await page1.click('button[type="submit"]');

    // Verify it appears in tab 1
    await expect(page1.locator(`text=${taskTitle}`)).toBeVisible();

    // Verify it appears in tab 2 via WebSocket
    await expect(page2.locator(`text=${taskTitle}`)).toBeVisible({ timeout: 10000 });

    await context.close();
  });
});

import { test, expect } from '@playwright/test';

test('test', async ({ page }) => {
  //const browser = await chromium.launch();
  //const context = await browser.newContext();
  //const page = await context.newPage();
  await page.goto('http://127.0.0.1:8080/#/settings');
  await page.getByTitle('Streaming').click();
  await page.getByTitle('Configure server url').getByRole('img').click();
  await page.getByPlaceholder('Enter a streaming server url').click();
  await page.getByPlaceholder('Enter a streaming server url').press('Meta+a');
  await page.getByPlaceholder('Enter a streaming server url').fill('http://127.0.0.1:11470/');
  await page.getByText('Submit').click();
  await expect(page.getByText('Online')).toHaveText('Online');
});

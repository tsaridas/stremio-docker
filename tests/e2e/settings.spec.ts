import { test, expect, request } from '@playwright/test';

test('api', async ({ page }) => {
  // Create a context that will issue http requests.
  const context = await request.newContext({
    baseURL: 'http://127.0.0.1:11470',
  });
    // Delete a repository.
  const settings = await context.get(`/settings`, {});
  expect(settings.ok()).toBeTruthy();
  expect(settings.json());
  const settingsText = await settings.text();
  console.log(`Settings Request Result: ${settingsText}`);

  const network = await context.get(`/network-info`, {});
  expect(network.ok()).toBeTruthy();
  expect(network.json());
  const networkText = await network.text();
  console.log(`Network Request Result: ${networkText}`);
});

test('settings', async ({ page }) => {
  await page.goto('http://127.0.0.1:8080/#/settings');
  await page.getByTitle('Streaming').click();
  await page.getByTitle('Configure server url').getByRole('img').click();
  await page.getByPlaceholder('Enter a streaming server url').click();
  await page.getByPlaceholder('Enter a streaming server url').press('Meta+a');
  await page.getByPlaceholder('Enter a streaming server url').fill('http://127.0.0.1:11470/');
  await page.getByText('Submit').click();
  await expect(page.getByText('Online')).toHaveText('Online');
});

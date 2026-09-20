import { expect } from '@playwright/test';
import { streamingOnlineTimeoutMs, test } from './fixtures';

const username = process.env.AUTH_USERNAME || 'default_user';
const password = process.env.AUTH_PASSWORD || 'default_pass';

test.describe('Stremio API and Settings', () => {
  test('API endpoints return expected responses', async ({ browser, serverURL, auth }) => {
    console.log('Testing API endpoints with serverURL:', serverURL);
    const context = await browser.newContext({ baseURL: serverURL });

    if (auth) {
      await context.setExtraHTTPHeaders({
        'Authorization': `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`
      });
    }

    async function testEndpoint(path: string, expectedStatus = 200) {
      const response = await context.request.get(path);
      expect(response.status()).toBe(expectedStatus);
      expect(response.headers()['content-type']).toContain('application/json');
      const data = await response.json();
      expect(data).toBeTruthy();
      return data;
    }

    const settings = await testEndpoint('/settings');
    console.log('Settings:', JSON.stringify(settings, null, 2));

    const networkInfo = await testEndpoint('/network-info');
    console.log('Network Info:', JSON.stringify(networkInfo, null, 2));
  });

  test('User can configure streaming server URL', async ({ page, serverURL, webURL, auth }) => {
    console.log('Testing settings with serverURL:', serverURL, 'webURL:', webURL);
    if (auth) {
      await page.setExtraHTTPHeaders({
        'Authorization': 'Basic ' + Buffer.from(`${username}:${password}`).toString('base64')
      });
    }
    // Stremio normalizes streaming URLs with a trailing slash (see DEFAULT_STREAMING_SERVER_URL).
    const urlToAdd = serverURL.endsWith('/') ? serverURL : `${serverURL}/`;

    await page.goto(`${webURL}/#/settings`);

    await expect(page.getByTitle('Streaming')).toBeVisible({ timeout: 60_000 });
    await page.getByTitle('Streaming').click();

    // "Add URL" is a Stremio <div> Button, not a real <button>.
    await page.getByText('Add URL', { exact: true }).click();
    const urlInput = page.getByPlaceholder('Enter URL');
    await expect(urlInput).toBeVisible();
    await urlInput.click();
    // pressSequentially so React controlled state is updated before submit
    // (fill + Enter can race and call handleAddUrl with "").
    await urlInput.pressSequentially(urlToAdd, { delay: 15 });
    await expect(urlInput).toHaveValue(urlToAdd);
    // Do not getByRole('button') — Stremio Button renders as <div>.
    // Enter is handled by TextInput once state has the typed value.
    await urlInput.press('Enter');

    // Match with or without trailing slash in case core stores either form.
    const addedUrl = page.getByText(urlToAdd, { exact: true }).or(page.getByText(serverURL, { exact: true }));
    await expect(addedUrl.first()).toBeVisible({ timeout: 15_000 });
    await addedUrl.first().locator('..').getByRole('radio').click();

    await expect(page.getByText('Online')).toBeVisible({ timeout: streamingOnlineTimeoutMs });

    await expect(addedUrl.first()).toBeVisible();

    await page.reload();
    await expect(page.getByTitle('Streaming')).toBeVisible({ timeout: 60_000 });
    await page.getByTitle('Streaming').click();
    await expect(addedUrl.first()).toBeVisible();
  });
});

import { expect } from '@playwright/test';
import { test } from './fixtures';

test.describe('Stremio API and Settings', () => {
  test('API endpoints return expected responses', async ({ browser, serverURL }) => {
    console.log('serverURL:', serverURL);
    const context = await browser.newContext({ baseURL: serverURL });

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

  test('User can configure streaming server URL', async ({ page, serverURL, webURL }) => {
    console.log('serverURL:', serverURL);
    console.log('webURL:', webURL);
    await page.goto(`${webURL}/#/settings`);
    
    await page.getByTitle('Streaming').click();
    
    await page.getByTitle('Configure server url').getByRole('img').click();
    await page.getByPlaceholder('Enter a streaming server url').fill(serverURL);
    await page.getByText('Submit').click();
    
    await expect(page.getByText('Online')).toBeVisible({ timeout: 10000 });
    
    const serverUrlElement = page.getByText(serverURL);
    await expect(serverUrlElement).toBeVisible();
    
    await page.reload();
    await expect(serverUrlElement).toBeVisible();
  });
});

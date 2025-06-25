import { expect } from '@playwright/test';
import { test } from './fixtures';

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
    await page.goto(`${webURL}/#/settings`);
    
    await page.getByTitle('Streaming').click();
    
    await page.getByText('Add URL').click();
    await page.getByPlaceholder('Enter URL').click();
    await page.getByPlaceholder('Enter URL').fill(serverURL);
    await page.getByPlaceholder('Enter URL').press('Enter');
    await page.getByRole('radio').nth(2).click(); 

    await expect(page.getByText('Online')).toBeVisible({ timeout: 10000 });
    
    const serverUrlElement = page.getByText(serverURL);
    await expect(serverUrlElement).toBeVisible();
    
    await page.reload();
    await expect(serverUrlElement).toBeVisible();
  });
});

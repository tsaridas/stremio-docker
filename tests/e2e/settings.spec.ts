import { expect } from '@playwright/test';
import { test } from './fixtures';

test.describe('Stremio API and Settings', () => {
  test('API endpoints return expected responses', async ({ browser, serverURL }) => {
    console.log('Testing API endpoints with serverURL:', serverURL);
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
    console.log('Testing settings with serverURL:', serverURL, 'webURL:', webURL);
    await page.goto(`${webURL}/#/settings`);
    
    await page.getByTitle('Streaming').click();
    
    await page.getByText('Add URL').click();
    await page.getByPlaceholder('Enter URL').click();
    await page.getByPlaceholder('Enter URL').fill('http://stremio:11470');
    await page.locator('div').filter({ hasText: /^URLStatushttp:\/\/127\.0\.0\.1:11470\/Add URLReload$/ }).getByRole('img').first().click();
    await page.getByRole('radio').nth(2).click(); 

    await expect(page.getByText('Online')).toBeVisible({ timeout: 10000 });
    
    const serverUrlElement = page.getByText(serverURL);
    await expect(serverUrlElement).toBeVisible();
    
    await page.reload();
    await expect(serverUrlElement).toBeVisible();
  });
});

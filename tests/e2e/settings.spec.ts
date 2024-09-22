import { test, expect, request } from '@playwright/test';

test.describe('Stremio API and Settings', () => {
  const BASE_URL = 'http://172.18.0.3:11470';
  const WEB_URL = 'http://172.18.0.3:8080';

  test('API endpoints return expected responses', async ({ request }) => {
    const context = await request.newContext({ baseURL: BASE_URL });

    async function testEndpoint(path: string, expectedStatus = 200) {
      const response = await context.get(path);
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

  test('User can configure streaming server URL', async ({ page }) => {
    await page.goto(`${WEB_URL}/#/settings`);
    
    // Navigate to streaming settings
    await page.getByTitle('Streaming').click();
    
    // Configure server URL
    await page.getByTitle('Configure server url').getByRole('img').click();
    await page.getByPlaceholder('Enter a streaming server url').fill(BASE_URL);
    await page.getByText('Submit').click();
    
    // Verify server is online
    await expect(page.getByText('Online')).toBeVisible({ timeout: 10000 });
    
    // Additional checks
    const serverUrlElement = page.getByText(BASE_URL);
    await expect(serverUrlElement).toBeVisible();
    
    // Verify settings are saved
    await page.reload();
    await expect(serverUrlElement).toBeVisible();
  });
});

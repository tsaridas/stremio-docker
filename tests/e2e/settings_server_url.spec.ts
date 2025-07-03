import { expect } from '@playwright/test';
import { test } from './fixtures';

test.describe('Stremio API and Settings', () => {
  test('Automatically set streaming server URL', async ({ page, serverURL, webURL }) => {
    console.log('Testing settings with serverURL:', serverURL, 'webURL:', webURL);
    await page.goto(`${webURL}/#/settings`);
    
    await page.getByTitle('Streaming').click();

    await expect(page.getByText('Online')).toBeVisible({ timeout: 10000 });
    
    const serverUrlElement = page.getByText(serverURL);
    await expect(serverUrlElement).toBeVisible();
    
    await page.reload();
    await expect(serverUrlElement).toBeVisible();
  });
});

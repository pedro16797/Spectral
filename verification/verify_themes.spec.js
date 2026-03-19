import { test, expect } from '@playwright/test';

test('Verify themes in settings', async ({ page }) => {
  await page.goto('http://localhost:8080/?enable-semantics=true');
  await page.waitForTimeout(2000);

  // Open settings
  await page.getByLabel('Settings').click();
  await page.waitForTimeout(1000);

  // Take screenshot of settings to see if themes fit in one row
  await page.screenshot({ path: '/home/jules/verification/settings_themes_renamed.png' });

  // Verify theme names exist
  await expect(page.getByLabel('Frost')).toBeVisible();
  await expect(page.getByLabel('Magma')).toBeVisible();
  await expect(page.getByLabel('Gray')).toBeVisible();
  await expect(page.getByLabel('Emerald')).toBeVisible();
  await expect(page.getByLabel('Rainbow')).toBeVisible();
});

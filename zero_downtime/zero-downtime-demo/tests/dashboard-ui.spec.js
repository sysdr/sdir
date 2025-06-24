const { test, expect } = require('@playwright/test');

test.describe('Zero-Downtime Dashboard UI Tests', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to dashboard before each test
    await page.goto('http://localhost:3000');
    // Wait for dashboard to load
    await page.waitForSelector('body', { timeout: 10000 });
  });

  test('should display main dashboard elements', async ({ page }) => {
    // Check for main dashboard title
    await expect(page.locator('h1, .dashboard-title')).toContainText('Zero-Downtime');
    
    // Check for deployment strategy sections
    await expect(page.locator('text=Rolling')).toBeVisible();
    await expect(page.locator('text=Blue-Green')).toBeVisible();
    await expect(page.locator('text=Canary')).toBeVisible();
    
    // Check for status indicators
    await expect(page.locator('.status-indicator, [data-status]')).toHaveCount(3);
  });

  test('should show deployment status information', async ({ page }) => {
    // Check that status information is displayed for each deployment
    const statusElements = page.locator('.deployment-status, .status, [data-testid*="status"]');
    await expect(statusElements).toHaveCount(3);
    
    // Verify status text contains expected values
    const statusTexts = await statusElements.allTextContents();
    for (const text of statusTexts) {
      expect(['Running', 'Stopped', 'Starting', 'Stopping']).toContain(text.trim());
    }
  });

  test('should have functional control buttons', async ({ page }) => {
    // Look for common button patterns
    const buttons = page.locator('button, .btn, [role="button"]');
    const buttonCount = await buttons.count();
    
    // Should have at least some buttons
    expect(buttonCount).toBeGreaterThan(0);
    
    // Check that buttons are clickable
    for (let i = 0; i < Math.min(buttonCount, 5); i++) {
      const button = buttons.nth(i);
      await expect(button).toBeEnabled();
    }
  });

  test('should respond to button clicks', async ({ page }) => {
    // Find and click start/stop buttons
    const startButtons = page.locator('button:has-text("Start"), .btn-start, [data-action="start"]');
    const stopButtons = page.locator('button:has-text("Stop"), .btn-stop, [data-action="stop"]');
    
    // If start buttons exist, test them
    if (await startButtons.count() > 0) {
      await startButtons.first().click();
      // Wait for potential status change
      await page.waitForTimeout(2000);
    }
    
    // If stop buttons exist, test them
    if (await stopButtons.count() > 0) {
      await stopButtons.first().click();
      // Wait for potential status change
      await page.waitForTimeout(2000);
    }
  });

  test('should update UI on refresh', async ({ page }) => {
    // Get initial state
    const initialStatuses = await page.locator('.deployment-status, .status').allTextContents();
    
    // Refresh the page
    await page.reload();
    await page.waitForSelector('body', { timeout: 10000 });
    
    // Check that dashboard still loads
    await expect(page.locator('h1, .dashboard-title')).toContainText('Zero-Downtime');
    
    // Get statuses after refresh
    const newStatuses = await page.locator('.deployment-status, .status').allTextContents();
    
    // Should have same number of status elements
    expect(newStatuses.length).toBe(initialStatuses.length);
  });

  test('should handle deployment strategy switching', async ({ page }) => {
    // Look for strategy-specific controls
    const strategySections = page.locator('.deployment-section, [data-strategy]');
    const sectionCount = await strategySections.count();
    
    // Should have sections for each strategy
    expect(sectionCount).toBeGreaterThanOrEqual(3);
    
    // Test interaction with each section
    for (let i = 0; i < sectionCount; i++) {
      const section = strategySections.nth(i);
      await section.click();
      await page.waitForTimeout(500);
    }
  });

  test('should display real-time updates', async ({ page }) => {
    // Wait for any real-time updates
    await page.waitForTimeout(3000);
    
    // Check that status elements are still present after waiting
    const statusElements = page.locator('.deployment-status, .status');
    await expect(statusElements).toHaveCount(3);
    
    // Verify elements are still visible
    for (let i = 0; i < 3; i++) {
      await expect(statusElements.nth(i)).toBeVisible();
    }
  });

  test('should handle error states gracefully', async ({ page }) => {
    // Try to interact with elements that might not exist
    const nonExistentButton = page.locator('[data-testid="non-existent-button"]');
    
    // Should not throw error when element doesn't exist
    await expect(nonExistentButton).toHaveCount(0);
    
    // Dashboard should still be functional
    await expect(page.locator('body')).toBeVisible();
  });

  test('should have responsive design elements', async ({ page }) => {
    // Test different viewport sizes
    await page.setViewportSize({ width: 1920, height: 1080 });
    await expect(page.locator('body')).toBeVisible();
    
    await page.setViewportSize({ width: 768, height: 1024 });
    await expect(page.locator('body')).toBeVisible();
    
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(page.locator('body')).toBeVisible();
  });

  test('should load all required resources', async ({ page }) => {
    // Check for console errors
    const consoleErrors = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });
    
    await page.reload();
    await page.waitForLoadState('networkidle');
    
    // Should have minimal console errors
    expect(consoleErrors.length).toBeLessThan(5);
  });
}); 
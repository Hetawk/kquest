import { expect, test } from '@playwright/test';

test('has expected h1', async ({ page }) => {
	await page.goto('/');
	await expect(
		page.getByRole('heading', { level: 1, name: /make learning feel like an adventure/i })
	).toBeVisible();
	await expect(page.getByRole('link', { name: /create your first quest/i })).toBeVisible();
	await expect(page.getByRole('link', { name: /i have a game code/i })).toHaveAttribute(
		'href',
		'/join'
	);
});

test('helps learners recover from an incomplete game code', async ({ page }) => {
	await page.goto('/join');
	await page.getByLabel(/6-character game code/i).fill('ABCDE');
	await page.getByRole('button', { name: /find my game/i }).click();
	await expect(page.locator('.join-form [role="alert"]')).toContainText(/6 letters or numbers/i);
	await expect(page).toHaveURL(/\/join$/);
});

import { test, expect } from '@playwright/test'

test('switches the local agenda between week and month across a month boundary', async ({ page }) => {
  test.skip(Boolean(process.env.E2E_BASE_URL || process.env.E2E_SUPABASE_URL), 'The demo agenda check runs only in local-data mode')
  await page.goto('/appointments')
  await page.getByRole('button', { name: 'Semaine' }).click()
  await page.getByLabel('Date du planning').fill('2026-10-31')
  await expect(page.locator('.appointment-calendar-day')).toHaveCount(7)
  await page.getByRole('button', { name: 'Mois' }).click()
  await expect(page.locator('.appointment-calendar-day')).toHaveCount(31)
  await page.getByRole('button', { name: 'Période suivante' }).click()
  await expect(page.getByLabel('Date du planning')).toHaveValue('2026-11-01')
  await expect(page.locator('.appointment-calendar-day')).toHaveCount(30)
})

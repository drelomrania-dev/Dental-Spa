import { test, expect } from '@playwright/test'

test('renders the public booking entry point without patient data', async ({ page }) => {
  await page.goto('/book/consultation')
  await expect(page.getByRole('heading', { name: 'Réserver une consultation' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Quel soin souhaitez-vous ?' })).toBeVisible()
  await expect(page.getByRole('button', { name: /Consultation/ })).toBeVisible()
})

test('shows a safe state for an invalid booking-management token', async ({ page }) => {
  await page.goto('/manage-booking/invalid-test-token')
  await expect(page.getByRole('heading', { name: /Gestion en ligne indisponible|Lien indisponible/i })).toBeVisible()
  await expect(page.locator('body')).not.toContainText(/stack trace|supabase_key|password/i)
})

test('shows a safe state for an invalid staff invitation token', async ({ page }) => {
  await page.goto('/join/invalid-test-token')
  await expect(page.getByRole('heading', { name: 'Lien indisponible' })).toBeVisible()
  await expect(page.locator('body')).not.toContainText(/stack trace|supabase_key|password/i)
})

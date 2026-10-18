import { test, expect } from './fixtures.js'
import { hasAuthenticatedTarget, hasTwoAccountConfig, missingAuthenticatedTargetReason, missingTwoAccountConfigReason } from './fixtures.js'

test.describe('administrator login shell', () => {
  test.skip(!hasAuthenticatedTarget, missingAuthenticatedTargetReason)
  test('shows the administrator login shell before authentication', async ({ browser }) => {
    const context = await browser.newContext(); const page = await context.newPage()
    await page.goto('/')
    await expect(page.getByRole('heading', { name: /Connexion au cabinet/i })).toBeVisible()
    await expect(page.getByLabel('Email')).toBeVisible(); await expect(page.getByLabel('Mot de passe')).toBeVisible()
    await context.close()
  })
})

test.describe('authenticated role structure', () => {
  test.skip(!hasTwoAccountConfig, missingTwoAccountConfigReason)
  test('allows the administrator into reports and denies the assistant', async ({ adminPage, assistantPage }) => {
    await adminPage.goto('/reports'); await expect(adminPage.getByRole('heading', { name: 'Rapports' })).toBeVisible()
    await assistantPage.goto('/reports'); await expect(assistantPage.getByRole('heading', { name: 'Accès refusé' })).toBeVisible()
  })
  test('allows the assistant into appointments while keeping the session separate', async ({ adminPage, assistantPage }) => {
    await assistantPage.goto('/appointments'); await expect(assistantPage.getByRole('heading', { name: 'Rendez-vous' })).toBeVisible()
    await adminPage.goto('/settings'); await expect(adminPage.getByRole('heading', { name: 'Paramètres' })).toBeVisible()
    await expect(assistantPage).not.toHaveURL(/\/settings$/)
  })
})

import { test, expect, hasTwoAccountConfig, missingTwoAccountConfigReason } from './fixtures.js'

test.describe('clinic setup access', () => {
  test.skip(!hasTwoAccountConfig, missingTwoAccountConfigReason)
  test('shows setup and audit to administrator and denies the assistant settings route', async ({ adminPage, assistantPage }) => {
    await adminPage.goto('/settings')
    await expect(adminPage.getByRole('heading',{name:'Premiers réglages'})).toBeVisible()
    await expect(adminPage.getByRole('heading',{name:'Journal d’audit'})).toBeVisible()
    await assistantPage.goto('/settings')
    await expect(assistantPage.getByRole('heading',{name:'Accès refusé'})).toBeVisible()
  })
})

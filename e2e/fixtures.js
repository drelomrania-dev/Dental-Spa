import { test as base, expect } from '@playwright/test'

export const e2eConfig = {
  admin: { email: process.env.E2E_ADMIN_EMAIL || '', password: process.env.E2E_ADMIN_PASSWORD || '' },
  assistant: { email: process.env.E2E_ASSISTANT_EMAIL || '', password: process.env.E2E_ASSISTANT_PASSWORD || '' }
}

export const hasAuthenticatedTarget = Boolean(process.env.E2E_BASE_URL || (process.env.E2E_SUPABASE_URL && process.env.E2E_SUPABASE_ANON_KEY))
export const missingAuthenticatedTargetReason = 'Skipped: set E2E_BASE_URL for a deployed test target, or set E2E_SUPABASE_URL and E2E_SUPABASE_ANON_KEY for the local Supabase target.'
export const hasTwoAccountConfig = Boolean(hasAuthenticatedTarget && e2eConfig.admin.email && e2eConfig.admin.password && e2eConfig.assistant.email && e2eConfig.assistant.password)
export const missingTwoAccountConfigReason = 'Skipped: configure an authenticated target, then define E2E_ADMIN_EMAIL, E2E_ADMIN_PASSWORD, E2E_ASSISTANT_EMAIL, and E2E_ASSISTANT_PASSWORD.'

async function signIn(page, credentials) {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: /Connexion au cabinet/i })).toBeVisible()
  await page.getByLabel('Email').fill(credentials.email)
  await page.getByLabel('Mot de passe').fill(credentials.password)
  await page.getByRole('button', { name: 'Se connecter' }).click()
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole('heading', { name: /Bonjour/i })).toBeVisible()
}

export const test = base.extend({
  adminPage: async ({ browser }, use) => {
    const context = await browser.newContext(); const page = await context.newPage()
    await signIn(page, e2eConfig.admin); await use(page); await context.close()
  },
  assistantPage: async ({ browser }, use) => {
    const context = await browser.newContext(); const page = await context.newPage()
    await signIn(page, e2eConfig.assistant); await use(page); await context.close()
  }
})

export { expect }

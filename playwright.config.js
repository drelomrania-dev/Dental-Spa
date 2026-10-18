import { defineConfig, devices } from '@playwright/test'

const baseURL = process.env.E2E_BASE_URL || 'http://127.0.0.1:4173'
const hasSupabaseConfig = Boolean(process.env.E2E_SUPABASE_URL && process.env.E2E_SUPABASE_ANON_KEY)

export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  expect: { timeout: 7_000 },
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    locale: 'fr-FR',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: process.env.E2E_BASE_URL ? undefined : {
    command: 'pnpm dev --host 127.0.0.1 --port 4173',
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      ...process.env,
      VITE_DATA_BACKEND: hasSupabaseConfig ? 'supabase' : 'local',
      VITE_SUPABASE_URL: process.env.E2E_SUPABASE_URL || '',
      VITE_SUPABASE_ANON_KEY: process.env.E2E_SUPABASE_ANON_KEY || '',
      VITE_USE_FIREBASE: 'false',
      VITE_ENABLE_DEMO_SEED: 'false',
      VITE_PUBLIC_APP_URL: baseURL
    }
  }
})

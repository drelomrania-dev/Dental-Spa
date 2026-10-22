import { test, expect } from '@playwright/test'

const internalRoutes = [
  '/', '/acquisition', '/acquisition/phase9-audit-lead', '/patients', '/patients/p1',
  '/appointments', '/clinical', '/approvals', '/payments', '/payment-history',
  '/receivables', '/collection-sessions', '/reminders', '/reports',
  '/doctors', '/treatments', '/settings'
]
const publicRoutes = ['/book/consultation', '/intake/invalid-token', '/manage-booking/invalid-token', '/join/invalid-token']

for (const width of [390, 1440]) {
  test(`phase 9 route and control audit at ${width}px`, async ({ page }) => {
    test.skip(Boolean(process.env.E2E_BASE_URL || process.env.E2E_SUPABASE_URL), 'Synthetic demo audit only')
    await page.setViewportSize({ width, height: 844 })
    await page.goto('/')
    await page.evaluate(() => localStorage.setItem('dentalflow:acquisition:leads', JSON.stringify([{
      id: 'phase9-audit-lead', firstName: 'Audit', lastName: 'Neuf', phone: '0600999910',
      email: 'audit@example.test', source: 'Direct', status: 'Nouveau', priority: 'Normale',
      concern: 'Contrôle synthétique', notes: '', createdAt: new Date().toISOString()
    }])))
    const issues = []
    for (const route of [...internalRoutes, ...publicRoutes]) {
      const errors = []
      const onError = error => errors.push(error.message)
      page.on('pageerror', onError)
      await page.goto(route)
      await page.waitForFunction(() => [...document.querySelectorAll('h1,h2')].some(el => el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0))
      const state = await page.evaluate(() => {
        const isVisible = el => {
          const rect = el.getBoundingClientRect()
          const style = getComputedStyle(el)
          return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none'
        }
        const unnamed = [...document.querySelectorAll('input,select,textarea,button,a')]
          .filter(el => isVisible(el) && !el.disabled && el.getAttribute('aria-hidden') !== 'true')
          .filter(el => {
            if (el.tagName === 'INPUT' && el.type === 'hidden') return false
            const label = el.labels?.length ? [...el.labels].map(x => x.textContent).join(' ') : ''
            const name = el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || label || el.getAttribute('title') || (['BUTTON', 'A'].includes(el.tagName) ? el.textContent : '')
            return !name?.trim()
          })
          .map(el => el.outerHTML.slice(0, 230))
        return { overflow: document.documentElement.scrollWidth - innerWidth, unnamed }
      })
      if (state.overflow > 1 || state.unnamed.length || errors.length) issues.push({ route, ...state, errors })
      page.off('pageerror', onError)
    }
    expect(issues).toEqual([])
  })
}

test('keyboard focus and failed-save recovery in the prospect dialog', async ({ page }) => {
  test.skip(Boolean(process.env.E2E_BASE_URL || process.env.E2E_SUPABASE_URL), 'Synthetic demo audit only')
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/acquisition')
  const trigger = page.getByRole('button', { name: 'Nouveau prospect' })
  await trigger.focus()
  await page.keyboard.press('Enter')
  const dialog = page.getByRole('dialog', { name: 'Nouveau prospect' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByLabel('Prénom')).toBeFocused()
  await page.keyboard.press('Shift+Tab')
  await expect(dialog.getByRole('button', { name: 'Fermer' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(dialog).toHaveCount(0)
  await expect(trigger).toBeFocused()

  await trigger.click()
  await dialog.getByLabel('Prénom').fill('Phase')
  await dialog.getByLabel('Nom', { exact: true }).fill('Neuf')
  await dialog.getByLabel('Téléphone').fill('0600999909')
  await page.evaluate(() => {
    window.__originalSetItem = Storage.prototype.setItem
    Storage.prototype.setItem = function (key, value) {
      if (key === 'dentalflow:acquisition:leads') throw new Error('Synthetic save failure')
      return window.__originalSetItem.call(this, key, value)
    }
  })
  await dialog.getByRole('button', { name: 'Créer le prospect' }).click()
  await expect(dialog.getByRole('alert')).toContainText('Synthetic save failure')
  await expect(dialog.getByLabel('Prénom')).toHaveValue('Phase')
  await page.evaluate(() => { Storage.prototype.setItem = window.__originalSetItem })
  await dialog.getByRole('button', { name: 'Créer le prospect' }).click()
  await expect(page.getByRole('heading', { name: 'Phase Neuf', level: 1 })).toBeVisible()
})

test('assistant route denial keeps clinical and financial detail out of the DOM', async ({ page }) => {
  test.skip(Boolean(process.env.E2E_BASE_URL || process.env.E2E_SUPABASE_URL), 'Synthetic demo role audit only')
  await page.goto('/')
  await page.evaluate(() => localStorage.setItem('dentalflow:currentUser', 'u2'))
  for (const route of ['/clinical', '/reports', '/payment-history', '/settings']) {
    await page.goto(route)
    await expect(page.getByRole('heading', { name: 'Accès refusé' })).toBeVisible()
    await expect(page.locator('.main-shell')).not.toContainText('Notes cliniques')
  }
  await page.goto('/appointments')
  await expect(page.getByRole('heading', { name: 'Rendez-vous' })).toBeVisible()
})

for (const width of [390, 1440]) {
  test(`key workflow dialogs stay labelled and keyboard usable at ${width}px`, async ({ page }) => {
    test.skip(Boolean(process.env.E2E_BASE_URL || process.env.E2E_SUPABASE_URL), 'Synthetic demo audit only')
    await page.setViewportSize({ width, height: 844 })
    await page.goto('/')
    await page.evaluate(() => localStorage.setItem('dentalflow:acquisition:leads', JSON.stringify([{
      id: 'phase9-dialog-lead', firstName: 'Audit', lastName: 'Neuf', phone: '0600999910',
      source: 'Direct', status: 'Nouveau', priority: 'Normale', concern: 'Contrôle', createdAt: new Date().toISOString()
    }])))
    const cases = [
      ['/acquisition', 'Nouveau prospect'],
      ['/acquisition/phase9-dialog-lead', 'Relance'],
      ['/acquisition/phase9-dialog-lead', 'Devis'],
      ['/acquisition/phase9-dialog-lead', 'Inviter'],
      ['/patients', 'Ajouter un patient'],
      ['/appointments', 'Nouveau rendez-vous'],
      ['/clinical', 'Ouvrir une consultation'],
      ['/approvals', 'Demander une remise'],
      ['/collection-sessions', 'Ouvrir ma session']
    ]
    for (const [route, button] of cases) {
      await page.goto(route)
      const trigger = page.getByRole('button', { name: button, exact: true })
      await trigger.click()
      const dialog = page.getByRole('dialog')
      await expect(dialog).toBeVisible()
      const result = await dialog.evaluate(element => {
        const unnamed = [...element.querySelectorAll('input,select,textarea,button')].filter(control => {
          if (control.disabled || !control.getClientRects().length) return false
          const label = control.labels?.length ? [...control.labels].map(item => item.textContent).join(' ') : ''
          return !(control.getAttribute('aria-label') || label || control.getAttribute('title') || (control.tagName === 'BUTTON' ? control.textContent : '')).trim()
        }).map(control => control.outerHTML.slice(0, 180))
        return { unnamed, focusInside: element.contains(document.activeElement), overflow: document.documentElement.scrollWidth - innerWidth }
      })
      expect(result, `${route} / ${button}`).toEqual({ unnamed: [], focusInside: true, overflow: 0 })
      await page.keyboard.press('Escape')
      await expect(dialog).toHaveCount(0)
      await expect(trigger).toBeFocused()
    }
  })
}

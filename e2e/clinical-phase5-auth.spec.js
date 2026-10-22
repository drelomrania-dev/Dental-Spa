import { test, expect, hasTwoAccountConfig, hasTwoClinicConfig, missingTwoAccountConfigReason, missingTwoClinicConfigReason } from './fixtures.js'

test.describe('patient and clinical access boundaries', () => {
  test.skip(!hasTwoAccountConfig, missingTwoAccountConfigReason)
  test('keeps the clinical route and medical panel from reception', async ({ adminPage, assistantPage }) => {
    await adminPage.goto('/patients')
    const patientPath=await adminPage.getByRole('link',{name:'Test Patient A'}).getAttribute('href')
    await assistantPage.goto('/clinical')
    await expect(assistantPage.getByRole('heading',{name:'Accès refusé'})).toBeVisible()
    await assistantPage.goto(patientPath)
    await expect(assistantPage.getByRole('heading',{name:'Test Patient A'})).toBeVisible()
    await expect(assistantPage.getByText('Alertes médicales')).toHaveCount(0)
    await expect(assistantPage.getByRole('heading',{name:'Consultations'})).toHaveCount(0)
  })
})

test.describe('cross clinic patient boundary', () => {
  test.skip(!hasTwoClinicConfig, missingTwoClinicConfigReason)
  test('does not open another clinic patient timeline', async ({ adminPage, otherAdminPage }) => {
    await adminPage.goto('/patients')
    const patientPath=await adminPage.getByRole('link',{name:'Test Patient A'}).getAttribute('href')
    await otherAdminPage.goto(patientPath)
    await expect(otherAdminPage.getByRole('heading',{name:'Patient introuvable'})).toBeVisible()
  })
})

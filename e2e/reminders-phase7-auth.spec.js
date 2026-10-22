import { test, expect, hasTwoClinicConfig, missingTwoClinicConfigReason } from './fixtures.js'

test.describe('reminder permissions on local Auth',()=>{
  test.skip(!hasTwoClinicConfig,missingTwoClinicConfigReason)

  test('keeps consent and configuration within the clinic grant',async({adminPage,assistantPage,otherAdminPage})=>{
    await assistantPage.goto('/reminders')
    await expect(assistantPage.getByRole('heading',{name:'Rappels',exact:true})).toBeVisible()
    await expect(assistantPage.getByRole('heading',{name:'Modèles de message'})).toHaveCount(0)
    await assistantPage.getByLabel('Patient').selectOption('local-patient-a')
    await assistantPage.getByLabel('Preuve ou motif').fill('Synthetic local signed consent')
    await assistantPage.getByRole('button',{name:'Enregistrer la préférence'}).click()
    await expect(assistantPage.getByText('Email : Accordé')).toBeVisible()

    await adminPage.goto('/reminders')
    await expect(adminPage.getByRole('heading',{name:'Modèles de message'})).toBeVisible()
    await adminPage.getByLabel('Patient').selectOption('local-patient-a')
    await expect(adminPage.getByText('Email : Accordé')).toBeVisible()

    await otherAdminPage.goto('/reminders')
    await expect(otherAdminPage.getByRole('heading',{name:'Rappels',exact:true})).toBeVisible()
    await expect(otherAdminPage.getByLabel('Patient').locator('option',{hasText:'Test Patient A'})).toHaveCount(0)
    await expect(otherAdminPage.getByLabel('Patient').locator('option',{hasText:'Test Patient B'})).toHaveCount(1)
    await expect(otherAdminPage.getByText('Email : Accordé')).toHaveCount(0)
  })
})

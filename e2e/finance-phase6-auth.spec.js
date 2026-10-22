import { test, expect, hasTwoAccountConfig, missingTwoAccountConfigReason } from './fixtures.js'

test.describe('finance ledger and collector access on local Auth',()=>{
  test.skip(!hasTwoAccountConfig,missingTwoAccountConfigReason)

  test('keeps reception in its own cash session and exposes documents to the administrator',async({adminPage,assistantPage})=>{
    await assistantPage.goto('/collection-sessions')
    await assistantPage.getByRole('button',{name:'Ouvrir ma session'}).click()
    await assistantPage.getByLabel('Fonds de caisse initial').fill('20')
    await assistantPage.getByRole('button',{name:'Ouvrir',exact:true}).click()
    await expect(assistantPage.getByRole('heading',{name:'Session ouverte'})).toBeVisible()

    await assistantPage.goto('/payments')
    await assistantPage.getByLabel('Patient').selectOption('local-patient-a')
    await assistantPage.getByLabel('Soin').selectOption('local-consultation')
    await assistantPage.getByRole('button',{name:'2 fois'}).click()
    await assistantPage.getByLabel('Montant reçu (DH)').fill('100')
    await assistantPage.getByLabel('Moyen').selectOption('Espèces')
    await assistantPage.getByRole('button',{name:'Valider le paiement'}).click()
    await expect(assistantPage.getByText('Paiement enregistré',{exact:false}).last()).toBeVisible()
    await expect(assistantPage.locator('#receipt-print').getByText('Numéro')).toBeVisible()
    await assistantPage.goto('/receivables')
    await expect(assistantPage.getByRole('heading',{name:'Accès refusé'})).toBeVisible()

    await adminPage.goto('/receivables')
    await expect(adminPage.getByText('Test Patient A')).toBeVisible()
    await expect(adminPage.getByText('À échéance',{exact:false})).toBeVisible()
    await adminPage.goto('/collection-sessions')
    await expect(adminPage.getByText('Toutes les sessions')).toBeVisible()
    await expect(adminPage.getByText('20 DH',{exact:false})).toBeVisible()
  })
})
